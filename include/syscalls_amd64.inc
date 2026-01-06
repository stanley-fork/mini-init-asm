; Linux x86-64 syscall numbers (subset)
%define SYS_read            0
%define SYS_write           1
%define SYS_close           3
%define SYS_execve          59
%define SYS_fork            57
%define SYS_wait4           61
%define SYS_kill            62
%define SYS_setpgid        109
%define SYS_setsid         112
%define SYS_rt_sigprocmask  14
%define SYS_nanosleep       35
%define SYS_signalfd4      289
%define SYS_epoll_create1  291
%define SYS_epoll_ctl      233
%define SYS_epoll_pwait    281
%define SYS_timerfd_create 283
%define SYS_timerfd_settime 286
%define SYS_clock_gettime   228
%define SYS_prctl           157
%define SYS_exit            60

; epoll/op flags
%define EPOLL_CTL_ADD 1
%define EPOLLIN       1
%define EPOLL_CLOEXEC  02000000o

; sigprocmask how
%define SIG_BLOCK     0
%define SIG_UNBLOCK   1
%define SIG_SETMASK   2

; common signals (x86/amd64 mapping)
%define SIGHUP   1
%define SIGINT   2
%define SIGQUIT  3
%define SIGILL   4
%define SIGTRAP  5
%define SIGABRT  6
%define SIGBUS   7
%define SIGFPE   8
%define SIGKILL  9
%define SIGUSR1 10
%define SIGSEGV 11
%define SIGUSR2 12
%define SIGPIPE 13
%define SIGALRM 14
%define SIGTERM 15
%define SIGCHLD 17
%define SIGCONT 18
%define SIGSTOP 19
%define SIGTSTP 20
%define SIGTTIN 21
%define SIGTTOU 22
%define SIGWINCH 28
; NOTE: do not hardcode SIGRTMIN/SIGRTMAX (see signal(7)); they vary at runtime in libc.
%define KERNEL_SIGMAX 64

; errno subset
%define ESRCH         3
%define EINTR         4
%define EAGAIN       11

; timerfd/signalfd flags (octal per manpages)
%define TFD_CLOEXEC   02000000o
%define TFD_NONBLOCK  00004000o
%define SFD_CLOEXEC   02000000o
%define SFD_NONBLOCK  00004000o

; clock ids
%define CLOCK_REALTIME    0
%define CLOCK_MONOTONIC   1

; epoll helpers
%define EPOLL_EVENT_SIZE 16

; prctl options
%define PR_SET_CHILD_SUBREAPER 36
