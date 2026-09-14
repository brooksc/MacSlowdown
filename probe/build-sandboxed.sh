#!/bin/bash
# Builds the Tier 0 probe as a signed, sandboxed .app bundle.
#
# Deliberately uses only swiftc + codesign, no xcodebuild, so the sandbox
# question can be answered independently of project/build-system setup.
# The sandbox is applied at exec based on the code signature, so running the
# inner binary directly from a terminal is genuinely sandboxed.

set -euo pipefail
cd "$(dirname "$0")"

# Discovered from the login keychain rather than hardcoded, so no personal
# signing identity lives in the repository. Override with IDENTITY=... to pick a
# specific certificate when more than one is present.
#
# IDENTITY="-" ad-hoc signs, which is what a CI runner must do: it holds no
# Apple Development certificate. Measured 2026-09-14 — an ad-hoc signature
# carries the app-sandbox entitlement and the sandbox is genuinely applied, so
# the probe's answers are as valid as a real-signed run.
IDENTITY="${IDENTITY:-$(
	security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Apple Development/ { print $2; exit }'
)}"

if [ -z "$IDENTITY" ]; then
	echo "error: no 'Apple Development' code-signing identity found in the keychain." >&2
	echo "       Set IDENTITY=\"<certificate name>\" to choose one explicitly," >&2
	echo "       or IDENTITY=\"-\" to ad-hoc sign (valid; see the note above)." >&2
	echo "       Available identities:" >&2
	security find-identity -v -p codesigning >&2
	exit 1
fi

# The bundle id is part of the experiment, not boilerplate.
#
# **A sandboxed binary hangs forever if it reuses a bundle id whose container
# was created by a different code signature.** Measured 2026-09-14 on final
# macOS 27: the process blocks in `_libsecinit_appsandbox` on a synchronous XPC
# round-trip to secinitd that never returns, during dyld initialisation — before
# `main`, so the probe prints nothing at all and looks like an infinite loop in
# our own code. It is not: an ad-hoc build and a real-signed build of the same
# bundle id are enough to trigger it, and deleting ~/Library/Containers/<id>
# does NOT clear it. Only a bundle id that has never been used does.
#
# So the id carries **which signature built it**: a short hash of the identity,
# plus a readable mode. Ad-hoc and real-signed builds then get separate
# containers and cannot poison each other, which is what lets the same script
# serve a developer machine and a CI runner. Two different developer
# certificates are likewise kept apart.
#
# GENERATION is the escape hatch, and it is needed because a poisoned id cannot
# be repaired — only abandoned. Bump it if a build of this probe starts hanging
# with no output; that is this failure and nothing else. `.tier0` (generation
# empty) and `.tier0.2` are burned on the author's machine, from the experiment
# that found all this.
#
# This also cost a day's confusion once: several probe binaries shared the bare
# `com.brooksc.MacSlowdown.Probe`, so the Tier 0 probe inherited a container
# another probe had created from a worktree that no longer exists. Every probe
# gets its own leaf id — `.tier0` here, `.$NAME` in build-probe.sh.
GENERATION="${GENERATION:-3}"
case "$IDENTITY" in
	-) SIGNER="adhoc" ;;
	*) SIGNER="dev-$(printf '%s' "$IDENTITY" | shasum | cut -c1-8)" ;;
esac
BUNDLE_ID="com.brooksc.MacSlowdown.Probe.tier0.g${GENERATION}.${SIGNER}"
OUT="${1:-./build}"
APP="$OUT/Probe.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Probe</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>Probe</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

nice swiftc -O -o "$APP/Contents/MacOS/Probe" Sources/main.swift

codesign --force --sign "$IDENTITY" \
	--entitlements Probe.entitlements \
	--options runtime \
	--timestamp=none \
	"$APP"

echo "--- signature ---"
codesign -d --entitlements - "$APP" 2>&1 | tail -12
echo ""
echo "built: $APP/Contents/MacOS/Probe"
