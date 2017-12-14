local lm	 = require "libmoon"
local log	 = require "log"
local lwipdpdk = require "lwipdpdk"
local ffi = require "ffi"
local bit = require "bit"
local syscall = require "syscall"
local device = require "device"
require "utils"

ffi.cdef[[
struct client_arg { struct lwip_dpdk_context* context; char* buffer; int buffer_size; };
]]


function configure(parser)
	parser:option("-p --dpdk-port", "Devices to use."):args(1)
	parser:option("-a --address", "Local address to use."):args(1)
	parser:option("-m --netmask", "Local netmask to use."):args(1)
	parser:option("-H --host", "Remote hosts to connect to."):args("+"):action("concat")
	parser:option("-P --port", "Remote port to connect to."):args(1):convert(tonumber)
	parser:option("-c --cores", "number of cores lwip will use"):args(1):convert(tonumber):default(1)
	parser:option("-n --concurrency", "number of connections per core"):args(1):convert(tonumber):default(1)
	parser:option("--pidfile", "pidfile location"):args(1):default("/dev/null")

	local args = parser:parse()

	return args
end

function ipaddr_from_str(str)
	addr = ffi.new("ip4_addr_t[1]")
	if lwipdpdk.lwip_dpdk_ip4addr_aton(str, addr) > 0 then
		return addr
	else
		return nil
	end
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
	
	log:info("Configuring lwip on %d cores...", args.cores)
	local global_context = lwipdpdk.lwip_dpdk_init()
	
	log:info("Configuring network interface...")
	local local_ip_addr = lwipdpdk
	lwipdpdk.lwip_dpdk_global_netif_create(global_context,
	                              dpdk_port,
								  ipaddr_from_str(args.address),
								  ipaddr_from_str(args.netmask),
								  ipaddr_from_str("0.0.0.0"))
	
	local contexts = {}
	for core = 0, args.cores - 1 do
		contexts[core] = lwipdpdk.lwip_dpdk_context_create(global_context, core)
	end
	
	log:info("Configuration done, starting lwip stack...")
	if lwipdpdk.lwip_dpdk_start(global_context) < 0 then
		log:error("Failed to start lwip stack")
	end

	-- start tasks
	for core = 0, args.cores - 1 do
		log:info("Starting client on core %d", core)
		lm.startTaskOnCore(core + 1, "client", contexts[core], core, args)
	end
	log:info("Waiting for Tasks to finish...")
	lm.waitForTasks()
	
	lwipdpdk.lwip_dpdk_close(global_context)
end

local function sent(arg, pcb, len)
	arg = ffi.cast("struct client_arg*", arg)
	local available = lwipdpdk.lwip_dpdk_tcp_sndbuf(pcb)
	local context = arg.context
	local buffer = arg.buffer
	local buffer_size = arg.buffer_size
	
	lwipdpdk.lwip_dpdk_tcp_write(context, pcb, buffer, buffer_size, lwipdpdk.TCP_WRITE_FLAG_MORE)
	
	return lwipdpdk.ERR_OK
end


local function read(arg, pcb, p, err)
	arg = ffi.cast("struct client_arg*", arg)
	local context = arg.context
	lwipdpdk.lwip_dpdk_tcp_recved(context, pcb, p.len)
	
	return lwipdpdk.ERR_OK
end

local function connected(arg, pcb, error)
	arg = ffi.cast("struct client_arg*", arg)
	if error == lwipdpdk.ERR_OK then
		log:info("Connected")
	else
		log:error("Connection error %d", error)
	end
	
	local available = lwipdpdk.lwip_dpdk_tcp_sndbuf(pcb)
    local context = arg.context
    local buffer = arg.buffer
    local buffer_size = arg.buffer_size

    lwipdpdk.lwip_dpdk_tcp_write(context, pcb, buffer, buffer_size, 0)
	
	return lwipdpdk.ERR_OK
end

function client(context, core, args)
	-- disable JIT
	jit.off()
	log:info("running client on core %d", core)
	
	local BUFFER_SIZE = 1448

	local connection = lwipdpdk.lwip_dpdk_tcp_new(context)
	
	local pcb_args = {}
	local pcb_arg = ffi.new("struct client_arg")
	pcb_arg.context = context
	pcb_arg.buffer = ffi.new("char[?]", BUFFER_SIZE)
	pcb_arg.buffer_size = BUFFER_SIZE

	lwipdpdk.lwip_dpdk_tcp_arg(context, connection, pcb_arg)
	lwipdpdk.lwip_dpdk_tcp_sent(context, connection, sent)
	lwipdpdk.lwip_dpdk_tcp_recv(context, connection, read)
	
	pcb_args[connection] = pcb_arg -- keep reference, so we can free it later
	
	local host = args.host[1]

	lwipdpdk.lwip_dpdk_tcp_connect(context, connection, bswap(parseIP4Address(host)), args.port, connected)
	
	log:info("Starting dispatching I/O...")
	while lm.running() do -- check if Ctrl+c was pressed
		lwipdpdk.lwip_dpdk_context_handle_timers(context)
		lwipdpdk.lwip_dpdk_context_dispatch_input(context)
	end
	log:info("Finished")
end
