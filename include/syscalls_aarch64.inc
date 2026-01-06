// Linux AArch64 syscall numbers (subset)

.equ SYS_read,            63
.equ SYS_write,           64
.equ SYS_close,           57
.equ SYS_execve,          221
.equ SYS_clone,           220
.equ SYS_wait4,           260
.equ SYS_kill,            129
.equ SYS_setpgid,         154
.equ SYS_setsid,          157
.equ SYS_rt_sigprocmask,  135
.equ SYS_nanosleep,       101
.equ SYS_signalfd4,       74
.equ SYS_epoll_create1,   20
.equ SYS_epoll_ctl,       21
.equ SYS_epoll_pwait,     22
.equ SYS_timerfd_create,  85
.equ SYS_timerfd_settime, 86
.equ SYS_exit,            93
.equ SYS_exit_group,      94
.equ SYS_clock_gettime,   113
.equ SYS_prctl,           167

// epoll/op flags
.equ EPOLL_CTL_ADD, 1
.equ EPOLLIN,       1
.equ EPOLL_CLOEXEC, 02000000

// sigprocmask how
.equ SIG_BLOCK,     0
.equ SIG_UNBLOCK,   1
.equ SIG_SETMASK,   2

// signal numbers (same as generic)
.equ SIGHUP,   1
.equ SIGINT,   2
.equ SIGQUIT,  3
.equ SIGILL,   4
.equ SIGTRAP,  5
.equ SIGABRT,  6
.equ SIGBUS,   7
.equ SIGFPE,   8
.equ SIGKILL,  9
.equ SIGUSR1, 10
.equ SIGSEGV, 11
.equ SIGUSR2, 12
.equ SIGPIPE, 13
.equ SIGALRM, 14
.equ SIGTERM, 15
.equ SIGCHLD, 17
.equ SIGCONT, 18
.equ SIGSTOP, 19
.equ SIGTSTP, 20
	.equ SIGTTIN, 21
	.equ SIGTTOU, 22
	.equ SIGWINCH, 28
	// NOTE: do not hardcode SIGRTMIN/SIGRTMAX (see signal(7)); they vary at runtime in libc.
	.equ KERNEL_SIGMAX, 64

	// errno subset
	.equ ESRCH, 3
	.equ EINTR, 4
	.equ EAGAIN, 11

// timerfd/signalfd flags
.equ TFD_CLOEXEC,   02000000
.equ TFD_NONBLOCK,  00004000
.equ SFD_CLOEXEC,   02000000
.equ SFD_NONBLOCK,  00004000

// clock ids
.equ CLOCK_REALTIME,    0
.equ CLOCK_MONOTONIC,   1

// epoll helpers
.equ EPOLL_EVENT_SIZE, 16

// prctl options
.equ PR_SET_CHILD_SUBREAPER, 36
