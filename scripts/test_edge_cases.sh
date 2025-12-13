#!/usr/bin/env bash
set -euo pipefail
# Integration tests for edge cases: rapid signal bursts, orphaned processes

BIN="${1:-./build/mini-init-amd64}"

echo "[test] Edge case integration tests"

# Test 1: Rapid signal bursts (send multiple TERM signals quickly)
echo "[test] 1) Rapid signal bursts (TERM x5)"
EP_GRACE_SECONDS=5 "$BIN" -v -- /bin/sh -c 'trap "exit 0" TERM; sleep 1000' &
pid=$!
sleep 0.5
# Send 5 TERM signals rapidly
for _ in {1..5}; do
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.1
done
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Rapid signal bursts not handled correctly"
    exit 1
}

# Test 2: Orphaned process (child forks grandchild, parent exits)
echo "[test] 2) Orphaned process handling"
orphan_script=$(
  cat <<'EOF'
# Fork a background process that will become orphaned
(sleep 2; echo "orphan done"; exit 42) &
orphan_pid=$!
# Exit immediately, leaving the orphan
exit 0
EOF
)
EP_SUBREAPER=1 "$BIN" -v -- /bin/sh -c "$orphan_script" &
init_pid=$!
set +e
wait "$init_pid"
init_rc=$?
set -e
echo "[test] init rc=$init_rc"
# Note: even in subreaper mode, this init exits when the main child exits; subreaper only affects adoption/reaping.
test "$init_rc" -eq 0 || {
    echo "FAIL: Orphaned process not handled"
    exit 1
}

# Test 3: Multiple rapid signals of different types
echo "[test] 3) Mixed rapid signals (TERM, INT, HUP)"
EP_GRACE_SECONDS=5 "$BIN" -v -- /bin/sh -c 'trap "exit 0" TERM INT HUP; sleep 1000' &
pid=$!
sleep 0.5
kill -TERM "$pid" 2>/dev/null || true
sleep 0.1
kill -INT "$pid" 2>/dev/null || true
sleep 0.1
kill -HUP "$pid" 2>/dev/null || true
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Mixed rapid signals not handled"
    exit 1
}

# Test 4: Signal during grace period (should not escalate)
echo "[test] 4) Signal during grace period"
EP_GRACE_SECONDS=3 "$BIN" -v -- /bin/sh -c 'trap "exit 0" TERM; sleep 1000' &
pid=$!
sleep 0.5
kill -TERM "$pid" 2>/dev/null || true
sleep 1
# Send another TERM during grace period
kill -TERM "$pid" 2>/dev/null || true
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Signal during grace period not handled"
    exit 1
}

# Test 5: Child exits immediately after signal (opportunistic reap)
echo "[test] 5) Child exits immediately after signal"
EP_GRACE_SECONDS=5 "$BIN" -v -- /bin/sh -c 'trap "exit 0" TERM; sleep 1000' &
pid=$!
sleep 0.5
kill -TERM "$pid" 2>/dev/null || true
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Immediate exit after signal not handled"
    exit 1
}

echo "[test] 6) Main-child exit amid many other zombies (reap correctness)"
set +e
zombies_script=$(
  cat <<'EOF'
# Spawn many short-lived children that may still be zombies when the parent exits.
i=0
while [ "$i" -lt 200 ]; do
  (exit 0) &
  i=$((i+1))
done
exit 42
EOF
)
EP_GRACE_SECONDS=5 timeout 5 "$BIN" -v -- /bin/sh -c "$zombies_script" >/dev/null 2>&1
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 42 || {
    echo "FAIL: Expected init to exit 42 (main child), got $wait_rc"
    exit 1
}

echo "[test] 7) Invalid numeric env values warn (verbose)"
EP_GRACE_SECONDS=1x "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "invalid EP_GRACE_SECONDS" || {
    echo "FAIL: Expected warning for invalid EP_GRACE_SECONDS"
    exit 1
}

echo "[test] 8) Overlarge grace seconds clamps (verbose)"
EP_GRACE_SECONDS=9223372036854775808 "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "EP_GRACE_SECONDS too large; clamping" || {
    echo "FAIL: Expected clamp warning for overlarge EP_GRACE_SECONDS"
    exit 1
}

echo "[test] All edge case tests passed"
