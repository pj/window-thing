#!/usr/bin/env bash
# ui-lib.sh — shared machinery for the interface tests.
#
# Sourced by each file in vm/scripts/ui-tests/. Provides the driver wrapper, the
# assertions, and the app lifecycle, so a test file is only the behaviour it is
# checking.

# Derived from this script's own location rather than named, so the harness
# works unchanged in whichever project it was synced into.
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
APP="$PROJECT_DIR/build/WindowThing.app"

# Compiled once, then run as a binary.
#
# Running it as `swift ax-driver.swift` re-compiles the script on every single
# invocation — 0.6s a call against 0.03s for the compiled binary, and the suite
# makes over a hundred calls. TCC grants are rows keyed on an absolute path, so
# the compiled binary is granted the same way `/usr/bin/swift` is; the path below
# is fixed precisely so grant-tcc-access.sh can authorise it ahead of time.
AX="$PROJECT_DIR/build/ax-driver"
AX_SOURCE="$PROJECT_DIR/vm/scripts/ax-driver.swift"

# Built on the host and copied in, so this only checks it arrived.
#
# The VM image carries no Swift toolchain, so there is nothing here to compile
# with. `vm/run-tests.sh` builds this and the app bundle before it syncs.
build_driver() {
    if [ -x "$AX" ]; then return 0; fi
    echo "the interface driver is missing at $AX"
    echo "it is built on the host — run the suite through vm/run-tests.sh,"
    echo "which builds it and copies it in."
    return 1
}

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

# Like expect_control, these retry rather than checking once.
#
# A single check has to be preceded by a sleep long enough for the interface to
# have caught up, and that sleep is paid in full on every run whether it was
# needed or not. Retrying costs only as long as the interface actually takes.
ASSERT_TIMEOUT="${ASSERT_TIMEOUT:-8}"

expect_value() {
    local actual deadline
    deadline=$((SECONDS + ASSERT_TIMEOUT))
    while :; do
        actual="$($AX value "$1" 2>/dev/null)"
        if [ "$actual" = "$2" ]; then pass "$3"; return 0; fi
        [ "$SECONDS" -ge "$deadline" ] && break
        sleep 0.2
    done
    fail "$3 (expected '$2', got '$actual')"
}

expect_count() {
    local actual deadline
    deadline=$((SECONDS + ASSERT_TIMEOUT))
    while :; do
        actual="$($AX count "$1" 2>/dev/null)"
        if [ "$actual" = "$2" ]; then pass "$3"; return 0; fi
        [ "$SECONDS" -ge "$deadline" ] && break
        sleep 0.2
    done
    fail "$3 (expected $2, got $actual)"
}

expect_equal() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

# Prints every control whose label starts with a prefix.
#
# For when an assertion says a control is missing and the useful question is
# what is there instead — "no control 'Delete layout Renamed By Test'" does not
# say whether the layout is called something else or absent altogether.
note_controls_matching() {
    local prefix="$1"
    local found
    found="$($AX list 2>/dev/null | grep -F "$prefix" | sed 's/^ *//' | tr '\n' '|')"
    note "controls matching '$prefix': ${found:-<none>}"
}

