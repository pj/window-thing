#!/usr/bin/env bash
# Editing a layout's panes: splitting, changing type, removing.

info "Panes: splitting"
launch_with_surface || return 0

# Work on a layout of our own so the split/remove churn does not touch a real
# one — every assertion below changes the layout it runs against.
$AX press "New layout" >/dev/null 2>&1
$AX wait "Layout name" 10 >/dev/null 2>&1
$AX type "Layout name" "Pane Test" >/dev/null 2>&1
$AX confirm >/dev/null 2>&1

# The pane bar is gone: splitting is four buttons on the pane's own edges, each
# sitting at one end of the divider it draws. Top and bottom are the two ends of
# a vertical divider, left and right the two ends of a horizontal one, so the
# four buttons are two actions offered at whichever end is nearer.
expect_control "Split into columns, from the top — pane 1" \
    "a fresh layout has one pane, and it is addressable"
expect_control "Split into rows, from the left — pane 1" \
    "and the side buttons draw the other divider"

$AX press "Split into columns, from the top — pane 1" >/dev/null 2>&1
expect_control "Split into columns, from the top — pane 2" "splitting produces a second pane"

info "Panes: the stack cannot be removed"
# A layout needs somewhere for unpinned windows to land, so the control says so
# rather than simply being missing.
expect_control "The stack can't be removed — every layout needs one — pane 1" \
    "the stack's remove button explains why it is disabled"

info "Panes: changing what a pane holds"
# What a pane holds is chosen from the pane's own list now, not from a toggle in
# the pane bar. The bar only shapes the layout: split and remove.
expect_no_control "Hold one app here — pane 2" "nothing outside the list sets a pane's role"

$AX press "Stack — pane 2" >/dev/null 2>&1
expect_control "The stack can't be removed — every layout needs one — pane 2" \
    "choosing Stack from the list moves the stack to that pane"
expect_control "Remove this cell — pane 1" \
    "and pane 1, no longer the stack, becomes removable"

$AX press "Empty — pane 2" >/dev/null 2>&1
expect_control "Remove this cell — pane 2" "choosing Empty hands the role back"

info "Panes: removing one"
$AX press "Remove this cell — pane 2" >/dev/null 2>&1
expect_no_control "Split into columns, from the top — pane 2" "removing a pane collapses the split"

info "Panes: tidying up"
$AX press "Delete layout Pane Test" >/dev/null 2>&1
$AX wait "Delete Layout" 4 >/dev/null 2>&1
$AX press "Delete Layout" >/dev/null 2>&1
expect_no_control "Delete layout Pane Test" "the scratch layout is gone"
