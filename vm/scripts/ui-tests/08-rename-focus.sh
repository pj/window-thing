#!/usr/bin/env bash
# Typing a layout's name while a chooser is on screen.
#
# The surface reads bare keystrokes as commands, and space closes it. So the
# moment a text field has focus it has to stand down — and the rename field is
# not the only text field on screen. Every pane that is not the stack draws a
# chooser with its own search box.
#
# 02-layouts renames in a fresh layout, which is a single stack and therefore
# has no chooser at all. That is why it passed while typing a name was closing
# the surface for real: the arrangement that breaks needs a search field present.

info "Rename focus: a name can be typed while a chooser is on screen"
launch_with_surface || return 0

# A pane that is not the stack, so a search field exists alongside the rename.
setup_chooser_pane "Focus Scratch" || return 0
expect_control "Search apps and windows" "a search field is on screen alongside the rename"

$AX press "New layout" >/dev/null 2>&1
sleep 2
expect_control "Layout name" "adding a layout opens its rename field"

# A name with a space in it. Space is the keystroke that closes the surface when
# the app thinks no text field has focus, so it is the one that matters.
SPACED="Two Words"
drive type "Layout name" "$SPACED"
sleep 2

expect_control "New layout" "the surface is still open while typing a name"
expect_value "Layout name" "$SPACED" "the whole name, spaces included, went into the field"

drive confirm
sleep 2
expect_control "Delete layout $SPACED" "the typed name reaches the layout"

info "Rename focus: tidying up"
teardown_scratch_layout "$SPACED"
teardown_scratch_layout "Focus Scratch"
