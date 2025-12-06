#!/usr/bin/env bash
set -euo pipefail

trap 'echo "got TERM"; exit 0' TERM INT HUP QUIT
( sleep 90 ) &
sleep 90
