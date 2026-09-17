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
#   - **Nothing here scripts another application.** An attempt to miniaturise
#     the Terminal window before capturing raised "sshd-keygen-wrapper wants
#     access to control Terminal" — a TCC consent dialog, modal, in the middle of
#     the frame. That is the same failure as capturing from the SSH session
#     directly, arriving by a different door. `open` activates the app on its
#     own; nothing else is needed.
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
# Absolute, not `$HOME`. The remote commands below are single-quoted so the local
# shell leaves them alone, which also stops the *remote* shell expanding `$HOME` —
# so `open -a '$HOME/...'` came back "Unable to find application named
# '$HOME/MacSlowdown/...'". The earlier `nohup` form failed the same way silently,
# which is why a capture run photographed a Terminal with no app in it.
REPO_IN_VM="/Users/$VM_USER/MacSlowdown"

cd "$(dirname "$0")/.."
OUT="$(pwd)/$OUT"
mkdir -p "$OUT"

# The sidebar sections, by the display names `UIVerificationLaunch` matches on.
SECTIONS=("Overview" "Now" "Apps & Processes" "Incidents" "Storage")

# `PubkeyAuthentication=no` and `IdentitiesOnly=yes` are load-bearing, not
# tidiness: with an agent loaded, ssh offers every key it holds before it will
# try the password, and the VM's sshd cuts the connection at six attempts with
# "Too many authentication failures" — which reads as a wrong password and is
# not one.
#
# The run also **multiplexes over one connection**. Each section costs an ssh and
# an scp, and authenticating separately every time walked into sshd's own limits:
# a mid-run scp came back "Permission denied (publickey,password,
# keyboard-interactive)" with the password unchanged and every earlier step
# working. A master connection authenticates once and every later step rides it.
CONTROL="${TMPDIR:-/tmp}/macslowdown-vm-capture.sock"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
	-o LogLevel=ERROR -o PubkeyAuthentication=no -o IdentitiesOnly=yes
	-o PreferredAuthentications=password -o NumberOfPasswordPrompts=1
	-o ControlMaster=auto -o "ControlPath=$CONTROL" -o ControlPersist=10m)

cleanup() {
	ssh -o "ControlPath=$CONTROL" -O exit "$VM_USER@${IP:-none}" 2>/dev/null || true
	rm -f "$CONTROL"
}
trap cleanup EXIT

ssh_vm() {
	sshpass -p "$VM_PASS" ssh "${SSH_OPTS[@]}" "$VM_USER@$IP" "$@"
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
	-e "ssh ${SSH_OPTS[*]}" \
	--exclude .build --exclude Derived --exclude '*.xcworkspace' --exclude '*.xcodeproj' \
	./ "$VM_USER@$IP:MacSlowdown/"

echo "==> Building (jobs 3 — the VM's 4 vCPU come out of a fanless 8-core host)"
ssh_vm "cd $REPO_IN_VM && export PATH=\$HOME/bin:\$PATH && \
	TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open && \
	TUIST_SKIP_UPDATE_CHECK=1 xcodebuild build -scheme MacSlowdown \
		-configuration Debug -destination 'platform=macOS' \
		-derivedDataPath .build -jobs 3 -quiet \
		CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
		PROVISIONING_PROFILE_SPECIFIER="
	# **Ad-hoc signed, and still sandboxed.** The VM holds no Apple Development
	# certificate, so the team-signed build fails outright. Ad-hoc keeps the
	# entitlements file, which is what decides whether the App Sandbox is on — so
	# the capture still shows what a sandboxed build sees, including the
	# other-uid processes it is denied. That matters: an unsandboxed capture
	# would show a census the shipping app can never produce.
	#
	# `probe/build-sandboxed.sh` records the other half of this rule: ad-hoc is
	# fine for measurement, never for an XCTest host app. Nothing here runs
	# XCTest.

# The **bundle**, launched through `open`, not the executable through `nohup`.
# A binary exec'd from an SSH session is not a full session member: it launches,
# but `activate(ignoringOtherApps:)` does not lift it above the Terminal window
# that is already there, and the first capture run photographed a terminal with
# the app's window edge just visible behind it. `open` goes through
# LaunchServices, which is also the rule `CLAUDE.md` already records for
# TCC-sensitive launches.
APP="$REPO_IN_VM/.build/Build/Products/Debug/MacSlowdown.app"

index=0
for section in "${SECTIONS[@]}"; do
	index=$((index + 1))
	slug="$(echo "$section" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
	file="$(printf '%02d-%s.png' "$index" "$slug")"
	echo "==> $section"

	ssh_vm "pkill -f MacSlowdown.app || true; sleep 2; \
		open -n -a '$APP' --args -ui-open main -ui-section '$section'; \
		sleep $SETTLE; \
		pgrep -f MacSlowdown.app >/dev/null || { echo 'app is not running'; exit 1; }; \
		osascript -e 'do shell script \"screencapture -x /tmp/$file\"'"

	sshpass -p "$VM_PASS" scp "${SSH_OPTS[@]}" \
		"$VM_USER@$IP:/tmp/$file" "$OUT/$file"
done

# **The shipping path, with no launch argument at all.** `-ui-open first-run`
# proves the window renders; it cannot prove TASK-65.20's actual criterion, which
# is that the window comes forward *without external intervention* on a cold
# launch under LSUIElement. The seam calls `activate(ignoringOtherApps:)`
# explicitly, so using it to answer that question would be assuming the
# conclusion. This shot launches the app exactly as a user would.
echo "==> First run, cold launch with no arguments"
ssh_vm "pkill -f MacSlowdown.app || true; sleep 2; \
	defaults delete com.brooksc.MacSlowdown firstRun.completed 2>/dev/null || true; \
	open -n -a '$APP'; \
	sleep 20; \
	osascript -e 'do shell script \"screencapture -x /tmp/07-first-run-cold.png\"'"
sshpass -p "$VM_PASS" scp "${SSH_OPTS[@]}" \
	"$VM_USER@$IP:/tmp/07-first-run-cold.png" "$OUT/07-first-run-cold.png"

echo "==> First run"
ssh_vm "pkill -f MacSlowdown.app || true; sleep 2; \
	defaults delete com.brooksc.MacSlowdown firstRun.completed 2>/dev/null || true; \
	open -n -a '$APP' --args -ui-open first-run; \
	sleep 20; \
	osascript -e 'do shell script \"screencapture -x /tmp/06-first-run.png\"'"
sshpass -p "$VM_PASS" scp "${SSH_OPTS[@]}" \
	"$VM_USER@$IP:/tmp/06-first-run.png" "$OUT/06-first-run.png"

ssh_vm "pkill -f MacSlowdown.app || true"
echo "==> Stopping $VM"
tart stop "$VM" || true

echo
echo "Captured into $OUT:"
ls -1 "$OUT"/*.png
