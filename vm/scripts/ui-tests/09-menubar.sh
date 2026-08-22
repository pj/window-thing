#!/usr/bin/env bash
# The menubar menu.
#
# Driven through System Events rather than the driver: status items live in the
# system's menu bar extras, not in the app's own Accessibility tree, so
# ax-driver cannot see them at all.
#
# The menu is rebuilt as it opens. It used to be assembled once at launch, so
# every layout added, renamed or deleted afterwards left it describing a list
# that no longer existed — and because the layouts still applied correctly from
# the surface, the menu was the only place it showed.

CONFIG="$HOME/Library/Application Support/WindowThing/config.yaml"

# Opens the menu, reads the item names, and closes it again.
menu_items() {
    osascript <<'OSA' 2>/dev/null
tell application "System Events"
  tell process "WindowThing"
    click menu bar item 1 of menu bar 2
    delay 1
    set out to ""
    repeat with mi in menu items of menu 1 of menu bar item 1 of menu bar 2
      set nm to name of mi
      if nm is not missing value then set out to out & nm & "|"
    end repeat
    key code 53
    return out
  end tell
end tell
OSA
}

# The shortcut drawn against a named item, as "char/modifiers".
menu_shortcut_of() {
    osascript 2>/dev/null <<OSA
tell application "System Events"
  tell process "WindowThing"
    click menu bar item 1 of menu bar 2
    delay 1
    set answer to "none"
    repeat with mi in menu items of menu 1 of menu bar item 1 of menu bar 2
      if name of mi is "$1" then
        set c to ""
        try
          set c to value of attribute "AXMenuItemCmdChar" of mi
        end try
        set m to ""
        try
          set m to (value of attribute "AXMenuItemCmdModifiers" of mi) as text
        end try
        set answer to c & "/" & m
      end if
    end repeat
    key code 53
    return answer
  end tell
end tell
OSA
}

expect_menu_has() {
    local items
    items="$(menu_items)"
    case "$items" in
        *"$1|"*) pass "$2" ;;
        *)       fail "$2 (menu was: ${items:-empty})" ;;
    esac
}

expect_menu_lacks() {
    local items
    items="$(menu_items)"
    case "$items" in
        *"$1|"*) fail "$2 (menu was: ${items:-empty})" ;;
        *)       pass "$2" ;;
    esac
}

info "Menubar: it lists the configured layouts"
# Start from the app's own defaults, by deleting the file and letting it write
# one. The menu truncates past a cap, so against a config already at that many
# an added layout has nowhere to appear and the assertions below would pass
# without testing anything. The defaults are four, leaving room for the two this
# test adds.
#
# Written by the app rather than by hand here: AppConfig has six non-optional
# fields beyond the layouts, and a config missing any of them fails to decode —
# whereupon the app falls back to these same defaults silently, so a hand-written
# config that has drifted looks like it worked.
#
# ui-test.sh restores the real config when the suite finishes.
rm -f "$CONFIG"

launch_with_surface || return 0

# Closed first: the surface sits above everything at the screen-saver level, and
# a click meant for the menu bar would land on it instead.
$AX press "Close layout surface" >/dev/null 2>&1
$AX gone "New layout" 8 >/dev/null 2>&1

expect_menu_has "Fullscreen"       "a configured layout is listed"
expect_menu_has "Half Split"       "so is the second"
expect_menu_has "Layout Editor"    "the menu offers the layout surface"
expect_menu_has "Quit WindowThing" "the menu is fully populated"

info "Menubar: Layout Editor carries the activation shortcut"
# The shortcut is read from the configured hotkey rather than written into the
# title, so the two cannot drift apart. Asserted against config.yaml for that
# reason — hard-coding ⌃⌥W here would pass even if the item stopped following
# the config.
config_key_code="$(awk '/^activationHotKey:/{f=1;next} f&&/keyCode:/{print $2;exit}' "$CONFIG" 2>/dev/null)"
shortcut="$(menu_shortcut_of "Layout Editor")"
note "activationHotKey keyCode=${config_key_code:-?}, menu shows ${shortcut}"

if [ "${shortcut%%/*}" != "none" ] && [ -n "${shortcut%%/*}" ]; then
    pass "Layout Editor has a keyboard shortcut against it"
else
    fail "Layout Editor has no shortcut (was '$shortcut')"
fi

# keyCode 13 is W, the default. Only checked when the config actually says so,
# so a VM configured differently reports rather than fails.
if [ "$config_key_code" = "13" ]; then
    expect_equal "${shortcut%%/*}" "W" "the shortcut is the configured key"
    # 8 = "no command", 4 = control, 2 = option → ⌃⌥, matching the config.
    expect_equal "${shortcut##*/}" "14" "the shortcut carries the configured modifiers"
else
    note "activation hotkey is not the default; skipping the exact-key check"
fi

info "Menubar: it follows a layout being added and deleted"
# The point of the whole file. Done in one process, without relaunching, since a
# restart rebuilds the menu from the file and would hide the fault.
reopen_surface_in_process || return 0

SCRATCH="Menu Scratch"
$AX press "New layout" >/dev/null 2>&1
$AX wait "Layout name" 10 >/dev/null 2>&1
drive type "Layout name" "$SCRATCH" || return 0
drive confirm || return 0
$AX wait "Delete layout $SCRATCH" 10 >/dev/null 2>&1

$AX press "Close layout surface" >/dev/null 2>&1
$AX gone "New layout" 8 >/dev/null 2>&1

expect_menu_has "$SCRATCH" "a layout added from the surface reaches the menu"

info "Menubar: it lists more than five layouts"
# Four defaults plus these two makes six. The menu used to stop at five, so a
# sixth layout could never appear however the list changed — which reads as the
# menu refusing to update rather than as a cap, and is exactly how it was
# reported.
reopen_surface_in_process || return 0

SIXTH="Menu Sixth"
$AX press "New layout" >/dev/null 2>&1
$AX wait "Layout name" 10 >/dev/null 2>&1
drive type "Layout name" "$SIXTH" || return 0
drive confirm || return 0
$AX wait "Delete layout $SIXTH" 10 >/dev/null 2>&1

$AX press "Close layout surface" >/dev/null 2>&1
$AX gone "New layout" 8 >/dev/null 2>&1

expect_menu_has "$SCRATCH" "the fifth layout is still listed"
expect_menu_has "$SIXTH"   "and so is the sixth, past the old five-item cap"

info "Menubar: and a deletion"
# Only means anything because the assertion above established the layout was in
# the menu to begin with. On its own it passes against a menu that never listed
# the layout at all — which is exactly what a stale menu looks like.
reopen_surface_in_process || return 0
teardown_scratch_layout "$SIXTH"
teardown_scratch_layout "$SCRATCH"
$AX press "Close layout surface" >/dev/null 2>&1
$AX gone "New layout" 8 >/dev/null 2>&1

expect_menu_lacks "$SCRATCH" "deleting the layout takes it out of the menu"
