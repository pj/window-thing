#!/usr/bin/env bash
# ui-lib.sh — shared machinery for the interface tests.
#
# Sourced by each file in vm/scripts/ui-tests/. Provides the driver wrapper, the
# assertions, and the app lifecycle, so a test file is only the behaviour it is
# checking.

PROJECT_DIR="${PROJECT_DIR:-$HOME/Projects/window_thing}"
APP="$PROJECT_DIR/build/WindowThing.app"

# Run as a script through /usr/bin/swift, not compiled first. Accessibility is
# granted to /usr/bin/swift by path, so a compiled copy would be a different
# client with no permission — and every query would come back empty, which reads
# as "the control isn't there" rather than "I wasn't allowed to look".
AX="swift $PROJECT_DIR/vm/scripts/ax-driver.swift"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; DIM='\033[2m'; NC='\033[0m'

: "${PASS_COUNT:=0}"
: "${FAIL_COUNT:=0}"

pass() { echo -e "  ${GREEN}pass${NC}  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info() { echo -e "${YELLOW}==>${NC} $1"; }
note() { echo -e "     ${DIM}$1${NC}"; }

# --------------------------------------------------------------------------- #
# Assertions                                                                    #
# --------------------------------------------------------------------------- #

# Waits, rather than checking once: the interface animates, and a bare check
# turns every timing difference into a failure.
expect_control() {
    if $AX wait "$1" 4 >/dev/null 2>&1; then pass "$2"; else fail "$2 (no control '$1')"; fi
}

expect_no_control() {
    if $AX gone "$1" 4 >/dev/null 2>&1; then pass "$2"; else fail "$2 ('$1' still present)"; fi
}

# Runs a driver command and fails the test if it errors, instead of hiding it.
# A silent failure here reads as "the interface did nothing", which sends you
# looking in the wrong place entirely.
drive() {
    local output
    if ! output="$($AX "$@" 2>&1)"; then
        fail "driver: $* — ${output//$'\n'/ }"
        return 1
    fi
    return 0
}

expect_value() {
    local actual
    actual="$($AX value "$1" 2>/dev/null)"
    if [ "$actual" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$actual')"; fi
}

expect_count() {
    local actual
    actual="$($AX count "$1" 2>/dev/null)"
    if [ "$actual" = "$2" ]; then pass "$3"; else fail "$3 (expected $2, got $actual)"; fi
}

expect_equal() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

# --------------------------------------------------------------------------- #
# App lifecycle                                                                 #
# --------------------------------------------------------------------------- #

quit_app() {
    pkill -x WindowThing 2>/dev/null || true
    # Wait for it to actually go. Leaving a dying instance around means `open`
    # starts a second one, and the driver may then talk to one instance while
    # keystrokes go to the other — which looks like typing silently not working.
    for _ in $(seq 1 20); do
        pgrep -x WindowThing >/dev/null || break
        sleep 0.5
    done
}

# Launch with the layout surface already open and pinned.
#
# Through `open`, not by running the executable: launching it directly leaves
# LaunchServices unaware this process handles com.windowthing.app, and Apple
# events sent to it time out — which looks like missing Automation consent.
launch_with_surface() {
    quit_app
    # No -n: the previous instance is gone, and forcing a second one is what
    # produced two processes for the driver to choose between.
    open -a "$APP" --args --screenshot space
    sleep 8

    local running
    running="$(pgrep -x WindowThing | wc -l | tr -d ' ')"
    if [ "$running" != "1" ]; then
        fail "expected exactly one app instance, found $running"
        return 1
    fi
}

# Launch without opening anything, for tests about opening it.
launch_plain() {
    quit_app
    open -a "$APP"
    sleep 6
}

# A layout with a pane that shows the window chooser.
#
# A fresh layout is a single stack, and the stack shows what has landed in it
# rather than a chooser — so anything testing the chooser has to make a pane
# that is not the stack first, instead of hoping the active layout happens to
# have one.
setup_chooser_pane() {
    local name="${1:-Chooser Scratch}"

    $AX press "New layout" >/dev/null 2>&1
    sleep 2
    drive type "Layout name" "$name" || return 1
    drive confirm || return 1
    sleep 2

    $AX press "Split into columns — pane 1" >/dev/null 2>&1
    sleep 2

    if ! $AX wait "Search apps and windows" 5 >/dev/null 2>&1; then
        fail "could not get a pane showing the chooser"
        return 1
    fi
    return 0
}

teardown_scratch_layout() {
    local name="$1"
    $AX press "Delete layout $name" >/dev/null 2>&1
    $AX wait "Delete Layout" 4 >/dev/null 2>&1
    $AX press "Delete Layout" >/dev/null 2>&1
    sleep 2
}

# A config of our own, so tests neither depend on nor disturb whatever layouts
# happen to exist in the VM.
CONFIG_DIR="$HOME/Library/Application Support/WindowThing"
BACKUP="$CONFIG_DIR/config.yaml.uitest-backup"

isolate_config() {
    mkdir -p "$CONFIG_DIR"
    [ -f "$CONFIG_DIR/config.yaml" ] && cp "$CONFIG_DIR/config.yaml" "$BACKUP"
    return 0
}

restore_config() {
    if [ -f "$BACKUP" ]; then
        mv "$BACKUP" "$CONFIG_DIR/config.yaml"
    fi
    return 0
}
