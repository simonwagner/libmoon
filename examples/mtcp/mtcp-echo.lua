local lm	 = require "libmoon"
local log	 = require "log"
local mtcpc = require "mtcpc"
local mtcp = require "mtcp"
local ffi = require "ffi"
local bit = require "bit"
local syscall = require "syscall"
local device = require "device"

ffi.cdef [[
char *strerror(int errnum);
void *memmove(void *dest, const void *src, size_t n);
]]

local function strerror(e)
	return ffi.string(ffi.C.strerror(e))
end

function configure(parser)
	parser:option("-p --dpdk-port", "Devices to use."):args(1)
	parser:option("-a --address", "Local address to use."):args(1)
	parser:option("-m --netmask", "Local netmask to use."):args(1)
	parser:option("-H --host", "Remote hosts to connect to."):args("+"):action("concat")
	parser:option("-P --port", "Remote port to connect to."):args(1):convert(tonumber)
	parser:option("-c --cores", "number of cores mTCP will use"):args(1):convert(tonumber):default(1)
	parser:option("-n --concurrency", "number of connections per core"):args(1):convert(tonumber):default(1)
	parser:option("--pidfile", "pidfile location"):args(1):default("/dev/null")
	parser:option("--send-buffer", "send buffer size"):args(1):convert(tonumber):default(1460)
	parser:option("--receive-buffer", "receive buffer size"):args(1):convert(tonumber):default(1460)

	local args = parser:parse()

	return args
end

function master(args)
	-- write pid to file
	if args.pidfile ~= "/dev/null" then
		log:info("Writing PID to %s", args.pidfile)
		pidfile = io.open(args.pidfile, "w")
		io.output(pidfile)
		io.write(syscall.getpid())
		io.close(pidfile)
	end
	-- get correct device
	pci_address = args.dpdk_port:match("^pci@(.*)$")
	if pci_address ~= nil then
		matching_device = device.getByPciAddress(pci_address)
		if matching_device ~= nil then
			dpdk_port = matching_device.id
		else
			log:error("Device with PCI address %s not found", pci_address)
			return
		end
	else
		dpdk_port = tonumber(args.dpdk_port)
	end
	-- configure mtcp
	log:info("Configuring mtcp on %d cores...", args.cores)
	local mtcpConfig = mtcp.configure({
									   num_cores=args.cores,
									   num_mem_ch=1,
									   interfaces_count=1,
									   max_concurrency=args.cores + args.concurrency,
									   rcvbuf_size=args.receive_buffer,
									   sndbuf_size=args.send_buffer})
	mtcpConfig:configureInterface(0, args.address, args.netmask, dpdk_port)

	log:info("Initializing mtcp...")
	mtcp.init(mtcpConfig)

	-- start echo task
	for mtcpCore = 0, args.cores - 1 do
		local mtcpNetworkLCore = 4 + 2*mtcpCore + 1
		local mtcpApplicationLCore = 4 + 2*mtcpCore
		log:info("Starting mtcp Task %d with app on core %d, network on %d...", mtcpCore, mtcpApplicationLCore, mtcpNetworkLCore)
		lm.startTaskOnCore(mtcpApplicationLCore, "echo", mtcpNetworkLCore, mtcpCore, args)
	end
	log:info("Waiting for Tasks to finish...")
	lm.waitForTasks()
end

local function write(mctx, context, sockid)
	-- allocate buffer
	local BUF_SIZE = 1448
	local buffer = context[sockid].buffer
	local buffer_offset = context[sockid].buffer_offset
	local running = context[sockid].running

	if buffer == nil then
		buffer = ffi.new("char[?]", BUF_SIZE)
	end

	local bytes_to_read = BUF_SIZE - buffer_offset;
	ffi.fill(buffer + buffer_offset, bytes_to_read)

	local bytes_read = bytes_to_read
	local write_more = true

	while write_more and running and lm.running() do
		if bytes_read < 0 then
			loge:error("error reading data");
			running = false
			break
		end

		local bytes_to_write = bytes_read + buffer_offset;
		local bytes_written = mtcpc.mtcp_write(mctx, sockid, buffer, bytes_to_write)
		if bytes_written < bytes_to_write then
			write_more = false -- do no longer try to write more data, wait until write is called again
		end
		if bytes_written < 0 and not errno == EAGAIN then
			log:error("Error, could not write data: mtcp_write returned %d", bytes_written)
			running = false
			break
		end

		if bytes_read < bytes_to_read then
			log:info("Finished sending data")
			running = false
			break
		end

		-- move unsend bytes to beginning of the buffer
		if bytes_written > 0 and bytes_written < bytes_to_write then
			ffi.C.memmove(buffer, buffer + bytes_written, BUF_SIZE - bytes_written);
			buffer_offset = bytes_written
		elseif bytes_written >= bytes_to_write then
			buffer_offset = 0
		end
	end

	running = running and lm.running()

	context[sockid].running = running
	context[sockid].buffer = buffer
	context[sockid].buffer_offset = buffer_offset
end

local function error(mctx, context, sockid, errorcode)
	log:error("Error occurred on socket %d", sockid)
end

local function read(mctx, context, sockid)
end

function echo(core, mtcpCore, args)
	local core = lm.getCore()

	log:info("Setting up mTCP context on lcore %d", core)

	local mctx = mtcpc.mtcp_create_context_on_lcore(mtcpCore, core + 1)
	
	log:info("Hosts: %d", #args.host)
	log:info("Host0: %s", args.host[1])
	mtcp.initRSS(mctx, 2, args.host[1], args.port) -- TODO: fix this

	log:info("Creating event queue...")
	queue = mtcp.createEventQueue(mctx, args.concurrency) -- save at least enough space for all connect events, might not be a good idea

	local context = {}
	for i = 1, args.concurrency do
		host = args.host[(i % #args.host) + 1]
		log:info("Connecting socket to %s:%d...", host, args.port)
		local sockid = mtcp.connectIPv4NonBlocking(mctx, host, args.port, queue, bit.bor(mtcpc.MTCP_EPOLLOUT, mtcpc.MTCP_EPOLLERR))
		if sockid < 0 then
			log:error("Failed to establish connection: errno %d", sockid)
			return
		else
			log:info("Connection established!")
		end

		context[sockid] = {
			running = true,
			buffer = nil,
			buffer_offset = 0,
		}
	end

	while lm.running() do -- check if Ctrl+c was pressed
		queue:dispatch(mctx, -1, context, write, read, error)
	end

	log:info("Exiting...")
	mtcpc.mtcp_destroy_context(mctx)
	log:info("done.")
end
