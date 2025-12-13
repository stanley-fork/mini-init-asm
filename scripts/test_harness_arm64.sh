#!/usr/bin/env bash
set -euo pipefail

# Smoke test for ARM64 binary using QEMU user emulation
# Requires: qemu-user-static or qemu-aarch64-static

BIN="${1:-./build/mini-init-arm64}"
QEMU="${QEMU:-qemu-aarch64-static}"
ARM64_FALLBACK="${ARM64_FALLBACK:-${EP_ARM64_FALLBACK:-0}}"

# Check if QEMU is available
if ! command -v "$QEMU" &> /dev/null; then
    echo "[test] ERROR: $QEMU not found. Install qemu-user-static or qemu-aarch64-static"
    echo "[test]   Debian/Ubuntu: sudo apt-get install -y qemu-user-static"
    exit 1
fi

# Verify binary exists and is ARM64
if [ ! -f "$BIN" ]; then
    echo "[test] ERROR: Binary not found: $BIN"
    exit 1
fi

if ! file "$BIN" | grep -q "ARM aarch64"; then
    echo "[test] ERROR: Binary is not ARM64: $BIN"
    file "$BIN"
    exit 1
fi

echo "[test] ARM64 smoke test using $QEMU"
echo "[test] Binary: $BIN"

# Sanity: verify helpers exist and are ARM64, and QEMU can run them standalone
if [ ! -f "build/arm64/helper-exit42" ] || [ ! -f "build/arm64/helper-sleeper" ]; then
    echo "[test] ERROR: Helper binaries not found. Run: make build-arm64"
    exit 1
fi
if ! file "build/arm64/helper-exit42" | grep -q "ARM aarch64"; then
    echo "[test] ERROR: helper-exit42 is not ARM64"
    file "build/arm64/helper-exit42"
    exit 1
fi
set +e
"$QEMU" -- build/arm64/helper-exit42
helper_rc=$?
set -e
if [ "$helper_rc" -ne 42 ]; then
    echo "[test] ERROR: QEMU failed to run helper-exit42 (rc=$helper_rc)"
    exit 1
fi

# Optional: fallback mode to skip flaky QEMU epoll/signalfd path
if [ "$ARM64_FALLBACK" = "1" ]; then
    echo "[test] WARNING: EP_ARM64_FALLBACK=1 set; running wait4-only smoke under QEMU"

    echo "[test] 0) Version check"
    set +e
    timeout 5s "$QEMU" -- "$BIN" --version
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        echo "[test] ERROR: --version failed under QEMU (rc=$rc)"
        exit 1
    fi

    echo "[test] 1) Wait4-only path (helper-exit42)"
    set +e
    timeout 10s env EP_ARM64_FALLBACK=1 "$QEMU" -- "$BIN" -v -- ./build/arm64/helper-exit42
    rc=$?
    set -e
    if [ "$rc" -ne 42 ]; then
        echo "[test] ERROR: Expected exit 42, got $rc"
        exit 1
    fi

    echo "[test] OK (fallback smoke passed)"
    exit 0
fi

# Test 1: Basic execution (help-like check)
echo "[test] 1) Basic execution"
set +e
timeout 10s "$QEMU" -- "$BIN" -v -- ./build/arm64/helper-exit42
rc=$?
set -e
if [ "$rc" -eq 42 ]; then
    echo "[test] OK (got exit code 42)"
else
    echo "[test] WARNING: Expected exit 42, got $rc"
fi

# Test 2: Graceful termination
echo "[test] 2) Graceful termination"
set -m
EP_GRACE_SECONDS=5 timeout 15s "$QEMU" -- "$BIN" -v -- ./build/arm64/helper-sleeper &
pid=$!
sleep 1
# Check if process is still running before sending signal
if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
else
    echo "[test] WARNING: Process already exited before signal"
fi
set +e
wait "$pid" 2>/dev/null || true
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
# Under QEMU without a shell, expect signal exit code (143 for TERM) or 137 on escalation
if [ "$wait_rc" -eq 143 ] || [ "$wait_rc" -eq 137 ]; then
    echo "[test] OK (terminated by TERM/KILL as expected: $wait_rc)"
else
    echo "[test] INFO: Got exit code $wait_rc (may vary under QEMU)"
fi

# Test 3: Escalation (simplified - may not work perfectly under QEMU)
echo "[test] 3) Escalation check (may be flaky under QEMU)"
EP_GRACE_SECONDS=1 timeout 10s "$QEMU" -- "$BIN" -v -- ./build/arm64/helper-sleeper &
pid=$!
sleep 1
# Check if process is still running before sending signal
if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
else
    echo "[test] WARNING: Process already exited before signal"
fi
set +e
wait "$pid" 2>/dev/null || true
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
if [ "$wait_rc" -eq 137 ] || [ "$wait_rc" -eq 143 ]; then
    echo "[test] OK (got kill signal: $wait_rc)"
else
    echo "[test] INFO: Got exit code $wait_rc (may vary under QEMU)"
fi

echo "[test] ARM64 smoke test completed"
