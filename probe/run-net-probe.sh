#!/bin/bash
# Runs the FR-051 network probe sandboxed and unsandboxed, against real traffic.
#
# A zero reading proves nothing, so this generates a sustained loopback transfer
# (a local HTTP server plus a curl loop) that spans the probe's sampling window.
# Loopback keeps the measurement deterministic and off the user's network.
#
# The sandboxed run is launched with `open`, never by exec'ing the inner binary:
# macOS attributes permissions to the responsible process, so a binary started
# from a terminal inherits the terminal's grants and reports the wrong answer.
#
# Usage: run-net-probe.sh [gap-seconds]   (default 6)
set -euo pipefail
cd "$(dirname "$0")"

GAP="${1:-6}"
PORT=8899
PAYLOAD_DIR="$(mktemp -d)"
BUNDLE_ID="com.brooksc.MacSlowdown.Probe.net-probe"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID/Data"

cleanup() {
	stop_load
	rm -rf "$PAYLOAD_DIR"
}
trap cleanup EXIT

echo "--- generating a 256 MB payload in $PAYLOAD_DIR ---"
mkfile -n 256m "$PAYLOAD_DIR/payload.bin" 2>/dev/null \
	|| dd if=/dev/zero of="$PAYLOAD_DIR/payload.bin" bs=1m count=256 2>/dev/null

start_load() {
	( cd "$PAYLOAD_DIR" && nice python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
	SERVER_PID=$!
	sleep 1
	# Verify the transfer really happens before trusting any delta below. A
	# stale server on this port serves 404s and the probe would then measure
	# almost nothing while appearing to have run under load.
	served=$(nice curl -s -o /dev/null -w '%{http_code} %{size_download}' \
		"http://127.0.0.1:$PORT/payload.bin")
	echo "load check: $served (expect '200 268435456')"
	case "$served" in
	"200 268435456") ;;
	*) echo "error: loopback load is not serving the payload; aborting" >&2; exit 1 ;;
	esac
	( while true; do
		nice curl -s -o /dev/null "http://127.0.0.1:$PORT/payload.bin" || true
	done ) &
	CURL_PID=$!
	echo "load running: http server pid $SERVER_PID, curl loop pid $CURL_PID"
}

# Killing the subshells is not enough: python and curl are their children and
# survive, and an orphaned server holding the port makes the next run measure a
# stream of 404s instead of a transfer. Ask for the real processes by pattern.
stop_load() {
	[ -n "${CURL_PID:-}" ] && { pkill -P "$CURL_PID" 2>/dev/null; kill "$CURL_PID" 2>/dev/null; } || true
	[ -n "${SERVER_PID:-}" ] && { pkill -P "$SERVER_PID" 2>/dev/null; kill "$SERVER_PID" 2>/dev/null; } || true
	pkill -f "http.server $PORT" 2>/dev/null || true
	pkill -f "127.0.0.1:$PORT/payload.bin" 2>/dev/null || true
	unset CURL_PID SERVER_PID
	sleep 1
}

echo ""
echo "=============== UNSANDBOXED CONTROL ==============="
nice swiftc -O -o /tmp/net-probe-unsandboxed Sources/net-probe.swift
start_load
NETPROBE_GAP="$GAP" /tmp/net-probe-unsandboxed | tee /tmp/net-probe-unsandboxed.txt
stop_load

echo ""
echo "=============== SANDBOXED (signed .app, launched via open) ==============="
./build-probe.sh Sources/net-probe.swift ./build
rm -f "$CONTAINER/net-probe-result.txt"
start_load
# `open` does not inherit the shell's TCC-responsible process, which is the point.
open --env NETPROBE_GAP="$GAP" "$PWD/build/net-probe.app"
# Sampling gap plus the socket scans, the NWPath wait and the nettop watchdog.
sleep "$((GAP + 25))"
stop_load

if [ -f "$CONTAINER/net-probe-result.txt" ]; then
	cat "$CONTAINER/net-probe-result.txt"
else
	echo "no result file at $CONTAINER/net-probe-result.txt"
	echo "container contents:"
	ls -la "$CONTAINER" 2>/dev/null || echo "  (no container)"
	exit 1
fi
