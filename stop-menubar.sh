#!/bin/bash
# Stops any running MacSlowdown instance. Safe to run when none is running.

set -uo pipefail

if pgrep -x MacSlowdown > /dev/null 2>&1; then
	pkill -x MacSlowdown || true
	for _ in $(seq 1 20); do
		pgrep -x MacSlowdown > /dev/null 2>&1 || break
		sleep 0.1
	done
	echo "stopped MacSlowdown"
else
	echo "MacSlowdown not running"
fi
