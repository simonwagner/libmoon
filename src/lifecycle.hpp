#ifndef LIFECYCLE_H__
#define LIFECYCLE_H__

namespace libmoon {
	void install_signal_handlers();
    void signal_handler(int signal);
	uint8_t is_running(uint32_t extra_time);
}

#endif
