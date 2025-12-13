# Roadmap

This document tracks planned features and improvements for `mini-init-asm`.

## Short-term (Next Release)

### Possible next steps

- Native ARM64 validation (real hardware or full-system QEMU) for the normal epoll/signalfd path.
- Consider optional `EP_SUBREAPER_WAIT=1` (wait for adopted children after main child exit) and document tradeoffs.
- Consider `EP_RESTART_ON_NONZERO_EXIT=1` (opt-in) if restart-on-crash should include nonzero normal exits.
- Clamp `EP_MAX_RESTARTS` to a sane upper bound to avoid pathological loops.
- Continue improving diagnostics while keeping pure-syscall design (e.g., log child PGID, kill/escalation decisions).

### Arm64 tests on linux

- QEMU user-mode remains flaky: ARM64 binary hangs/SIGILLs under `qemu-aarch64-static` right after startup (historically even with fallback mode).
- Helpers (`helper-exit42`, `helper-sleeper`) run fine under QEMU; issue is specific to `mini-init-arm64` user-mode emulation.
- Instrumentation shows execution reaches `get_timestamp_ptr`/epoll setup, then no further syscalls; QEMU SIGILL is likely emulator-specific.
- Added `EP_ARM64_FALLBACK`/`ARM64_FALLBACK` env to skip the QEMU smoke in CI while keeping native behavior unchanged.
- Implemented a safer path: removed `msub` usage and made `EP_ARM64_FALLBACK=1` omit timestamp formatting to avoid QEMU-user issues.
- Note: even in fallback mode (`EP_ARM64_FALLBACK=1`), QEMU-user may still SIGILL on some runners; CI treats SIGILL/timeout as a non-fatal skip while still running helper binaries and `--version`.
- Next: validate on native ARM64 hardware or full-system QEMU; try newer QEMU user-mode if emulation still fails.

---

## Medium-term

### Enhanced Diagnostics

- Add structured logging (JSON output option)
- Performance metrics (signal delivery latency, grace period accuracy)
- Health check endpoint (optional HTTP server on unix socket)

## Long-term

---
