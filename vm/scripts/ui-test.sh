#!/usr/bin/env bash
# ui-test.sh — drive WindowThing's interface and check what it does.
#
# Runs *inside* the VM, in the logged-in GUI session. That is the whole point:
# these tests open windows, take focus and click things, so running them on a
# developer's own machine means taking over their screen.
#
# Usage (inside the VM):
#   ~/Projects/window_thing/vm/scripts/ui-test.sh
#
# Covers the layout lifecycle end to end: creating one, renaming it, cancelling
# a delete, then confirming one. The delete confirmation in particular cannot be
# checked any other way — it exists precisely to sit between a click and the
# model, so a test that calls the model directly proves nothing about it.

set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/Projects/window_thing}"
APP="$PROJECT_DIR/build/WindowThing.app"
AX="swift $PROJECT_DIR/vm/scripts/ax-driver.swift"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass_count=0
fail_count=0

pass() { echo -e "  ${GREEN}pass${NC}  $1"; pass_count=$((pass_count + 1)); }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; fail_count=$((fail_count + 1)); }
info() { echo -e "${YELLOW}==>${NC} $1"; }

# Assert that a control with this label is present / absent.
expect_control() {
    if $AX exists "$1" >/dev/null 2>&1; then pass "$2"; else fail "$2 (no control '$1')"; fi
}
expect_no_control() {
    if $AX exists "$1" >/dev/null 2>&1; then fail "$2 (control '$1' still there)"; else pass "$2"; fi
}

cleanup() {
    osascript -e 'tell application "WindowThing" to hide layout surface' >/dev/null 2>&1 || true
    pkill -x WindowThing 2>/dev/null || true
}
trap cleanup EXIT

# --------------------------------------------------------------------------- #
# Build and launch                                                             #
# --------------------------------------------------------------------------- #

info "Building the app bundle"
if ! "$PROJECT_DIR/scripts/package.sh" --no-sign >/tmp/ui-test-build.log 2>&1; then
    echo "build failed; see /tmp/ui-test-build.log"
    tail -20 /tmp/ui-test-build.log
    exit 1
fi

# A fresh config, so the test neither depends on nor disturbs whatever layouts
# happen to exist in the VM.
CONFIG_DIR="$HOME/Library/Application Support/WindowThing"
mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG_DIR/config.yaml" ] && mv "$CONFIG_DIR/config.yaml" "$CONFIG_DIR/config.yaml.uitest-backup"
restore_config() {
    [ -f "$CONFIG_DIR/config.yaml.uitest-backup" ] && \
        mv "$CONFIG_DIR/config.yaml.uitest-backup" "$CONFIG_DIR/config.yaml"
}
trap 'cleanup; restore_config' EXIT

pkill -x WindowThing 2>/dev/null || true
sleep 1

info "Launching with the layout surface open"
# --screenshot space opens the surface and pins it, so it survives this script
# taking focus — which it must, to drive anything.
"$APP/Contents/MacOS/WindowThing" --screenshot space >/tmp/ui-test-app.log 2>&1 &
sleep 8

if ! pgrep -x WindowThing >/dev/null; then
    echo "app did not stay running; see /tmp/ui-test-app.log"
    tail -20 /tmp/ui-test-app.log
    exit 1
fi

# --------------------------------------------------------------------------- #
# The surface is up                                                            #
# --------------------------------------------------------------------------- #

info "Surface"
expect_control "New layout" "the surface is open and its controls are reachable"
expect_control "Close layout surface" "the close button is labelled"

before=$($AX list 2>/dev/null | grep -c "Delete layout ")
echo "     layouts before: $before"

# --------------------------------------------------------------------------- #
# Add                                                                          #
# --------------------------------------------------------------------------- #

info "Adding a layout"
$AX press "New layout" >/dev/null 2>&1
sleep 2

after=$($AX list 2>/dev/null | grep -c "Delete layout ")
if [ "$after" -gt "$before" ]; then
    pass "adding a layout adds one ($before -> $after)"
else
    fail "adding a layout did nothing ($before -> $after)"
fi

# The new layout is whichever name wasn't there before.
NEW_LAYOUT=$($AX list 2>/dev/null | sed -n 's/.*Delete layout //p' | tail -1)
echo "     new layout: '$NEW_LAYOUT'"

# --------------------------------------------------------------------------- #
# Rename                                                                       #
# --------------------------------------------------------------------------- #

info "Renaming it"
RENAMED="Renamed By Test"
if osascript -e "tell application \"WindowThing\" to rename layout \"$NEW_LAYOUT\" to \"$RENAMED\"" >/dev/null 2>&1; then
    sleep 2
    expect_control "Delete layout $RENAMED" "the rename reaches the interface"
    expect_no_control "Delete layout $NEW_LAYOUT" "the old name is gone"
else
    # Sending Apple events needs Automation consent for this sender and target.
    # Worth reporting rather than failing: the rest of the lifecycle still runs.
    echo -e "  ${YELLOW}skip${NC}  rename (AppleScript unavailable — Automation not granted?)"
    RENAMED="$NEW_LAYOUT"
fi

# --------------------------------------------------------------------------- #
# Delete — cancelled                                                           #
# --------------------------------------------------------------------------- #

info "Cancelling a delete"
$AX press "Delete layout $RENAMED" >/dev/null 2>&1
sleep 2

if $AX exists "Delete Layout" >/dev/null 2>&1; then
    pass "the delete button asks for confirmation"
else
    fail "no confirmation appeared"
fi

$AX press "Cancel" >/dev/null 2>&1
sleep 2
expect_control "Delete layout $RENAMED" "cancelling keeps the layout"

# --------------------------------------------------------------------------- #
# Delete — confirmed                                                           #
# --------------------------------------------------------------------------- #

info "Confirming a delete"
$AX press "Delete layout $RENAMED" >/dev/null 2>&1
sleep 2
$AX press "Delete Layout" >/dev/null 2>&1
sleep 2

expect_no_control "Delete layout $RENAMED" "confirming removes the layout"

final=$($AX list 2>/dev/null | grep -c "Delete layout ")
if [ "$final" -eq "$before" ]; then
    pass "the layout list is back where it started ($final)"
else
    fail "expected $before layouts, found $final"
fi

# --------------------------------------------------------------------------- #

echo
echo "passed: $pass_count   failed: $fail_count"
[ "$fail_count" -eq 0 ] || exit 1
