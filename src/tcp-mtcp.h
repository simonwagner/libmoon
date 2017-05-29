#pragma once

#ifdef __cplusplus
extern "C" {
#endif

struct moon_mtcp_dpdk_config;
struct moon_mtcp_event_queue;

struct moon_mtcp_dpdk_config* moonmtcp_create_config();
void moonmtcp_free_config(struct moon_mtcp_dpdk_config* cfg);
int moonmtcp_configure_interface(struct moon_mtcp_dpdk_config* cfg, int interface, in_addr_t ip_addr, in_addr_t netmask, uint8_t dpdk_port);
int moonmtcp_init(struct moon_mtcp_dpdk_config* cfg);
int moonmtcp_create_tcp_socket(mctx_t mctx);
int moonmtcp_connect_ipv4(mctx_t mctx, int sockid, in_addr_t ipv4, in_port_t port);

struct moon_mtcp_event_queue* moonmtcp_create_eventqueue(mctx_t mctx, int maxevents);
int moonmtcp_eventqueue_wait(mctx_t mctx, struct moon_mtcp_event_queue* queue, int timeout);
int moonmtcp_eventqueue_add_socket(mctx_t mctx, struct moon_mtcp_event_queue* queue, int sockid, int events);

#ifdef __cplusplus
}
#endif