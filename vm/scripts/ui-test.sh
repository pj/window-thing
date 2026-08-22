#!/usr/bin/env bash
# ui-test.sh — run the interface tests.
#
# Runs *inside* the VM, in the logged-in GUI session. That is the whole point:
# these tests open windows, take focus and click things, so running them on a
# developer's own machine means taking over their screen.
#
# Usage (inside the VM):
#   ~/Projects/window_thing/vm/scripts/ui-test.sh            # everything
#   ~/Projects/window_thing/vm/scripts/ui-test.sh 02-layouts # one file
#
# What belongs here: behaviour that only exists in the interface — focus,
# keyboard interception, dialogs, what a control is called. Layout arithmetic,
# window matching and the view model are covered far more cheaply and thoroughly
# by `swift test`, and duplicating that here would only make this slower.

set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/Projects/window_thing}"
source "$PROJECT_DIR/vm/scripts/ui-lib.sh"

info "Building the app bundle"
if ! "$PROJECT_DIR/scripts/package.sh" --no-sign >/tmp/ui-test-build.log 2>&1; then
    echo "build failed; see /tmp/ui-test-build.log"
    tail -20 /tmp/ui-test-build.log
    exit 1
fi

info "Building the driver"
build_driver || exit 1

isolate_config
trap 'quit_app; restore_config' EXIT

only="${1:-}"
failed_files=()

for file in "$PROJECT_DIR"/vm/scripts/ui-tests/*.sh; do
    name="$(basename "$file" .sh)"
    if [ -n "$only" ] && [[ "$name" != *"$only"* ]]; then continue; fi

    echo
    echo "───────────────────────────────────────────── $name"

    # Sourced rather than executed so the shared counters survive; each file
    # starts from a known state of its own.
    before_failures=$FAIL_COUNT
    # shellcheck disable=SC1090
    source "$file" || fail "$name exited unexpectedly"
    if [ "$FAIL_COUNT" -gt "$before_failures" ]; then failed_files+=("$name"); fi
done

echo
echo "───────────────────────────────────────────────────────"
echo "passed: $PASS_COUNT   failed: $FAIL_COUNT"
if [ ${#failed_files[@]} -gt 0 ]; then
    echo "failing files: ${failed_files[*]}"
fi
[ "$FAIL_COUNT" -eq 0 ] || exit 1
