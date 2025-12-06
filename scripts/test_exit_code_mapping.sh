#!/usr/bin/env bash
set -euo pipefail
# Tests for configurable signal-to-exit-code mapping

BIN="${1:-./build/mini-init-amd64}"

echo "[test] Exit code mapping tests"

# Test 1: Default behavior (base=128)
echo "[test] 1) Default exit code base (128)"
EP_GRACE_SECONDS=1 $BIN -v -- /bin/sh -c 'trap "" TERM; sleep 99' &
pid=$!
sleep 0.5
kill -TERM $pid 2>/dev/null || true
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 137 || {
    echo "FAIL: Expected 137 (128+9), got $wait_rc"
    exit 1
}

# Test 2: Custom exit code base
echo "[test] 2) Custom exit code base (200)"
EP_EXIT_CODE_BASE=200 EP_GRACE_SECONDS=1 $BIN -v -- /bin/sh -c 'trap "" TERM; sleep 99' &
pid=$!
sleep 0.5
kill -TERM $pid 2>/dev/null || true
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 209 || {
    echo "FAIL: Expected 209 (200+9), got $wait_rc"
    exit 1
}

# Test 3: Normal exit (should not be affected by base)
echo "[test] 3) Normal exit (unaffected by base)"
EP_EXIT_CODE_BASE=200 $BIN -v -- /bin/sh -c 'exit 42' &
pid=$!
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 42 || {
    echo "FAIL: Expected 42, got $wait_rc"
    exit 1
}

# Test 4: Signal exit with custom base
echo "[test] 4) Signal exit with custom base (TERM = 15)"
EP_EXIT_CODE_BASE=100 $BIN -v -- /bin/sh -c 'trap "exit 0" TERM; sleep 1000' &
pid=$!
sleep 0.5
kill -TERM $pid 2>/dev/null || true
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Expected 0 (graceful exit), got $wait_rc"
    exit 1
}

echo "[test] All exit code mapping tests passed"

