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
IDENTITY="${IDENTITY:-$(
	security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Apple Development/ { print $2; exit }'
)}"

if [ -z "$IDENTITY" ]; then
	echo "error: no 'Apple Development' code-signing identity found in the keychain." >&2
	echo "       Set IDENTITY=\"<certificate name>\" to choose one explicitly." >&2
	echo "       Available identities:" >&2
	security find-identity -v -p codesigning >&2
	exit 1
fi

BUNDLE_ID="com.brooksc.MacSlowdown.Probe"
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
