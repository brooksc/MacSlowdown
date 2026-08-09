#!/bin/bash
# Builds a probe that needs the *shipping* Metrics code, sandboxed.
#
# build-probe.sh compiles a self-contained probe. This one compiles the probe
# together with Metrics/Sources, so it exercises the code the app runs rather
# than a reimplementation that can drift from it. Compiling the sources in
# directly (rather than linking the built framework) also reaches internal API
# without widening `public` in the shipping framework to suit a probe.
#
# Usage: build-with-metrics.sh <Sources/xyz-probe.swift> [output-dir]
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

# -parse-as-library keeps the probe's top-level code out of conflict with the
# framework sources, which have none.
nice swiftc -O -o "$APP/Contents/MacOS/$NAME" \
	-module-name ProbeWithMetrics \
	"$SRC" ../Metrics/Sources/*.swift

codesign --force --sign "$IDENTITY" \
	--entitlements Probe.entitlements \
	--options runtime \
	--timestamp=none \
	"$APP"

echo "built: $APP/Contents/MacOS/$NAME"
