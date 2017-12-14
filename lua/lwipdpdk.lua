local ffi = require "ffi"

ffi.cdef[[

struct tcp_pcb;
struct lwip_dpdk_context;
struct pbuf;
struct lwip_dpdk_global_context;
struct lwip_dpdk_global_netif;

struct ip4_addr {
  uint32_t addr;
};

typedef int8_t lwip_dpdk_err_t;
typedef struct ip4_addr ip4_addr_t;
typedef ip4_addr_t ip_addr_t;

/** Definitions for error constants. */
typedef enum {
/** No error, everything OK. */
  ERR_OK         = 0,
/** Out of memory error.     */
  ERR_MEM        = -1,
/** Buffer error.            */
  ERR_BUF        = -2,
/** Timeout.                 */
  ERR_TIMEOUT    = -3,
/** Routing problem.         */
  ERR_RTE        = -4,
/** Operation in progress    */
  ERR_INPROGRESS = -5,
/** Illegal value.           */
  ERR_VAL        = -6,
/** Operation would block.   */
  ERR_WOULDBLOCK = -7,
/** Address in use.          */
  ERR_USE        = -8,
/** Already connecting.      */
  ERR_ALREADY    = -9,
/** Conn already established.*/
  ERR_ISCONN     = -10,
/** Not connected.           */
  ERR_CONN       = -11,
/** Low-level netif error    */
  ERR_IF         = -12,

/** Connection aborted.      */
  ERR_ABRT       = -13,
/** Connection reset.        */
  ERR_RST        = -14,
/** Connection closed.       */
  ERR_CLSD       = -15,
/** Illegal argument.        */
  ERR_ARG        = -16
} err_enum_t;

/* those are defines in lwip, define them here as enums */
enum tcp_write_flags {
	TCP_WRITE_FLAG_COPY = 0x01,
	TCP_WRITE_FLAG_MORE = 0x02
};

struct lwip_dpdk_global_context* lwip_dpdk_init();
int lwip_dpdk_start(struct lwip_dpdk_global_context* global_context);
void lwip_dpdk_close(struct lwip_dpdk_global_context* global_context);

struct lwip_dpdk_context* lwip_dpdk_context_create(struct lwip_dpdk_global_context* global_context, uint8_t lcore);
int lwip_dpdk_context_dispatch_input(struct lwip_dpdk_context* context);
void lwip_dpdk_context_handle_timers(struct lwip_dpdk_context* context);

struct lwip_dpdk_global_netif* lwip_dpdk_global_netif_create(struct lwip_dpdk_global_context* global_context, uint8_t port_id, const ip_addr_t* ipaddr, const ip_addr_t* netmask, const ip_addr_t* gw);

typedef lwip_dpdk_err_t (*lwip_dpdk_tcp_connected_fn)(void *arg, struct tcp_pcb *tpcb, lwip_dpdk_err_t err);
typedef lwip_dpdk_err_t (*lwip_dpdk_tcp_sent_fn)(void *arg, struct tcp_pcb *tpcb, uint16_t len);
typedef lwip_dpdk_err_t (*lwip_dpdk_tcp_recv_fn)(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, lwip_dpdk_err_t err);

struct tcp_pcb * lwip_dpdk_tcp_new(struct lwip_dpdk_context* context);
lwip_dpdk_err_t lwip_dpdk_tcp_bind(struct lwip_dpdk_context* context, struct tcp_pcb *pcb, uint32_t ipaddr, uint16_t port);
lwip_dpdk_err_t lwip_dpdk_tcp_connect(struct lwip_dpdk_context* context, struct tcp_pcb *pcb, uint32_t ipaddr, uint16_t port, lwip_dpdk_tcp_connected_fn connected);
lwip_dpdk_err_t lwip_dpdk_tcp_write(struct lwip_dpdk_context* context, struct tcp_pcb *pcb, const void *dataptr, uint16_t len, uint8_t apiflags);
lwip_dpdk_err_t lwip_dpdk_tcp_output(struct lwip_dpdk_context* context, struct tcp_pcb *pcb);
void lwip_dpdk_tcp_recved(struct lwip_dpdk_context* context, struct tcp_pcb *pcb, uint16_t len);
lwip_dpdk_err_t lwip_dpdk_tcp_close(struct lwip_dpdk_context* context, struct tcp_pcb *pcb);
void lwip_dpdk_tcp_sent(struct lwip_dpdk_context* context, struct tcp_pcb *pcb, lwip_dpdk_tcp_sent_fn sent);
void lwip_dpdk_tcp_arg(struct lwip_dpdk_context* context, struct tcp_pcb * pcb, void * arg);
void lwip_dpdk_tcp_err(struct lwip_dpdk_context* context, struct tcp_pcb * pcb, void (*err)(void *, lwip_dpdk_err_t));
void lwip_dpdk_tcp_recv(struct lwip_dpdk_context* context, struct tcp_pcb *pcb, lwip_dpdk_tcp_recv_fn recv);
uint32_t lwip_dpdk_tcp_sndbuf(struct tcp_pcb *pcb);
int lwip_dpdk_ip4addr_aton(const char *cp, struct ip4_addr *addr);

]]

return ffi.C