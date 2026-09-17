#!/bin/bash
# Capture the running app's main-window sections, in a VM, without touching the
# owner's display.
#
# **Why a VM and not this Mac.** The app is LSUIElement: launching it opens
# nothing and puts a status item in the menu bar, and driving that from a script
# needs Accessibility permission. Doing either here collides with whatever the
# owner is doing, and CLAUDE.md's screen rule forbids it without asking. The VM
# has its own window server and its own grants, so the app can be launched,
# activated and photographed with nobody watching.
#
# **Two things that are not obvious and cost a session each.**
#
#   - Screenshots go through `osascript`, never `screencapture` straight from the
#     SSH session. macOS attributes a screen-recording grant to the *responsible*
#     process, and an SSH session has none — it raises a consent dialog, which
#     then appears in the frame. That is what the first attempts produced.
#   - The app is relaunched once per section rather than clicked through.
#     SwiftUI's accessibility tree is not walkable by System Events on macOS 26,
#     so scripting the sidebar silently does nothing. `UIVerificationLaunch`
#     (Debug only) takes `-ui-open` and `-ui-section` and makes it deterministic.
#
# Usage: probe/vm-capture.sh [output-directory] [settle-seconds]
set -euo pipefail

VM="${VM:-macslowdown-uitest-26}"
OUT="${1:-design/verified/$(date +%F)}"
# Long enough for the 60 s trailing mean and the sparklines to hold something
# real. A shorter settle photographs an app that has nothing to say yet, which
# reads as a defect and is not one.
SETTLE="${2:-45}"
VM_USER=admin
VM_PASS=admin
REPO_IN_VM='$HOME/MacSlowdown'

cd "$(dirname "$0")/.."
OUT="$(pwd)/$OUT"
mkdir -p "$OUT"

# The sidebar sections, by the display names `UIVerificationLaunch` matches on.
SECTIONS=("Overview" "Now" "Apps & Processes" "Incidents" "Storage")

ssh_vm() {
	sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		"$VM_USER@$IP" "$@"
}

echo "==> Starting $VM"
if ! tart list | grep -q "$VM.*running"; then
	# --no-graphics, always. --vnc-experimental calls `open` on a vnc:// URL and
	# launches Screen Sharing onto the owner's display. That happened once.
	nohup nice tart run "$VM" --no-graphics --no-audio --no-clipboard \
		>/dev/null 2>&1 &
fi

echo "==> Waiting for an address"
for _ in $(seq 1 60); do
	IP="$(tart ip "$VM" 2>/dev/null || true)"
	[ -n "${IP:-}" ] && break
	sleep 2
done
[ -n "${IP:-}" ] || { echo "no address after 120 s"; exit 1; }
echo "    $IP"

echo "==> Syncing the working tree"
# The VM builds what is *here*, including uncommitted work — the point is to look
# at the change in hand, not at what happens to be pushed.
sshpass -p "$VM_PASS" rsync -az --delete \
	-e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR" \
	--exclude .build --exclude Derived --exclude '*.xcworkspace' --exclude '*.xcodeproj' \
	./ "$VM_USER@$IP:MacSlowdown/"

echo "==> Building (jobs 3 — the VM's 4 vCPU come out of a fanless 8-core host)"
ssh_vm "cd $REPO_IN_VM && export PATH=\$HOME/bin:\$PATH && \
	TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open && \
	TUIST_SKIP_UPDATE_CHECK=1 xcodebuild build -scheme MacSlowdown \
		-configuration Debug -destination 'platform=macOS' \
		-derivedDataPath .build -jobs 3 -quiet"

APP="$REPO_IN_VM/.build/Build/Products/Debug/MacSlowdown.app/Contents/MacOS/MacSlowdown"

index=0
for section in "${SECTIONS[@]}"; do
	index=$((index + 1))
	slug="$(echo "$section" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
	file="$(printf '%02d-%s.png' "$index" "$slug")"
	echo "==> $section"

	ssh_vm "pkill -f MacSlowdown.app || true; sleep 2; \
		nohup '$APP' -ui-open main -ui-section '$section' >/dev/null 2>&1 & \
		sleep $SETTLE; \
		osascript -e 'do shell script \"screencapture -x /tmp/$file\"'"

	sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		"$VM_USER@$IP:/tmp/$file" "$OUT/$file"
done

echo "==> First run"
ssh_vm "pkill -f MacSlowdown.app || true; sleep 2; \
	defaults delete com.brooksc.MacSlowdown firstRun.completed 2>/dev/null || true; \
	nohup '$APP' -ui-open first-run >/dev/null 2>&1 & \
	sleep 15; \
	osascript -e 'do shell script \"screencapture -x /tmp/06-first-run.png\"'"
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
	"$VM_USER@$IP:/tmp/06-first-run.png" "$OUT/06-first-run.png"

ssh_vm "pkill -f MacSlowdown.app || true"
echo "==> Stopping $VM"
tart stop "$VM" || true

echo
echo "Captured into $OUT:"
ls -1 "$OUT"/*.png
