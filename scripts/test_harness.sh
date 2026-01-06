#!/usr/bin/env bash
set -euo pipefail
BIN="${1:-./build/mini-init-amd64}"

echo "[test] 1) Graceful termination"
set -m
EP_GRACE_SECONDS=5 "$BIN" -v -- /bin/bash scripts/fixtures/trap_exit0.sh &
pid=$!
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
  echo "[test] ERROR: init exited before TERM (pid=$pid)"
  wait "$pid" || true
  exit 1
fi
kill -TERM "$pid"
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
# our fixture exits 0 on TERM
test "$wait_rc" -eq 0

echo "[test] 2) Escalation after grace (app ignores TERM)"
EP_GRACE_SECONDS=1 "$BIN" -v -- /bin/bash -c 'trap "" TERM INT HUP QUIT; while :; do sleep 5; done' &
pid=$!
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
  echo "[test] ERROR: init exited before TERM (pid=$pid)"
  wait "$pid" || true
  exit 1
fi
kill -TERM "$pid"
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 137
echo "[test] OK (got 137)"

echo "[test] 3) Forward custom EP_SIGNALS=USR1"
EP_SIGNALS=USR1 "$BIN" -v -- /bin/bash -c 'trap "echo got USR1; exit 0" USR1; sleep 99' &
pid=$!
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
  echo "[test] ERROR: init exited before USR1 (pid=$pid)"
  wait "$pid" || true
  exit 1
fi
kill -USR1 "$pid"
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0

echo "[test] 4) Forward numeric EP_SIGNALS=5 (SIGTRAP)"
EP_SIGNALS=5 "$BIN" -v -- /bin/sh -c 'trap "echo got TRAP; exit 0" TRAP; sleep 99' &
pid=$!
sleep 1
if ! kill -0 "$pid" 2>/dev/null; then
  echo "[test] ERROR: init exited before TRAP (pid=$pid)"
  wait "$pid" || true
  exit 1
fi
kill -TRAP "$pid"
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0
