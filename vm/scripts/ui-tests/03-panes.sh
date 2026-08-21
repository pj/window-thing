#!/usr/bin/env bash
# Editing a layout's panes: splitting, changing type, removing.

info "Panes: splitting"
launch_with_surface || return 0

# Work on a layout of our own so the split/remove churn does not touch a real
# one — every assertion below changes the layout it runs against.
$AX press "New layout" >/dev/null 2>&1
sleep 2
$AX type "Layout name" "Pane Test" >/dev/null 2>&1
$AX confirm >/dev/null 2>&1
sleep 2

expect_control "Split into columns — pane 1" "a fresh layout has one pane, and it is addressable"

$AX press "Split into columns — pane 1" >/dev/null 2>&1
sleep 2
expect_control "Split into columns — pane 2" "splitting into columns produces a second pane"

info "Panes: the stack cannot be removed"
# A layout needs somewhere for unpinned windows to land, so the control says so
# rather than simply being missing.
expect_control "The stack can't be removed — every layout needs one — pane 1" \
    "the stack's remove button explains why it is disabled"

info "Panes: changing a pane's type"
$AX press "Hold one app here — pane 2" >/dev/null 2>&1
sleep 2
expect_control "Remove this cell — pane 2" "a pinned pane can be removed"

info "Panes: removing one"
$AX press "Remove this cell — pane 2" >/dev/null 2>&1
sleep 2
expect_no_control "Split into columns — pane 2" "removing a pane collapses the split"

info "Panes: tidying up"
$AX press "Delete layout Pane Test" >/dev/null 2>&1
$AX wait "Delete Layout" 4 >/dev/null 2>&1
$AX press "Delete Layout" >/dev/null 2>&1
sleep 2
expect_no_control "Delete layout Pane Test" "the scratch layout is gone"
