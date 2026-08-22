#!/usr/bin/env bash
# The first-run flow.
#
# Only appears when the app has never completed onboarding, so this test clears
# that flag rather than depending on the VM's history.

info "Onboarding: it appears on a first run"
quit_app
defaults delete com.windowthing.app hasCompletedOnboarding >/dev/null 2>&1 || true
launch_plain

expect_control "Welcome to WindowThing" "a first run opens the welcome step"
expect_control "Get Started"            "the first step offers a way forward"

# The SF Symbol beside the title used to be announced by name — VoiceOver read
# the first step as "rectangle.3.group".
if $AX exists "rectangle.3.group" >/dev/null 2>&1; then
    fail "the decorative icon is still announced by its symbol name"
else
    pass "the decorative icon is not announced by its symbol name"
fi

info "Onboarding: stepping through it"
$AX press "Get Started" >/dev/null 2>&1
expect_control "Accessibility Access" "the second step covers the required permission"

info "Onboarding: tidying up"
quit_app
defaults write com.windowthing.app hasCompletedOnboarding -bool true >/dev/null 2>&1 || true
