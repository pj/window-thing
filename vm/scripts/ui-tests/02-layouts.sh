#!/usr/bin/env bash
# The layout list: adding, renaming, deleting, and what delete asks first.

info "Layouts: adding"
launch_with_surface || return 0

before="$($AX count "Delete layout " 2>/dev/null)"
note "layouts before: $before"

$AX press "New layout" >/dev/null 2>&1
# The rename field opening is the signal that the add landed, so the count below
# is read from a settled list rather than after a guessed delay.
$AX wait "Layout name" 10 >/dev/null 2>&1
after="$($AX count "Delete layout " 2>/dev/null)"
expect_equal "$after" "$((before + 1))" "adding a layout adds exactly one"

# A new layout has no name yet: addLayout() creates it empty and opens the
# rename field, so naming it is the first thing a person does.
expect_control "Layout name" "a new layout opens its rename field"

info "Layouts: renaming"
RENAMED="Renamed By Test"
drive type "Layout name" "$RENAMED"

# Read the field back before committing. Without this the only signal is the
# outcome, which cannot say whether the characters failed to arrive or arrived
# and the commit did not apply them — two different bugs that look identical
# from the far end.
typed="$($AX value "Layout name" 2>/dev/null)"
note "field holds: '${typed}'"
expect_value "Layout name" "$RENAMED" "the whole name arrives in the field"

drive confirm

expect_control_verbose "Delete layout $RENAMED" \
    "the typed name reaches the layout" "Delete layout "
expect_no_control "Layout name"         "submitting closes the rename field"

info "Layouts: a cancelled delete"
$AX press "Delete layout $RENAMED" >/dev/null 2>&1
expect_control "Delete Layout" "deleting asks for confirmation first"

$AX press "Cancel" >/dev/null 2>&1
expect_control "Delete layout $RENAMED" "cancelling keeps the layout"
expect_no_control "Delete Layout"        "cancelling dismisses the dialog"

info "Layouts: a confirmed delete"
$AX press "Delete layout $RENAMED" >/dev/null 2>&1
$AX wait "Delete Layout" 4 >/dev/null 2>&1
$AX press "Delete Layout" >/dev/null 2>&1

expect_no_control "Delete layout $RENAMED" "confirming removes the layout"
final="$($AX count "Delete layout " 2>/dev/null)"
expect_equal "$final" "$before" "the list is back where it started"
