#!/bin/bash
# Drives the FR-046 exit-status probe unsandboxed and sandboxed, against real
# terminations with known outcomes.
#
# The probe cannot answer the question by watching ambient churn alone: ambient
# exits are nearly all ordinary, so "no crash was seen" would be indistinguishable
# from "crashes are invisible". This script therefore manufactures four known
# fates in processes it spawns itself, none of which are children of the probe:
#
#   victim-segv : sleep, killed with SIGSEGV      -> a crash
#   victim-term : sleep, killed with SIGTERM      -> not a crash
#   victim-ok   : sh -c 'sleep N'                 -> exit 0
#   victim-3    : sh -c 'sleep N; exit 3'         -> nonzero, still not a crash
#   victim-app  : an LSUIElement .app, SIGSEGV    -> a crashed application
#
# Every one of them is created by this script. Nothing else on the machine is
# signalled; FR-037 forbids it and so does the brief.
#
# The sandboxed run is launched with `open`, never by exec'ing the inner binary:
# macOS attributes permissions to the responsible process, so a binary started
# from a terminal inherits the terminal's grants.
#
# Usage: run-exit-status-probe.sh [watch-seconds]   (default 45)
set -uo pipefail
cd "$(dirname "$0")"

WATCH="${1:-45}"
BUNDLE_ID="com.brooksc.MacSlowdown.Probe.exit-status-probe"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID/Data"
OUTDIR="${OUTDIR:-/tmp/fr046-exit-status}"
mkdir -p "$OUTDIR"

VICTIMS=()

spawn_victims() {
	VICTIMS=()
	sleep 300 & VSEGV=$!
	sleep 300 & VTERM=$!
	sh -c 'sleep 12' & VOK=$!
	sh -c 'sleep 14; exit 3' & V3=$!
	VICTIMS=("$VSEGV" "$VTERM" "$VOK" "$V3")

	# -g so it never takes focus, -n so a leftover instance is not reused.
	# It is LSUIElement, so it puts nothing on screen at all.
	open -g -n "$PWD/build/victim-app.app"
	sleep 2
	VAPP="$(pgrep -f "$PWD/build/victim-app.app/Contents/MacOS/victim-app" | head -1)"
	echo "victims: SEGV=$VSEGV TERM=$VTERM exit0=$VOK exit3=$V3 app=${VAPP:-none}"
}

# Fates are delivered on a schedule that lands inside the probe's watch window.
# The probe registers within about a second of launch, so the first kill waits 6.
drive_fates() {
	sleep 6;  kill -SEGV "$VSEGV" 2>/dev/null; echo "  sent SIGSEGV to $VSEGV"
	sleep 2;  kill -TERM "$VTERM" 2>/dev/null; echo "  sent SIGTERM to $VTERM"
	# SIGKILL, not SIGSEGV, for the .app: CrashReporter's default DialogType puts
	# a "quit unexpectedly" alert on screen for a segfaulting application, and
	# this run must put nothing on screen. SIGKILL is still an abnormal
	# termination, so it is a fair test of whether NSWorkspace distinguishes one
	# from a clean quit — if it cannot tell SIGKILL from a normal exit it cannot
	# tell SIGSEGV either. The SIGSEGV cases above are CLI tools, which get a
	# crash log but no dialog.
	if [ -n "${VAPP:-}" ]; then
		sleep 2; kill -KILL "$VAPP" 2>/dev/null; echo "  sent SIGKILL to victim-app $VAPP"
	fi
	# A second instance, launched and then quitting cleanly of its own accord,
	# entirely inside the probe's watch window. Its launch is the control for
	# the NSWorkspace plumbing — a run that sees no launch notification cannot
	# claim anything from having seen no termination notification — and its
	# voluntary exit(0) is what a SIGKILLed instance has to be compared against.
	sleep 2
	VICTIM_LIFETIME=8 open -g -n --env VICTIM_LIFETIME=8 "$PWD/build/victim-app.app"
	echo "  launched a second victim-app, clean exit(0) in 8 s"
	# victim-ok and victim-3 exit on their own at +12 s and +14 s.
	wait "$VSEGV" "$VTERM" "$VOK" "$V3" 2>/dev/null
}

cleanup() {
	for p in "${VICTIMS[@]:-}"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
	[ -n "${VAPP:-}" ] && kill -9 "$VAPP" 2>/dev/null
	pkill -f "victim-app.app/Contents/MacOS/victim-app" 2>/dev/null
	return 0
}
trap cleanup EXIT

echo "--- building ---"
nice swiftc -O -o "$OUTDIR/exit-status-probe-unsandboxed" Sources/exit-status-probe.swift || exit 1
./build-probe.sh Sources/victim-app.swift ./build >/dev/null || exit 1
./build-probe.sh Sources/exit-status-probe.swift ./build >/dev/null || exit 1
echo "built."

echo ""
echo "=============== UNSANDBOXED CONTROL ==============="
spawn_victims
drive_fates &
EXITPROBE_WATCH="$WATCH" EXITPROBE_OUT="$OUTDIR/unsandboxed.txt" \
	"$OUTDIR/exit-status-probe-unsandboxed" > "$OUTDIR/unsandboxed.stdout" 2>&1
echo "unsandboxed report: $OUTDIR/unsandboxed.txt"
cleanup

echo ""
echo "=============== SANDBOXED (signed .app, launched via open) ==============="
rm -f "$CONTAINER/exit-status-result.txt"
spawn_victims
open -g --env EXITPROBE_WATCH="$WATCH" "$PWD/build/exit-status-probe.app"
drive_fates &
sleep "$((WATCH + 8))"
cleanup

if [ -f "$CONTAINER/exit-status-result.txt" ]; then
	cp "$CONTAINER/exit-status-result.txt" "$OUTDIR/sandboxed.txt"
	echo "sandboxed report: $OUTDIR/sandboxed.txt"
else
	echo "no result file at $CONTAINER/exit-status-result.txt"
	ls -la "$CONTAINER" 2>/dev/null || echo "  (no container)"
	exit 1
fi

echo ""
echo "=============== HEADLINE DIFF ==============="
for f in "$OUTDIR/unsandboxed.txt" "$OUTDIR/sandboxed.txt"; do
	echo "--- $f ---"
	grep -E 'sandboxed |attached|NOTE_EXIT events|carried NOTE_EXITSTATUS|did NOT|children we forked|strangers|with usable status|registration cost' "$f"
done
