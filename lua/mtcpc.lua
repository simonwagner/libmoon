---------------------------------
--- @file mtcpc.lua
--- @brief C APIs from mtcp
---------------------------------


local ffi = require "ffi"

ffi.cdef[[

//BEGIN typdefs from system

typedef uint32_t in_addr_t;

//END typedefs from system

//BEGIN mtcp_api.h

enum socket_type
{
	MTCP_SOCK_UNUSED,
	MTCP_SOCK_STREAM,
	MTCP_SOCK_PROXY,
	MTCP_SOCK_LISTENER,
	MTCP_SOCK_EPOLL,
	MTCP_SOCK_PIPE,
};

struct mtcp_conf
{
	int num_cores;
	int max_concurrency;

	int max_num_buffers;
	int rcvbuf_size;
	int sndbuf_size;

	int tcp_timewait;
	int tcp_timeout;
};

typedef struct mtcp_context *mctx_t;

int
mtcp_init(char *config_file);

int
mtcp_init_with_configuration_func(void *context, int (*load_configuration)(void*));

void
mtcp_destroy();

int
mtcp_getconf(struct mtcp_conf *conf);

int
mtcp_setconf(const struct mtcp_conf *conf);

int
mtcp_core_affinitize(int cpu);

mctx_t
mtcp_create_context(int cpu);

mctx_t
mtcp_create_context_on_lcore(int mtcp_cpu, int lcore);

void
mtcp_destroy_context(mctx_t mctx);

typedef void (*mtcp_sighandler_t)(int);

mtcp_sighandler_t
mtcp_register_signal(int signum, mtcp_sighandler_t handler);

int
mtcp_pipe(mctx_t mctx, int pipeid[2]);

int
mtcp_getsockopt(mctx_t mctx, int sockid, int level,
		int optname, void *optval, socklen_t *optlen);

int
mtcp_setsockopt(mctx_t mctx, int sockid, int level,
		int optname, const void *optval, socklen_t optlen);

int
mtcp_setsock_nonblock(mctx_t mctx, int sockid);

/* mtcp_socket_ioctl: similar to ioctl,
   but only FIONREAD is supported currently */
int
mtcp_socket_ioctl(mctx_t mctx, int sockid, int request, void *argp);

int
mtcp_socket(mctx_t mctx, int domain, int type, int protocol);

int
mtcp_bind(mctx_t mctx, int sockid,
		const struct sockaddr *addr, socklen_t addrlen);

int
mtcp_listen(mctx_t mctx, int sockid, int backlog);

int
mtcp_accept(mctx_t mctx, int sockid, struct sockaddr *addr, socklen_t *addrlen);

int
mtcp_init_rss(mctx_t mctx, in_addr_t saddr_base, int num_addr,
		in_addr_t daddr, in_addr_t dport);

int
mtcp_connect(mctx_t mctx, int sockid,
		const struct sockaddr *addr, socklen_t addrlen);

int
mtcp_close(mctx_t mctx, int sockid);

ssize_t
mtcp_read(mctx_t mctx, int sockid, char *buf, size_t len);

/* readv should work in atomic */
int
mtcp_readv(mctx_t mctx, int sockid, struct iovec *iov, int numIOV);

ssize_t
mtcp_write(mctx_t mctx, int sockid, char *buf, size_t len);

/* writev should work in atomic */
int
mtcp_writev(mctx_t mctx, int sockid, struct iovec *iov, int numIOV);

//END mtcp_api.h

//BEGIN mtcp_epoll.h

/*----------------------------------------------------------------------------*/
enum mtcp_epoll_op
{
	MTCP_EPOLL_CTL_ADD = 1,
	MTCP_EPOLL_CTL_DEL = 2,
	MTCP_EPOLL_CTL_MOD = 3,
};
/*----------------------------------------------------------------------------*/
enum mtcp_event_type
{
	MTCP_EPOLLNONE	= 0x000,
	MTCP_EPOLLIN	= 0x001,
	MTCP_EPOLLPRI	= 0x002,
	MTCP_EPOLLOUT	= 0x004,
	MTCP_EPOLLRDNORM	= 0x040,
	MTCP_EPOLLRDBAND	= 0x080,
	MTCP_EPOLLWRNORM	= 0x100,
	MTCP_EPOLLWRBAND	= 0x200,
	MTCP_EPOLLMSG		= 0x400,
	MTCP_EPOLLERR		= 0x008,
	MTCP_EPOLLHUP		= 0x010,
	MTCP_EPOLLRDHUP		= 0x2000,
	MTCP_EPOLLONESHOT	= (1 << 30),
	MTCP_EPOLLET		= (1 << 31)
};
/*----------------------------------------------------------------------------*/
typedef union mtcp_epoll_data
{
	void *ptr;
	int sockid;
	uint32_t u32;
	uint64_t u64;
} mtcp_epoll_data_t;
/*----------------------------------------------------------------------------*/
struct mtcp_epoll_event
{
	uint32_t events;
	mtcp_epoll_data_t data;
};
/*----------------------------------------------------------------------------*/
int
mtcp_epoll_create(mctx_t mctx, int size);
/*----------------------------------------------------------------------------*/
int
mtcp_epoll_ctl(mctx_t mctx, int epid,
		int op, int sockid, struct mtcp_epoll_event *event);
/*----------------------------------------------------------------------------*/
int
mtcp_epoll_wait(mctx_t mctx, int epid,
		struct mtcp_epoll_event *events, int maxevents, int timeout);
/*----------------------------------------------------------------------------*/
char *
EventToString(uint32_t event);
/*----------------------------------------------------------------------------*/

//END mtcp_epoll.h

//BEGIN tcp-mtcp.h

//TODO: moon_mtcp_interface and moon_mtcp_dpdk_config maybe should be private API
struct moon_mtcp_interface {
	uint32_t ip_addr;
	uint32_t netmask;

	uint8_t dpdk_port_id;
};

struct moon_mtcp_dpdk_config {
	int num_cores;
	int max_concurrency;
	int max_num_buffers;
	int num_mem_ch;


	int rcvbuf_size;
	int sndbuf_size;
	int tcp_timeout;
	int tcp_timewait;

	_Bool multi_process;

	int interfaces_count;
	struct moon_mtcp_interface interfaces[16];
};

struct moon_mtcp_event_queue {
	int ep;
	struct mtcp_epoll_event *events;
	int maxevents;
};

struct moon_mtcp_dpdk_config* moonmtcp_create_config();
void moonmtcp_free_config(struct moon_mtcp_dpdk_config* cfg);
int moonmtcp_configure_interface(struct moon_mtcp_dpdk_config* cfg, int interface, in_addr_t ip_addr, in_addr_t netmask, uint8_t dpdk_port);
int moonmtcp_init(struct moon_mtcp_dpdk_config* cfg);
int moonmtcp_create_tcp_socket(mctx_t mctx);
int moonmtcp_connect_ipv4(mctx_t mctx, int sockid, in_addr_t ipv4, in_port_t port);

struct moon_mtcp_event_queue* moonmtcp_create_eventqueue(mctx_t mctx, int maxevents);
int moonmtcp_eventqueue_wait(mctx_t mctx, struct moon_mtcp_event_queue* queue, int timeout);
int moonmtcp_eventqueue_add_socket(mctx_t mctx, struct moon_mtcp_event_queue* queue, int sockid, int events);
//END tcp-mtcp.h

]]

MOONGEN_MTCP_MAX_INTERFACES = 16

return ffi.C
