#!/bin/bash
# Standalone FR-030 measurement, signed and sandboxed.
#
# Run outside the test bundle deliberately: the harness measures the whole
# process, so inside a parallel test run it counts other suites' work too. This
# is the authoritative figure.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${IDENTITY:-$(
	security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Apple Development/ { print $2; exit }'
)}"
SECONDS_TO_RUN="${1:-60}"
BUILD="$(cd ../.. && pwd)/.build/Build/Products/Debug"
APP=build/Overhead.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Overhead</string>
	<key>CFBundleIdentifier</key><string>com.brooksc.MacSlowdown.Overhead</string>
	<key>CFBundleName</key><string>Overhead</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

nice swiftc -O -parse-as-library \
	-F "$BUILD" -framework Metrics \
	-Xlinker -rpath -Xlinker "$BUILD" \
	-o "$APP/Contents/MacOS/Overhead" main.swift

codesign --force --sign "$IDENTITY" --entitlements ../Probe.entitlements \
	--options runtime --timestamp=none "$APP" >/dev/null

"$APP/Contents/MacOS/Overhead" "$SECONDS_TO_RUN"
