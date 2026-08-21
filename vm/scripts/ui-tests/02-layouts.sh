#!/usr/bin/env bash
# The layout list: adding, renaming, deleting, and what delete asks first.

info "Layouts: adding"
launch_with_surface || return 0

before="$($AX count "Delete layout " 2>/dev/null)"
note "layouts before: $before"

$AX press "New layout" >/dev/null 2>&1
sleep 2
after="$($AX count "Delete layout " 2>/dev/null)"
expect_equal "$after" "$((before + 1))" "adding a layout adds exactly one"

# A new layout has no name yet: addLayout() creates it empty and opens the
# rename field, so naming it is the first thing a person does.
expect_control "Layout name" "a new layout opens its rename field"

info "Layouts: renaming"
RENAMED="Renamed By Test"
drive type "Layout name" "$RENAMED"
drive confirm
sleep 2

expect_control "Delete layout $RENAMED" "the typed name reaches the layout"
expect_no_control "Layout name"         "submitting closes the rename field"

info "Layouts: a cancelled delete"
$AX press "Delete layout $RENAMED" >/dev/null 2>&1
expect_control "Delete Layout" "deleting asks for confirmation first"

$AX press "Cancel" >/dev/null 2>&1
sleep 2
expect_control "Delete layout $RENAMED" "cancelling keeps the layout"
expect_no_control "Delete Layout"        "cancelling dismisses the dialog"

info "Layouts: a confirmed delete"
$AX press "Delete layout $RENAMED" >/dev/null 2>&1
$AX wait "Delete Layout" 4 >/dev/null 2>&1
$AX press "Delete Layout" >/dev/null 2>&1
sleep 2

expect_no_control "Delete layout $RENAMED" "confirming removes the layout"
final="$($AX count "Delete layout " 2>/dev/null)"
expect_equal "$final" "$before" "the list is back where it started"