# Like expect_control, but says what it found when it fails.
expect_control_verbose() {
    if $AX wait "$1" 4 >/dev/null 2>&1; then
        pass "$2"
    else
        fail "$2 (no control '$1')"
        note_controls_matching "$3"
    fi
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
# Starts the app, retrying if LaunchServices refuses.
#
# Through `open`, not by running the executable: launching it directly leaves
# LaunchServices unaware this process handles com.windowthing.app, and Apple
# events sent to it time out — which looks like missing Automation consent.
#
# The retry is for the other side of that same bookkeeping. For a short window
# after the process exits, LaunchServices still believes it is running and
# rejects `open` outright with -600, so nothing starts at all. Waiting for pgrep
# to clear is not enough — LaunchServices lets go a moment later than the kernel
# does — and the resulting failure lands much later, as a surface that never
# appeared.
open_app() {
    local attempt
    for attempt in 1 2 3; do
        if open -a "$APP" "$@" 2>/tmp/ui-open.log; then
            return 0
        fi
        note "open refused the app (attempt $attempt): $(tr -d '\n' </tmp/ui-open.log)"
        sleep 1
    done
    return 1
}

launch_with_surface() {
    quit_app
    # No -n: the previous instance is gone, and forcing a second one is what
    # produced two processes for the driver to choose between.
    # WT_EXTRA_ARGS lets a diagnostic run add flags (--probe-render) without
    # editing the tests, so the run being measured is the same one that fails.
    # shellcheck disable=SC2086
    if ! open_app --args --screenshot space ${WT_EXTRA_ARGS:-}; then
        fail "the app could not be launched"
        return 1
    fi

    # Waits for the surface itself rather than sleeping a fixed span. Launch
    # time varies with what else the VM is doing, so any constant is either
    # slower than it needs to be or occasionally too short.
    if ! $AX wait "New layout" 25 >/dev/null 2>&1; then
        fail "the surface did not open within 25s"
        return 1
    fi

    local running
    running="$(pgrep -x WindowThing | wc -l | tr -d ' ')"
    if [ "$running" != "1" ]; then
        fail "expected exactly one app instance, found $running"
        return 1
    fi
}

# Launch without opening anything, for tests about opening it.
#
# Cannot wait on a named control the way launch_with_surface does: what appears
# is the point of those tests — onboarding on a first run, nothing at all
# otherwise. So it waits for the process to start answering Accessibility
# queries at all, and lets the assertions poll for whatever should follow.
launch_plain() {
    quit_app
    if ! open_app; then
        fail "the app could not be launched"
        return 1
    fi
    wait_for_app_ready
}

wait_for_app_ready() {
    local deadline
    deadline=$((SECONDS + 25))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if pgrep -x WindowThing >/dev/null 2>&1 \
           && [ "$($AX list 2>/dev/null | head -1)" != "controls: 0" ]; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

# Reopen the surface *without restarting the app*.
#
# This distinction is the whole point of the persistence tests. Relaunching
# re-reads config.yaml from disk, so the app comes back correct no matter what
# state it had in memory — which hides exactly the bug where the editor's list
# and the layout manager's have drifted apart. Going through the menubar keeps
# the same process, and the same in-memory state, alive.
#
# Driven with System Events because status items live in the system's menu bar
# extras rather than the app's own Accessibility tree, so the driver cannot see
# them. The global hotkey would be the other way in, but a synthesised chord
# does not trigger a Carbon hotkey in the VM.
reopen_surface_in_process() {
    local pid_before
    pid_before="$(pgrep -x WindowThing)"

    osascript <<'OSA' >/dev/null 2>&1
tell application "System Events"
  tell process "WindowThing"
    click menu bar item 1 of menu bar 2
    delay 1
    click menu item "Layout Editor" of menu 1 of menu bar item 1 of menu bar 2
  end tell
end tell
OSA
    if ! $AX wait "New layout" 10 >/dev/null 2>&1; then
        fail "the surface did not reopen via the menubar"
        return 1
    fi

    local pid_after
    pid_after="$(pgrep -x WindowThing)"
    if [ "$pid_before" != "$pid_after" ]; then
        fail "the app restarted — this test needs the same process"
        return 1
    fi
    return 0
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
    $AX wait "Layout name" 10 >/dev/null 2>&1
    drive type "Layout name" "$name" || return 1
    drive confirm || return 1
    $AX wait "Delete layout $name" 10 >/dev/null 2>&1

    $AX press "Split into columns, from the top — pane 1" >/dev/null 2>&1

    if ! $AX wait "Search apps and windows" 10 >/dev/null 2>&1; then
        # Distinguish the two ways this goes wrong. If the surface has gone
        # entirely, a keystroke was taken as a command — space closes it — which
        # is a different fault from a pane simply not showing a chooser.
        if $AX exists "New layout" >/dev/null 2>&1; then
            fail "the pane is not showing a chooser"
        else
            fail "the surface closed while setting up — a keystroke was read as a command"
        fi
        return 1
    fi
    return 0
}

teardown_scratch_layout() {
    local name="$1"
    $AX press "Delete layout $name" >/dev/null 2>&1
    $AX wait "Delete Layout" 4 >/dev/null 2>&1
    $AX press "Delete Layout" >/dev/null 2>&1

    # Reported but never fatal. This is cleanup, not an assertion — and because
    # each test file is sourced, letting the last command's status escape makes
    # a tidy-up hiccup look like the test itself failed.
    if ! $AX gone "Delete layout $name" 8 >/dev/null 2>&1; then
        note "scratch layout '$name' outlived its teardown"
    fi
    return 0
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
