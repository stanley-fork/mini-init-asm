# Roadmap

This document tracks planned features and improvements for `mini-init-asm`.

## Short-term (Next Release)

### Arm64 tests on linux

- QEMU user-mode remains flaky: ARM64 binary hangs/SIGILLs under `qemu-aarch64-static` right after startup (even with fallback mode).
- Helpers (`helper-exit42`, `helper-sleeper`) run fine under QEMU; issue is specific to `mini-init-arm64` user-mode emulation.
- Instrumentation shows execution reaches `get_timestamp_ptr`/epoll setup, then no further syscalls; QEMU SIGILL is likely emulator-specific.
- Added `EP_ARM64_FALLBACK`/`ARM64_FALLBACK` env to skip the QEMU smoke in CI while keeping native behavior unchanged.
- Next: validate on native ARM64 hardware or full-system QEMU; try newer QEMU user-mode or replace `udiv`/`msub` in `get_timestamp_ptr` with a simpler divide loop if emulation keeps failing.

---

## Medium-term

### Enhanced Diagnostics

- Add structured logging (JSON output option)
- Performance metrics (signal delivery latency, grace period accuracy)
- Health check endpoint (optional HTTP server on unix socket)

## Long-term

---
