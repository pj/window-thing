#!/usr/bin/env bash
# Does a change to the layout list actually stick?
#
# The interface tests above check that a layout appears after adding it. That is
# not the same thing: a layout can show up in the surface, be written to the
# config, and still be lost — because the surface re-reads its list from the
# layout manager every time it opens, and the manager was never told.

info "Persistence: a new layout survives closing the surface"
launch_with_surface || return 0

STICKY="Sticky Layout"
$AX press "New layout" >/dev/null 2>&1
sleep 2
drive type "Layout name" "$STICKY"
drive confirm
sleep 2
expect_control "Delete layout $STICKY" "the layout is there before closing"

# Close and reopen, which is what re-reads the manager's list.
$AX press "Close layout surface" >/dev/null 2>&1
sleep 2
osascript -e 'tell application "WindowThing" to show layout surface with pinned' >/dev/null 2>&1
sleep 3
if ! $AX exists "New layout" >/dev/null 2>&1; then
    note "reopen via scripting unavailable — relaunching instead"
    launch_with_surface || return 0
fi

expect_control "Delete layout $STICKY" "the layout is still there after reopening"

info "Persistence: it survives the app restarting"
launch_with_surface || return 0
expect_control "Delete layout $STICKY" "the layout is still there after a relaunch"

info "Persistence: deleting it sticks too"
$AX press "Delete layout $STICKY" >/dev/null 2>&1
$AX wait "Delete Layout" 4 >/dev/null 2>&1
$AX press "Delete Layout" >/dev/null 2>&1
sleep 2

launch_with_surface || return 0
expect_no_control "Delete layout $STICKY" "the deletion survives a relaunch"
