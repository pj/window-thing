#!/usr/bin/env bash
# Does a change to the layout list actually reach disk, and survive?
#
# The tests above check that a layout appears in the surface after adding it.
# That is not the same thing. A layout can show up, be written to config.yaml,
# and still be lost — the surface re-reads its list from the layout manager
# every time it opens, so if the manager was never told, the next reopen drops
# it and the save after that writes it back out of the file.
#
# So these assert against config.yaml itself, not just against the interface.

CONFIG="$HOME/Library/Application Support/WindowThing/config.yaml"

# How many layouts the file claims, and whether a given name is among them.
config_layout_count() { grep -c '^  name:' "$CONFIG" 2>/dev/null || echo 0; }
config_has_layout()   { grep -q "^  name: $1\$" "$CONFIG" 2>/dev/null; }

# Both poll: the write to config.yaml happens off the back of the edit rather
# than synchronously with it, so checking once means sleeping first and hoping.
expect_in_config() {
    local deadline=$((SECONDS + ASSERT_TIMEOUT))
    while :; do
        if config_has_layout "$1"; then pass "$2"; return 0; fi
        [ "$SECONDS" -ge "$deadline" ] && break
        sleep 0.2
    done
    fail "$2 (not in config.yaml)"
}
expect_not_in_config() {
    local deadline=$((SECONDS + ASSERT_TIMEOUT))
    while :; do
        if ! config_has_layout "$1"; then pass "$2"; return 0; fi
        [ "$SECONDS" -ge "$deadline" ] && break
        sleep 0.2
    done
    fail "$2 (still in config.yaml)"
}

info "Persistence: adding a layout"
launch_with_surface || return 0

STICKY="Sticky Layout"
before_count="$(config_layout_count)"
note "config.yaml holds $before_count layouts"

$AX press "New layout" >/dev/null 2>&1
$AX wait "Layout name" 10 >/dev/null 2>&1
drive type "Layout name" "$STICKY"
drive confirm

expect_control  "Delete layout $STICKY" "the layout appears in the surface"
expect_in_config "$STICKY"              "the name reaches config.yaml"

after_count="$(config_layout_count)"
expect_equal "$after_count" "$((before_count + 1))" "config.yaml gained exactly one layout"

info "Persistence: it survives reopening the surface"
# The heart of it. Reopening re-reads the layout manager's list, so a layout the
# manager never heard about disappears here — while config.yaml still has it,
# which is why the file alone is not evidence.
#
# Reopened in the same process on purpose: relaunching would reload the file and
# paper over precisely the fault being tested.
$AX press "Close layout surface" >/dev/null 2>&1
$AX gone "New layout" 8 >/dev/null 2>&1
reopen_surface_in_process || return 0

expect_control   "Delete layout $STICKY" "the layout is still in the surface after reopening"
expect_in_config "$STICKY"               "config.yaml still holds it"
expect_equal "$(config_layout_count)" "$after_count" "no layouts were dropped from the file"

info "Persistence: renaming it again also sticks"
# The rename that matters here is of a layout that already exists, rather than
# the one that opens automatically when a layout is created.
RENAMED="Renamed Sticky"
$AX press "New layout" >/dev/null 2>&1
$AX wait "Layout name" 10 >/dev/null 2>&1
drive type "Layout name" "$RENAMED"
drive confirm

expect_in_config "$RENAMED" "a second layout's name reaches config.yaml"
expect_in_config "$STICKY"  "the first layout is still in the file"

info "Persistence: deleting reaches the file too"
$AX press "Delete layout $RENAMED" >/dev/null 2>&1
$AX wait "Delete Layout" 4 >/dev/null 2>&1
$AX press "Delete Layout" >/dev/null 2>&1

expect_not_in_config "$RENAMED" "the deleted layout leaves config.yaml"
expect_in_config     "$STICKY"  "deleting one layout does not take the others"

info "Persistence: everything survives a relaunch"
launch_with_surface || return 0
expect_control       "Delete layout $STICKY" "the kept layout is there after a relaunch"
expect_no_control    "Delete layout $RENAMED" "the deleted layout stays deleted"
expect_in_config     "$STICKY"                "config.yaml agrees after a relaunch"
expect_not_in_config "$RENAMED"               "config.yaml has no trace of the deleted one"

info "Persistence: tidying up"
teardown_scratch_layout "$STICKY"
