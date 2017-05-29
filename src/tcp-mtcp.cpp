#include <stdint.h>
#include <stdlib.h>
#include <signal.h>

extern "C" {
	#include <mtcp_api.h>
	#include <mtcp_epoll.h>
    #include <moon_mtcp.h>
}

#include "tcp-mtcp.h"
#include "lifecycle.hpp"

struct moon_mtcp_event_queue {
	int ep;
	struct mtcp_epoll_event *events;
	int maxevents;
};

struct moon_mtcp_dpdk_config* moonmtcp_create_config()
{
	struct moon_mtcp_dpdk_config* cfg = (struct moon_mtcp_dpdk_config*)calloc(sizeof(struct moon_mtcp_dpdk_config), 1);
	moon_mtcp_set_default_config(cfg);

	return cfg;
}

void moonmtcp_free_config(struct moon_mtcp_dpdk_config* cfg)
{
	free(cfg);
}

int moonmtcp_configure_interface(struct moon_mtcp_dpdk_config* cfg, int interface, in_addr_t ip_addr, in_addr_t netmask, uint8_t dpdk_port)
{
	cfg->interfaces[interface].ip_addr = ntohl(ip_addr);
	cfg->interfaces[interface].netmask = ntohl(netmask);
	cfg->interfaces[interface].dpdk_port_id = dpdk_port;

	return 0;
}

int moonmtcp_init(struct moon_mtcp_dpdk_config* cfg)
{
	int ret = mtcp_init_with_configuration_func(cfg, moon_mtcp_load_config);
	if(ret == 0) {
		mtcp_register_signal(SIGINT, &libmoon::signal_handler);
	}

	return ret;
}

int moonmtcp_create_tcp_socket(mctx_t mctx)
{
	int sockid = mtcp_socket(mctx, AF_INET, SOCK_STREAM, 0);

	return sockid;
}

int moonmtcp_connect_ipv4(mctx_t mctx, int sockid, in_addr_t ipv4, in_port_t port)
{
	struct sockaddr_in addr;
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(ipv4);
	addr.sin_port = htons(port);

	int connect_ret = mtcp_connect(mctx, sockid, (struct sockaddr *)&addr, sizeof(struct sockaddr_in));

	if(connect_ret == 0) {
		return sockid;
	}
	else {
		return connect_ret;
	}
}

struct moon_mtcp_event_queue* moonmtcp_create_eventqueue(mctx_t mctx, int maxevents)
{
	struct moon_mtcp_event_queue* queue = (struct moon_mtcp_event_queue*)calloc(1, sizeof(struct moon_mtcp_event_queue));

	queue->maxevents = maxevents;
	queue->events = (struct mtcp_epoll_event *) calloc(maxevents, sizeof(struct mtcp_epoll_event));

	queue->ep = mtcp_epoll_create(mctx, maxevents);

	return queue;
}

void moonmtcp_free_eventqueue(struct moon_mtcp_event_queue* queue)
{
	free(queue->events);
	free(queue);
}

int moonmtcp_eventqueue_wait(mctx_t mctx, struct moon_mtcp_event_queue* queue, int timeout)
{
	return mtcp_epoll_wait(mctx, queue->ep, queue->events, queue->maxevents, timeout);
}

int moonmtcp_eventqueue_add_socket(mctx_t mctx, struct moon_mtcp_event_queue* queue, int sockid, int events)
{
	struct mtcp_epoll_event ev;
	ev.events = events;
	ev.data.sockid = sockid;

	return mtcp_epoll_ctl(mctx, queue->ep, MTCP_EPOLL_CTL_ADD, sockid, &ev);
}
