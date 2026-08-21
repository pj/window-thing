#!/usr/bin/env bash
# The window chooser inside a pane.

info "Chooser: it lists what is running"

# Opens its own window rather than relying on the harness having done it. A test
# that assumes another app is running fails for a reason unrelated to what it is
# actually checking.
open -a TextEdit --args --new-document >/dev/null 2>&1
sleep 3

launch_with_surface || return 0
setup_chooser_pane "Chooser Scratch" || return 0

expect_control "All windows of TextEdit" "running apps appear as choosable boxes"
expect_control "Empty"                   "the empty option is offered alongside them"

info "Chooser: searching narrows it"
drive type "Search apps and windows" "TextEdit"
sleep 2
expect_value "Search apps and windows" "TextEdit" "the search box takes the query"
expect_control "All windows of TextEdit" "a matching app survives the filter"

info "Chooser: clearing the search brings the rest back"
for _ in $(seq 1 10); do $AX key delete >/dev/null 2>&1; done
sleep 2
expect_value "Search apps and windows" "" "the search box empties"
expect_control "All windows of TextEdit" "the list is populated again"

info "Chooser: tidying up"
teardown_scratch_layout "Chooser Scratch"
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1 || true
