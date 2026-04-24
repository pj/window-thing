#!/bin/bash
# dev.sh — Build, run, or restart WindowThing and open the editor.
#
# Usage:
#   scripts/dev.sh          # build (debug) + restart + open editor
#   scripts/dev.sh --release # build release + restart + open editor
#   scripts/dev.sh --run     # restart from last build without rebuilding
#   scripts/dev.sh --build   # build only, no restart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="WindowThing"

# Resolve the Xcode developer dir (mirrors what the nix devShell sets)
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
XCODE_TOOLCHAIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin"
export DEVELOPER_DIR
export SDKROOT="${DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
export PATH="${XCODE_TOOLCHAIN}:${PATH}"

SWIFT="${XCODE_TOOLCHAIN}/swift"

# ---- flags ---------------------------------------------------------------

BUILD=true
RESTART=true
OPEN_EDITOR=true
BUILD_CONFIG="debug"

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)  BUILD_CONFIG="release"; shift ;;
        --run)      BUILD=false;            shift ;;
        --build)    RESTART=false; OPEN_EDITOR=false; shift ;;
        --help|-h)
            sed -n '2,8p' "$0" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

BINARY="${PROJECT_DIR}/.build/${BUILD_CONFIG}/${APP_NAME}"

# ---- build ---------------------------------------------------------------

if [ "$BUILD" = true ]; then
    echo "Building ${APP_NAME} (${BUILD_CONFIG})..."
    cd "$PROJECT_DIR"
    if [ "$BUILD_CONFIG" = "release" ]; then
        "$SWIFT" build -c release 2>&1
    else
        "$SWIFT" build 2>&1
    fi
    echo "Build complete."
fi

if [ ! -f "$BINARY" ]; then
    echo "Binary not found at ${BINARY} — run without --run to build first." >&2
    exit 1
fi

# ---- restart -------------------------------------------------------------

if [ "$RESTART" = true ]; then
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "Stopping running ${APP_NAME}..."
        pkill -x "$APP_NAME" || true
        # Wait for it to fully exit
        for i in {1..20}; do
            pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
            sleep 0.2
        done
    fi

    echo "Starting ${APP_NAME}..."
    "$BINARY" &
    disown

    # Wait for the app to appear in the process list
    for i in {1..30}; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 && break
        sleep 0.2
    done
    echo "${APP_NAME} running (pid $(pgrep -x "$APP_NAME"))."
fi

# ---- open editor ---------------------------------------------------------

if [ "$OPEN_EDITOR" = true ]; then
    sleep 0.5  # give the app a moment to register its menu extras
    # Send a left-click activation via AppleScript — the menubar icon handler
    # opens the editor on left-click.
    osascript -e "
        tell application \"System Events\"
            tell process \"${APP_NAME}\"
                set frontmost to true
            end tell
        end tell
    " 2>/dev/null || true

    # Alternatively trigger via the Open Editor menu item
    osascript -e "
        tell application \"System Events\"
            tell process \"${APP_NAME}\"
                try
                    click menu item \"Open Editor\xE2\x80\xA6\" of menu 1 of menu bar item 1 of menu bar 1
                end try
            end tell
        end tell
    " 2>/dev/null || true

    echo "Editor opened."
fi
