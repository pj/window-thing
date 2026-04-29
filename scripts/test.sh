#!/bin/bash
# test.sh — Run WindowThing tests using the Xcode toolchain.
#
# Usage:
#   scripts/test.sh                          # run all tests
#   scripts/test.sh --filter WindowThingTests  # run specific target

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Resolve the Xcode developer dir (mirrors what the nix devShell sets)
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
XCODE_TOOLCHAIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin"
export DEVELOPER_DIR
export SDKROOT="${DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
export PATH="${XCODE_TOOLCHAIN}:${PATH}"

SWIFT="${XCODE_TOOLCHAIN}/swift"

cd "$PROJECT_DIR"

echo "Running tests..."
"$SWIFT" test "$@" 2>&1
