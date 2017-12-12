local mod = {}

local ffi = require "ffi"
local mtcpc = require "mtcpc"
local utils = require "utils"
local bit = require "bit"
local S = require "syscall"

local log	 = require "log"

mod.INADDR_ANY = 0x00000000
mod.INADDR_BROADCAST = 0xffffffff

function mod.configure(options)--num_cores, num_memory_channels, num_interfaces, num_connections_per_core)
	local config = mtcpc.moonmtcp_create_config()
	if config == nil then
		return config
	end

	config.num_cores = assert(options["num_cores"])
	config.num_mem_ch = assert(options["num_mem_ch"])
	config.interfaces_count = assert(options["interfaces_count"])
	config.max_concurrency = assert(options["max_concurrency"])
	config.max_num_buffers = config.max_concurrency
	config.rcvbuf_size = options["rcvbuf_size"] or config.rcvbuf_size
	config.sndbuf_size = options["sndbuf_size"] or config.rcvbuf_size
	config.tcp_timeout = options["tcp_timeout"] or config.tcp_timeout
	config.tcp_timewait = options["tcp_timewait"] or config.tcp_timewait

	return config
end

function mod.init(configuration)
	return mtcpc.moonmtcp_init(configuration)
end

local function configureInterface(configuration, interface_index, address, netmask, dpdk_port)
	local address_int = parseIP4Address(address)
	local netmask_int = parseIP4Address(netmask)

	assert(address_int ~= nil, "Invalid IP Address: "..address)
	assert(netmask_int ~= nil, "Invalid Netmask: "..netmask)

	mtcpc.moonmtcp_configure_interface(configuration, interface_index, address_int, netmask_int, dpdk_port)
end

local function freeConfig(configuration)
	mtcpc.moonmtcp_free_config(configuration)
end


local mt_moon_mtcp_dpdk_config = {
	__index = {
		configureInterface = configureInterface,
	},
	__gc = freeConfig,
}

mod.moon_mtcp_dpdk_config = ffi.metatype("struct moon_mtcp_dpdk_config", mt_moon_mtcp_dpdk_config)

function mod.initRSS(mctx, addressPoolSize, dstIPv4Address, dstPort)
	local dstIPv4Address_int = bswap(parseIP4Address(dstIPv4Address))
	mtcpc.mtcp_init_rss(mctx, 0, addressPoolSize, dstIPv4Address_int, bswap16(dstPort))
end

function mod.connectIPv4(mctx, ipv4Address, port)
	local address_int = parseIP4Address(ipv4Address)
	local sockid = mtcpc.moonmtcp_create_tcp_socket(mctx)

	local ret = mtcpc.moonmtcp_connect_ipv4(mctx, sockid, address_int, port)
	if ret > 0 then
		return sockid
	else
		return ret
	end
end

function mod.connectIPv4NonBlocking(mctx, ipv4Address, port, queue, events)
	local address_int = parseIP4Address(ipv4Address)
	local sockid = mtcpc.moonmtcp_create_tcp_socket(mctx)

	local addQueueError =  queue:addSocket(mctx, sockid, events)
	if addQueueError < 0 then
		return addQueueError
	end

	local ret = mtcpc.moonmtcp_connect_ipv4(mctx, sockid, address_int, port)

	if ret > 0 then
		mtcpc.mtcp_setsock_nonblock(mctx, sockid)
		return sockid
	else
		return ret
	end
end

function mod.listenIPv4NonBlocking(mctx, ipv4Address, port, backlog, queue, events)
	local address_int = nil
	
	if not ipv4Address == nil then
		address_int = parseIP4Address(ipv4Address)
	else
		address_int = mod.INADDR_ANY
	end

	local sockid = mtcpc.moonmtcp_create_tcp_socket(mctx)
	mtcpc.mtcp_setsock_nonblock(mctx, sockid)
	
	local ret = 0
	
	ret = mtcpc.moonmtcp_bind(mctx, sockid, address_int, port)
	if ret < 0 then
		return ret
	end
	
	ret = mtcpc.mtcp_listen(mctx, sockid, backlog)
	if ret < 0 then
		return ret
	end

	ret = queue:addSocket(mctx, sockid, events)
	
	if ret < 0 then
		return ret
	else
		return sockid
	end
end

function mod.acceptNonBlocking(mctx, listener)
	local address = S.types.t.sockaddr_in()
	local length = S.types.t.socklen1()
	
	local sockid = mtcpc.mtcp_accept(mctx, listener, S.types.pt.sockaddr(address), length)
	
	if sockid < 0 then
		return sockid, nil, 0
	end
	
	mtcpc.mtcp_setsock_nonblock(mctx, sockid)
	
	local addressInt = ntoh(address.sin_addr.s_addr)
	local port = ntoh16(address.sin_port)
	
	local addressString = ip4ToString(addressInt)
	
	return sockid, addressString, port
end

function mod.createEventQueue(mctx, maxevents)
	local queue = mtcpc.moonmtcp_create_eventqueue(mctx, maxevents)

	return queue
end

local function freeEventQueue(queue)
	local queue = mtcpc.moonmtcp_free_eventqueue(mctx, maxevents)

	return queue
end

local function dispatchOnEventQueue(queue, mctx, timeout, context, writeCallback, readCallback, errorCallback)
	local nevents = mtcpc.moonmtcp_eventqueue_wait(mctx, queue, timeout)

	if nevents < 0 then
		return nevents
	end

	for i = 0, nevents - 1 do
		event = queue.events[i]
		if event == nil then
			return -1
		end
		sockid = event.data.sockid

		if bit.band(event.events, mtcpc.MTCP_EPOLLERR) > 0 then
			local length = S.types.t.socklen1()
			local errorCode = ffi.new("int[1]")

			mtcpc.mtcp_getsockopt(mctx, sockid, S.c.SOL.SOCKET, S.c.SO.ERROR, errorCode, length)
			errorCallback(mctx, context, sockid, tonumber(errorCode[0]))
		end
		if bit.band(event.events, mtcpc.MTCP_EPOLLIN) > 0 then
			readCallback(mctx, context, sockid)
		end
		if bit.band(event.events, mtcpc.MTCP_EPOLLOUT) > 0 then
			writeCallback(mctx, context, sockid)
		end
	end

	return 0
end

local function addSocketToQueue(queue, mctx, sockid, events)
	return mtcpc.moonmtcp_eventqueue_add_socket(mctx, queue, sockid, events)
end

local mt_moon_mtcp_event_queue = {
	__index = {
		dispatch = dispatchOnEventQueue,
		addSocket = addSocketToQueue,
	},
	__gc = freeEventQueue,
}

mod.moon_mtcp_event_queue = ffi.metatype("struct moon_mtcp_event_queue", mt_moon_mtcp_event_queue)

return mod
