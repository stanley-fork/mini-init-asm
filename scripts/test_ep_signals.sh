#!/usr/bin/env bash
set -euo pipefail
# Unit tests for EP_SIGNALS tokenizer/parser

BIN="${1:-./build/mini-init-amd64}"

echo "[test] EP_SIGNALS parser unit tests"

# Test 1: Single valid token
echo "[test] 1) Single token: USR1"
EP_SIGNALS=USR1 "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "EP_SIGNALS parsed" || {
    echo "FAIL: EP_SIGNALS=USR1 not parsed"
    exit 1
}

# Test 2: Multiple valid tokens
echo "[test] 2) Multiple tokens: USR1,USR2,PIPE"
EP_SIGNALS=USR1,USR2,PIPE "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "EP_SIGNALS parsed" || {
    echo "FAIL: Multiple tokens not parsed"
    exit 1
}

# Test 3: Unknown token (should warn but continue)
echo "[test] 3) Unknown token: INVALID"
EP_SIGNALS=INVALID "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "Unknown EP_SIGNALS token" || {
    echo "FAIL: Unknown token not warned"
    exit 1
}

# Test 4: Mixed valid and invalid tokens
echo "[test] 4) Mixed tokens: USR1,INVALID,USR2"
EP_SIGNALS=USR1,INVALID,USR2 "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "Unknown EP_SIGNALS token" || {
    echo "FAIL: Mixed tokens not handled"
    exit 1
}

# Test 5: Empty EP_SIGNALS (should not error)
echo "[test] 5) Empty EP_SIGNALS"
EP_SIGNALS="" "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -vq "ERROR" || {
    echo "FAIL: Empty EP_SIGNALS caused error"
    exit 1
}

# Test 6: All supported signals
echo "[test] 6) All supported signals"
output=$(EP_SIGNALS=USR1,USR2,PIPE,WINCH,TTIN,TTOU,CONT,ALRM "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1)
if echo "$output" | grep -q "EP_SIGNALS parsed"; then
    : # Success
else
    echo "FAIL: All signals not parsed"
    echo "Output was:"
    echo "$output"
    exit 1
fi

# Test 7: Whitespace handling
echo "[test] 7) Whitespace handling: ' USR1 , USR2 '"
EP_SIGNALS=" USR1 , USR2 " "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "EP_SIGNALS parsed" || {
    echo "FAIL: Whitespace not handled"
    exit 1
}

# Test 8: Very long token (should be ignored)
echo "[test] 8) Very long token (should warn)"
EP_SIGNALS=THISISAVERYLONGTOKENTHATEXCEEDSTHEBUFFER "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "Unknown EP_SIGNALS token" || {
    echo "FAIL: Long token not handled"
    exit 1
}

# Test 9: Real-time signals (RT1, RT2, etc.)
echo "[test] 9) RT tokens require explicit EP_SIGRTMIN/EP_SIGRTMAX (warns if missing)"
EP_SIGNALS=RT1 "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "RT\\* EP_SIGNALS tokens require EP_SIGRTMIN" || {
    echo "FAIL: Expected warning for RT token without EP_SIGRTMIN/EP_SIGRTMAX"
    exit 1
}

echo "[test] 9b) Real-time signals with explicit RT bounds: RT1,RT2,RT5"
EP_SIGRTMIN=34 EP_SIGRTMAX=64 EP_SIGNALS=RT1,RT2,RT5 \
  "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "EP_SIGNALS parsed" || {
    echo "FAIL: RT signals not parsed with EP_SIGRTMIN/EP_SIGRTMAX"
    exit 1
}

# Test 10: Invalid RT signal (RT0, RT31, RT32)
echo "[test] 10) Invalid RT signals: RT0,RT31,RT32 (should warn)"
EP_SIGRTMIN=34 EP_SIGRTMAX=64 EP_SIGNALS=RT0,RT31,RT32 "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "Unknown EP_SIGNALS token" || {
    echo "FAIL: Invalid RT signals not handled"
    exit 1
}

# Test 11: Mixed RT and regular signals
echo "[test] 11) Mixed signals: USR1,RT1,RT5,USR2"
EP_SIGRTMIN=34 EP_SIGRTMAX=64 EP_SIGNALS=USR1,RT1,RT5,USR2 "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "EP_SIGNALS parsed" || {
    echo "FAIL: Mixed RT and regular signals not parsed"
    exit 1
}

echo "[test] 11b) Invalid RT suffix: RT5X (should warn)"
EP_SIGRTMIN=34 EP_SIGRTMAX=64 EP_SIGNALS=RT5X "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -q "Unknown EP_SIGNALS token" || {
    echo "FAIL: Invalid RT suffix not warned"
    exit 1
}

echo "[test] 12) No EP_SIGNALS should not log parse"
output=$("$BIN" -v -- /bin/sh -c 'exit 0' 2>&1)
if echo "$output" | grep -q "EP_SIGNALS parsed"; then
    echo "FAIL: EP_SIGNALS parsed log should not appear when unset"
    exit 1
fi

echo "[test] 13) EP_SIGNALS parsed log appears once"
count=$(EP_SIGNALS=USR1 "$BIN" -v -- /bin/sh -c 'exit 0' 2>&1 | grep -c "EP_SIGNALS parsed")
if [ "$count" -ne 1 ]; then
    echo "FAIL: Expected one EP_SIGNALS parsed log, got $count"
    exit 1
fi

echo "[test] All EP_SIGNALS parser tests passed"
