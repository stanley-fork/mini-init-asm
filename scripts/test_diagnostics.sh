#!/usr/bin/env bash
set -euo pipefail

BIN="${1:-./build/mini-init-amd64}"

echo "[test] Diagnostics/verbose logging checks"

tmp="$(mktemp)"
tmp2="$(mktemp)"
cleanup() {
  rm -f "$tmp" "$tmp2"
}
trap cleanup EXIT

echo "[test] 1) Logs include signal and grace_seconds"
EP_GRACE_SECONDS=2 "$BIN" -v -- /bin/bash scripts/fixtures/trap_exit0.sh 2>"$tmp" &
pid=$!
sleep 0.5
kill -TERM "$pid"
set +e
wait "$pid"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 0
grep -q "DEBUG: signal=" "$tmp"
grep -q "DEBUG: grace_seconds=" "$tmp"

echo "[test] 2) Logs include restart_count on restart"
set +e
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=1 EP_RESTART_BACKOFF_SECONDS=0 \
  "$BIN" -v -- /bin/sh -c "kill -SEGV \$\$" 2>"$tmp2"
wait_rc=$?
set -e
echo "[test] rc=$wait_rc"
test "$wait_rc" -eq 139
grep -q "DEBUG: restart_count=" "$tmp2"

echo "[test] Diagnostics tests passed"
