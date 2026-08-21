#!/usr/bin/env bash
# What the surface does with the keyboard.
#
# It reads bare keystrokes as commands — a letter is a cell address, space
# closes it — so wherever text is being typed it has to stand down. That
# behaviour exists only in the interface layer, which is why it is checked here.

info "Keyboard: typing in search is text, not shortcuts"
launch_with_surface || return 0
setup_chooser_pane "Keyboard Scratch" || return 0

drive type "Search apps and windows" "zzz"
sleep 2

expect_value "Search apps and windows" "zzz" "letters typed into search land as text"
expect_control "New layout" "the surface stays open — 'z' was not read as a shortcut"

info "Keyboard: escape gives up the field before the surface"
$AX key escape >/dev/null 2>&1
sleep 2
expect_control "New layout" "the first escape leaves the search field, not the surface"

info "Keyboard: escape cancels a rename rather than closing the surface"
$AX press "New layout" >/dev/null 2>&1
sleep 2
expect_control "Layout name" "adding a layout opens its rename field"

$AX key escape >/dev/null 2>&1
sleep 2
expect_no_control "Layout name" "escape closes the rename field"
expect_control "New layout"     "the surface survives cancelling a rename"

info "Keyboard: escape cancels a confirmation rather than closing the surface"
# The layout left unnamed by the cancelled rename above.
$AX press "Delete layout " >/dev/null 2>&1
if $AX wait "Delete Layout" 5 >/dev/null 2>&1; then
    pass "the unnamed layout still asks before deleting"
    $AX key escape >/dev/null 2>&1
    sleep 2
    expect_no_control "Delete Layout" "escape dismisses the confirmation"
    expect_control "New layout"       "the surface survives cancelling a delete"
else
    fail "no confirmation appeared for the unnamed layout"
fi

info "Keyboard: tidying up"
teardown_scratch_layout ""
teardown_scratch_layout "Keyboard Scratch"
