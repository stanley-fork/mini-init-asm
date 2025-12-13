#!/usr/bin/env bash
set -euo pipefail
# Integration tests for process restart functionality

BIN="${1:-./build/mini-init-amd64}"

echo "[test] Restart functionality tests"

# Test 1: Basic restart on crash (signal)
echo "[test] 1) Basic restart on crash (SIGSEGV)"
# Use a file to track crashes across restarts
rm -f "/tmp/test_restart_count"
# Run with timeout wrapper
restart_script_1=$(
  cat <<'EOF'
crash_count=$(cat /tmp/test_restart_count 2>/dev/null || echo "0")
crash_count=$((crash_count + 1))
echo "$crash_count" > /tmp/test_restart_count
if [ "$crash_count" -ge 3 ]; then
    rm -f /tmp/test_restart_count
    exit 0
fi
kill -SEGV $$
EOF
)
set +e
timeout 10 env EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=2 EP_RESTART_BACKOFF_SECONDS=0 \
  "$BIN" -v -- /bin/bash -c "$restart_script_1" >/dev/null 2>&1
wait_rc=$?
set -e
# Check if restart count file was cleaned up (indicates success)
if [ ! -f "/tmp/test_restart_count" ] && [ "$wait_rc" -eq 0 ]; then
    wait_rc=0
elif [ "$wait_rc" -eq 124 ]; then
    echo "FAIL: Process timed out"
    wait_rc=124
else
    wait_rc=1
fi
rm -f "/tmp/test_restart_count"
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Basic restart not working (rc=$wait_rc)"
    exit 1
}

# Test 2: Restart with backoff
echo "[test] 2) Restart with backoff delay"
start_time=$(date +%s)
# Child will crash immediately, then restart after 2 second backoff, then crash again
# With EP_MAX_RESTARTS=1, we allow 1 restart (2 total runs)
# First crash happens immediately, then backoff wait (2s), then restart, then second crash
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=1 EP_RESTART_BACKOFF_SECONDS=2 \
  "$BIN" -v -- /bin/sh -c "kill -SEGV \$\$" &
init_pid=$!
set +e
wait "$init_pid"
wait_rc=$?
set -e
end_time=$(date +%s)
elapsed=$((end_time - start_time))
echo "[test] rc=$wait_rc, elapsed=${elapsed}s"
# Should take at least 2 seconds due to backoff (first crash -> backoff 2s -> restart -> second crash)
test "$elapsed" -ge 2 || {
    echo "FAIL: Backoff not working (elapsed=${elapsed}s, expected >= 2s)"
    exit 1
}
# Should exit with SIGSEGV code (139) after max restarts
test "$wait_rc" -eq 139 || {
    echo "FAIL: Expected exit code 139 after max restarts, got $wait_rc"
    exit 1
}

# Test 3: Max restarts limit
echo "[test] 3) Max restarts limit"
# Child will crash immediately, restart 2 times (max_restarts=2), then exit with SIGSEGV code
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=2 EP_RESTART_BACKOFF_SECONDS=0 \
  "$BIN" -v -- /bin/sh -c "kill -SEGV \$\$" &
init_pid=$!
set +e
wait "$init_pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
# Should exit with signal exit code (128 + 11 = 139 for SIGSEGV) after max restarts
test "$wait_rc" -eq 139 || {
    echo "FAIL: Max restarts not enforced (rc=$wait_rc)"
    exit 1
}

# Test 4: No restart on normal exit
echo "[test] 4) No restart on normal exit"
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=10 EP_RESTART_BACKOFF_SECONDS=0 "$BIN" -v -- /bin/bash -c 'exit 42' &
init_pid=$!
set +e
wait "$init_pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
# Should exit with child's exit code, not restart
test "$wait_rc" -eq 42 || {
    echo "FAIL: Normal exit should not restart (rc=$wait_rc)"
    exit 1
}

# Test 5: No restart when shutdown signal received
echo "[test] 5) No restart when shutdown signal received"
no_restart_shutdown_script=$(
  cat <<'EOF'
trap "exit 0" TERM
sleep 100 &
sleep_pid=$!
wait "$sleep_pid" 2>/dev/null || true
EOF
)
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=10 EP_RESTART_BACKOFF_SECONDS=0 \
  "$BIN" -v -- /bin/sh -c "$no_restart_shutdown_script" &
init_pid=$!
sleep 1
# Send TERM (shutdown signal) - should not restart
kill -TERM "$init_pid" 2>/dev/null || true
set +e
wait "$init_pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
# Should exit normally (0) because TERM was handled, not restart
test "$wait_rc" -eq 0 || {
    echo "FAIL: Shutdown signal should prevent restart (rc=$wait_rc)"
    exit 1
}

# Test 6: Unlimited restarts (EP_MAX_RESTARTS=0)
echo "[test] 6) Unlimited restarts (EP_MAX_RESTARTS=0)"
# Use a file to track crashes across restarts
rm -f "/tmp/test_unlimited_count"
# Run with timeout wrapper
restart_script_6=$(
  cat <<'EOF'
crash_count=$(cat /tmp/test_unlimited_count 2>/dev/null || echo "0")
crash_count=$((crash_count + 1))
echo "$crash_count" > /tmp/test_unlimited_count
if [ "$crash_count" -ge 3 ]; then
    rm -f /tmp/test_unlimited_count
    exit 0
fi
kill -SEGV $$
EOF
)
set +e
timeout 10 env EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=0 EP_RESTART_BACKOFF_SECONDS=0 \
  "$BIN" -v -- /bin/sh -c "$restart_script_6" >/dev/null 2>&1
wait_rc=$?
set -e
# Check if restart count file was cleaned up (indicates success)
if [ ! -f "/tmp/test_unlimited_count" ] && [ "$wait_rc" -eq 0 ]; then
    wait_rc=0
elif [ "$wait_rc" -eq 124 ]; then
    echo "FAIL: Process timed out"
    wait_rc=124
else
    wait_rc=1
fi
rm -f "/tmp/test_unlimited_count"
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0 || {
    echo "FAIL: Unlimited restarts not working (rc=$wait_rc)"
    exit 1
}

echo "[test] 7) Shutdown during restart backoff prevents restart (exits promptly)"
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=0 EP_RESTART_BACKOFF_SECONDS=5 EP_GRACE_SECONDS=5 \
  "$BIN" -v -- /bin/sh -c "kill -SEGV \$\$" &
init_pid=$!
sleep 0.5
kill -TERM "$init_pid" 2>/dev/null || true
set +e
timeout 3s bash -c "while kill -0 \"\$1\" 2>/dev/null; do sleep 0.1; done" _ "$init_pid"
poll_rc=$?
wait "$init_pid"
wait_rc=$?
set -e
if [ "$poll_rc" -eq 124 ]; then
    echo "FAIL: Init did not exit promptly during backoff shutdown"
    exit 1
fi
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 139 || {
    echo "FAIL: Expected 139 (SIGSEGV mapped) after shutdown during backoff, got $wait_rc"
    exit 1
}

echo "[test] All restart tests passed!"
