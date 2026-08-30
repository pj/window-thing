#!/usr/bin/env bash
# The window chooser inside a pane.

info "Chooser: it lists what is running"

# Opens its own window rather than relying on the harness having done it. A test
# that assumes another app is running fails for a reason unrelated to what it is
# actually checking.
open -a TextEdit --args --new-document >/dev/null 2>&1
for _ in $(seq 1 40); do pgrep -x TextEdit >/dev/null && break; sleep 0.25; done

launch_with_surface || return 0
setup_chooser_pane "Chooser Scratch" || return 0

expect_control "All windows of TextEdit" "running apps appear as choosable boxes"

# The two roles a pane can play lead the list, above the apps. Both are named
# for their pane: every pane draws the same list, so a bare "Empty" would be
# several identical controls with no way to say which one is meant.
expect_control "Empty — pane 2" "the empty option is offered alongside them"
expect_control "Stack — pane 2" "and so is the stack"

info "Chooser: searching narrows it"
drive type "Search apps and windows" "TextEdit"
expect_value "Search apps and windows" "TextEdit" "the search box takes the query"
expect_control "All windows of TextEdit" "a matching app survives the filter"

info "Chooser: clearing the search brings the rest back"
for _ in $(seq 1 10); do $AX key delete >/dev/null 2>&1; done
expect_value "Search apps and windows" "" "the search box empties"
expect_control "All windows of TextEdit" "the list is populated again"

info "Chooser: tidying up"
teardown_scratch_layout "Chooser Scratch"
osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1 || true
