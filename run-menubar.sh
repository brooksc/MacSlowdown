#!/bin/bash
# Canonical local build-and-run path. Does not open Xcode.
#
# `tuist run` cannot reliably resolve a macOS destination, so this builds the
# generated project with `tuist xcodebuild` and launches the product directly.

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-Debug}"
SCHEME="MacSlowdown"

./stop-menubar.sh || true

# Always regenerate: Project.swift globs Sources/**, so a newly added file is
# invisible to the build until the project is regenerated. Generation takes well
# under a second, so there is no reason to make this conditional.
nice env TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

# Explicit derivedDataPath so the product location is deterministic. Discovering
# it via -showBuildSettings is unreliable: tuist and plain xcodebuild resolve
# different DerivedData hashes for the same workspace.
DERIVED="${DERIVED:-.build}"

nice env TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
	-scheme "$SCHEME" \
	-configuration "$CONFIG" \
	-destination 'platform=macOS' \
	-derivedDataPath "$DERIVED"

APP="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"

if [ ! -d "$APP" ]; then
	echo "error: built app not found at $APP" >&2
	exit 1
fi

echo "launching: $APP"
open "$APP"
