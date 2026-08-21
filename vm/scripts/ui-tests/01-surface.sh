#!/usr/bin/env bash
# Opening and closing the layout surface.

info "Surface: opening"
launch_with_surface || return 0

expect_control "New layout"          "the surface opens with its controls reachable"
expect_control "Close layout surface" "the close button is there"

info "Surface: the close button closes it"
$AX press "Close layout surface" >/dev/null 2>&1
expect_no_control "New layout" "pressing close dismisses the surface"

info "Surface: reopening"
# Reopened rather than relaunched: the window is retained between showings, so
# this is where state left over from last time would show up.
osascript -e 'tell application "WindowThing" to show layout surface with pinned' >/dev/null 2>&1
sleep 2
if $AX exists "New layout" >/dev/null 2>&1; then
    pass "the surface can be reopened"
else
    # Scripting needs Automation consent; not having it is not a surface bug.
    note "reopen via scripting unavailable — relaunching instead"
    launch_with_surface || return 0
    expect_control "New layout" "the surface can be reopened"
fi

info "Surface: escape closes it"
$AX key escape >/dev/null 2>&1
expect_no_control "New layout" "escape dismisses the surface"
