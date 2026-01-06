# Changelog

## 0.3.0 - 2026-01-06

- Real-time signals: `EP_SIGNALS=RT*` now requires explicit `EP_SIGRTMIN`/`EP_SIGRTMAX` (avoids hardcoded SIGRTMIN/SIGRTMAX assumptions).
- `EP_SIGNALS` now supports numeric signal tokens (`1..64`, excluding SIGKILL/SIGSTOP).
- Logging and fd I/O: add `write_all` handling partial writes and `EINTR`; harden `signalfd`/`timerfd` reads.
- Correctness: avoid forwarding signals after the main child has exited while restart backoff is pending (prevents accidental signaling of a reused PGID).
- Debian readiness: add `mini-init-asm(1)` and an initial `debian/` packaging skeleton with autopkgtest and CI lintian build.

## 0.2.0 - 2025-12-13

### Fixed

- Fix critical PID1 hang: main-child exit could be missed during SIGCHLD storms (now reliably detected/reported on both amd64 and arm64).
- Fix amd64 restart-mode stack safety when max restarts are reached.
- Prevent `epoll` fd leakage into the exec’ed child (`epoll_create1(EPOLL_CLOEXEC)`).
- Avoid SIGKILL escalation to a reused/nonexistent PGID (`kill(-pgid, 0)` probe before escalation).
- Fix verbose logging writing a NUL byte in timestamps.

### Improved

- More actionable verbose logs: signal number, grace seconds, restart backoff seconds, and restart count.
- Harden `EP_SIGNALS` parsing:
  - Trim trailing whitespace per token.
  - Real-time signals are now bounded to the kernel max (`RT1..RT30`).
- Numeric env vars are now parsed strictly as decimal digits; invalid/overflow values are ignored (warnings in verbose mode).
- Timer-related seconds (grace/backoff) are clamped to fit signed 64-bit seconds.
- `EP_EXIT_CODE_BASE` is now validated as `0..255` (out-of-range values are ignored; default applies).
- ARM64/QEMU: remove `msub` usage in hot paths; in `EP_ARM64_FALLBACK=1` mode timestamps are omitted to reduce QEMU-user flakiness.

### Tests/Docs

- Add an edge-case test covering “main child exits while many other children are reaped”.
- Update docs to reflect RT signal bounds and ARM64 fallback timestamp behavior.
- ARM64/QEMU: in fallback mode, smoke tests now exercise `--version` and the wait4-only path (helper exit propagation) instead of skipping entirely.
- Clean up `scripts/*` quoting to avoid common ShellCheck warnings (SC2016/SC2086).
