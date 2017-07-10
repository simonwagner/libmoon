local lm	 = require "libmoon"
local log	 = require "log"
local mtcpc = require "mtcpc"
local mtcp = require "mtcp"
local ffi = require "ffi"
local bit = require "bit"
local E = require "syscall".c.E

ffi.cdef [[
char *strerror(int errnum);
void *memmove(void *dest, const void *src, size_t n);
]]

local function strerror(e)
	return ffi.string(ffi.C.strerror(e))
end

function configure(parser)
	parser:option("-p --dpdk-port", "Devices to use."):args(1):convert(tonumber)
	parser:option("-a --address", "Local address to use."):args(1)
	parser:option("-m --netmask", "Local netmask to use."):args(1)
	parser:option("-P --port", "Port to listen on"):args(1):convert(tonumber)
	parser:option("-c --cores", "number of cores mTCP will use"):args(1):convert(tonumber):default(1)
	parser:option("-n --concurrency", "number of connections per core"):args(1):convert(tonumber):default(1)
	parser:option("--send-buffer", "send buffer size"):args(1):convert(tonumber):default(1460)
	parser:option("--receive-buffer", "receive buffer size"):args(1):convert(tonumber):default(1460)

	local args = parser:parse()

	return args
end

function master(args)
	-- configure mtcp
	log:info("Configuring mtcp on %d cores...", args.cores)
	local mtcpConfig = mtcp.configure({
									   num_cores=args.cores,
									   num_mem_ch=1,
									   interfaces_count=1,
									   max_concurrency=args.cores + args.concurrency + args.cores,
									   rcvbuf_size=args.receive_buffer,
									   sndbuf_size=args.send_buffer})
	mtcpConfig:configureInterface(0, args.address, args.netmask, args.dpdk_port)

	log:info("Initializing mtcp...")
	mtcp.init(mtcpConfig)
	
	-- start task for listening for new connections
	local mtcpListeningNetworkLCore = 5
	local mtcpListeningApplicationLCore = 4
	local mtcpListeningCore = 0

	log:info("Starting mtcp Task %d for listening on core %d, network on %d...", mtcpListeningCore, mtcpListeningApplicationLCore, mtcpListeningNetworkLCore)
	
	-- start tasks for communicating with clients
	for mtcpCore = 0, args.cores - 1 do
		local mtcpNetworkLCore = 4 + 2*mtcpCore + 1
		local mtcpApplicationLCore = 4 + 2*mtcpCore
		log:info("Starting mtcp Task %d with app on core %d, network on %d...", mtcpCore, mtcpApplicationLCore, mtcpNetworkLCore)
		lm.startTaskOnCore(mtcpApplicationLCore, "listen", mtcpNetworkLCore, mtcpCore, args)
	end
	log:info("Waiting for Tasks to finish...")
	lm.waitForTasks()
end

local function write(mctx, context, sockid)
	
end

local function error(mctx, context, sockid, errorcode)
	log:error("Error occurred on socket %d: %s (%d)", sockid, strerror(errorcode), errorcode)
end

local function accept(mctx, context, listener)
	log:info("Got connections...")
	
	while true do
		local sockid, address, port = mtcp.acceptNonBlocking(mctx, listener)
		local errno = ffi.errno()
		if sockid < 0 and not errno == E.AGAIN then
			log:error("Failed to accept connection, error code %d", sockid)
			return
		elseif sockid < 0 and errno == E.AGAIN then
			return -- no sockets anymore to accept
		end
	
		local queue = context[listener].queue
	
		log:info("Accepted connection from %s:%d on socket %d", address, port, sockid)
		
		context[sockid] = {
			running = true,
			buffer = nil,
			buffer_offset = 0,
			listening = false,
			queue = nil,
			address = address,
			port = port,
		}
		queue:addSocket(mctx, sockid, mtcpc.MTCP_EPOLLIN, mtcpc.MTCP_EPOLLERR)
	end
end

local function read(mctx, context, sockid)
	local BUF_SIZE = 1448
	
	log:info("received read event on socket %d", sockid)
	
	if context[sockid] == nil then
		log:error("No context found for socket")
		return
	end
	if context[sockid].listening then
		accept(mctx, context, sockid)
		return
	end
	
	local buffer = context[sockid].buffer
	if buffer == nil then
		buffer = ffi.new("char[?]", BUF_SIZE)
	end
	
	local bytes_read = tonumber(mtcpc.mtcp_read(mctx, sockid, buffer, BUF_SIZE))
	
	log:info("%d Bytes received from %s:%d", bytes_read, context[sockid].address, context[sockid].port)
	dumpHex(buffer, bytes_read)
end

function listen(core, mtcpCore, args)
	local core = lm.getCore()

	log:info("Setting up mTCP context on lcore %d", core)

	local mctx = mtcpc.mtcp_create_context_on_lcore(mtcpCore, core + 1)

	--mtcp.initRSS(mctx, 10, args.host, args.port)

	log:info("Creating event queue...")
	queue = mtcp.createEventQueue(mctx, args.concurrency) -- save at least enough space for all connect events, might not be a good idea

	local context = {}
	
	log:info("Listening on port %d on mtcp core %d (lcore %d)...", args.port, mtcpCore, core)
	local sockid = mtcp.listenIPv4NonBlocking(mctx, nil, args.port, math.min(1024, args.concurrency), queue, bit.bor(mtcpc.MTCP_EPOLLIN, mtcpc.MTCP_EPOLLERR))
	if sockid < 0 then
		log:error("Failed to bind socket: errno %d", sockid)
		return
	else
		log:info("Socket %d is listening now", sockid)
	end

	context[sockid] = {
		running = true,
		buffer = nil,
		buffer_offset = 0,
		listening = true,
		queue = queue,
		address = nil,
		port = args.port,
	}

	while lm.running() do -- check if Ctrl+c was pressed
		queue:dispatch(mctx, -1, context, write, read, error)
	end

	log:info("Exiting...")
	mtcpc.mtcp_destroy_context(mctx)
	log:info("done.")
end
