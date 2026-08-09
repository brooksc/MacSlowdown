#!/bin/bash
# Builds one probe source as a signed, sandboxed .app bundle.
#
# build-sandboxed.sh hardcodes Sources/main.swift, the Tier 0 probe. This is the
# same recipe parameterised by source file, so a later question does not require
# either editing that script or answering the question unsandboxed — and an
# unsandboxed binary proves nothing about the sandbox.
#
# Usage: build-probe.sh <Sources/xyz-probe.swift> [output-dir]
set -euo pipefail
cd "$(dirname "$0")"

SRC="$1"
OUT="${2:-./build}"
NAME="$(basename "$SRC" .swift)"
APP="$OUT/$NAME.app"

IDENTITY="${IDENTITY:-$(
	security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Apple Development/ { print $2; exit }'
)}"
if [ -z "$IDENTITY" ]; then
	echo "error: no 'Apple Development' code-signing identity found." >&2
	exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>$NAME</string>
	<key>CFBundleIdentifier</key><string>com.brooksc.MacSlowdown.Probe.$NAME</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

nice swiftc -O -o "$APP/Contents/MacOS/$NAME" "$SRC"

codesign --force --sign "$IDENTITY" \
	--entitlements Probe.entitlements \
	--options runtime \
	--timestamp=none \
	"$APP"

echo "built: $APP/Contents/MacOS/$NAME"
