#!/usr/bin/env bash
set -euo pipefail
# Integration tests for edge cases: rapid signal bursts, orphaned processes

BIN="${1:-./build/mini-init-amd64}"

echo "[test] Edge case integration tests"

# Test 1: Rapid signal bursts (send multiple TERM signals quickly)
echo "[test] 1) Rapid signal bursts (TERM x5)"
EP_GRACE_SECONDS=5 $BIN -v -- /bin/sh -c 'trap "exit 0" TERM; sleep 1000' &
pid=$!
sleep 0.5
# Send 5 TERM signals rapidly
for i in {1..5}; do
    kill -TERM $pid 2>/dev/null || true
    sleep 0.1
done
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Rapid signal bursts not handled correctly"
    exit 1
}

# Test 2: Orphaned process (child forks grandchild, parent exits)
echo "[test] 2) Orphaned process handling"
EP_SUBREAPER=1 $BIN -v -- /bin/sh -c '
    # Fork a background process that will become orphaned
    (sleep 2; echo "orphan done"; exit 42) &
    orphan_pid=$!
    # Exit immediately, leaving the orphan
    exit 0
' &
init_pid=$!
set +e
wait $init_pid
init_rc=$?
set -e
echo "[test] init rc=$init_rc"
# With subreaper, init should wait for orphan
# Without subreaper, init exits immediately
test "$init_rc" -eq 0 || {
    echo "FAIL: Orphaned process not handled"
    exit 1
}

# Test 3: Multiple rapid signals of different types
echo "[test] 3) Mixed rapid signals (TERM, INT, HUP)"
EP_GRACE_SECONDS=5 $BIN -v -- /bin/sh -c 'trap "exit 0" TERM INT HUP; sleep 1000' &
pid=$!
sleep 0.5
kill -TERM $pid 2>/dev/null || true
sleep 0.1
kill -INT $pid 2>/dev/null || true
sleep 0.1
kill -HUP $pid 2>/dev/null || true
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Mixed rapid signals not handled"
    exit 1
}

# Test 4: Signal during grace period (should not escalate)
echo "[test] 4) Signal during grace period"
EP_GRACE_SECONDS=3 $BIN -v -- /bin/sh -c 'trap "exit 0" TERM; sleep 1000' &
pid=$!
sleep 0.5
kill -TERM $pid 2>/dev/null || true
sleep 1
# Send another TERM during grace period
kill -TERM $pid 2>/dev/null || true
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Signal during grace period not handled"
    exit 1
}

# Test 5: Child exits immediately after signal (opportunistic reap)
echo "[test] 5) Child exits immediately after signal"
EP_GRACE_SECONDS=5 $BIN -v -- /bin/sh -c 'trap "exit 0" TERM; sleep 1000' &
pid=$!
sleep 0.5
kill -TERM $pid 2>/dev/null || true
set +e
wait $pid
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Immediate exit after signal not handled"
    exit 1
}

echo "[test] All edge case tests passed"
