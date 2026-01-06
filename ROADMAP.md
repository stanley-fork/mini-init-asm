# Roadmap

This document tracks planned features and improvements for `mini-init-asm`.

## Recently completed

- See CHANGELOG.md

## Short-term (Next Release)

### Possible next steps

- Native ARM64 validation (real hardware or full-system QEMU) for the normal epoll/signalfd path in CI (not only fallback smoke).
- Consider optional `EP_SUBREAPER_WAIT=1` (wait for adopted children after main child exit) and document tradeoffs.
- Consider `EP_RESTART_ON_NONZERO_EXIT=1` (opt-in) if restart-on-crash should include nonzero normal exits.
- Clamp `EP_MAX_RESTARTS` to a sane upper bound to avoid pathological loops.
- Continue improving diagnostics while keeping pure-syscall design (e.g., log child PGID, kill/escalation decisions).

### Arm64 tests on linux

- QEMU user-mode remains flaky for the full init loop on some hosts (hang/SIGILL under `qemu-aarch64-static`).
- `EP_ARM64_FALLBACK=1` provides a wait4-only smoke test; `scripts/test_harness_arm64.sh` treats SIGILL/timeout as a non-fatal skip in fallback mode.
- CI today:
  - always cross-builds arm64 and runs the QEMU-user fallback smoke;
  - additionally runs native ARM64 tests on GitHub-hosted ARM runners (subject to runner availability).
- Next: add a higher-confidence arm64 CI lane (preferred order):
  1) always-on native ARM64 runner, or
  2) full-system emulation integration tests (`qemu-system-aarch64`), or
  3) pin/upgrade QEMU-user and expand fallback coverage if full-loop remains unstable.

---

## Medium-term

### Enhanced Diagnostics

- Add structured logging (JSON output option)
- Performance metrics (signal delivery latency, grace period accuracy)
- Health check endpoint (optional HTTP server on unix socket)

## Long-term

---
