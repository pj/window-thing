#!/bin/bash
# Grant Accessibility TCC permissions to the Swift test runner.
#
# Must be run inside the VM after building the project (so the test binary exists).
# Requires SIP to be disabled — cirruslabs base images ship with SIP off.
#
# Usage:
#   grant-tcc-access.sh <project-dir>
#
# The script grants access to four clients:
#   1. /usr/bin/swift          — covers `swift test` invocations from shell
#   2. The compiled XCTest bundle — covers direct test binary execution
#   3. Terminal.app            — covers interactive SSH sessions
#   4. build/ax-driver         — the compiled interface driver
#
# auth_value 2 = allowed, auth_reason 4 = user-set, client_type 1 = absolute path,
# client_type 0 = bundle ID.

set -euo pipefail

PROJECT_DIR="${1:-$HOME/Projects/window_thing}"
TCC_DB_USER="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
TCC_DB_SYSTEM="/Library/Application Support/com.apple.TCC/TCC.db"
SERVICE="kTCCServiceAccessibility"
TIMESTAMP=$(date +%s)

# --------------------------------------------------------------------------- #
# Helpers                                                                       #
# --------------------------------------------------------------------------- #

tcc_insert() {
    local db="$1"
    local client="$2"
    local client_type="$3"   # 0=bundleID 1=path

    sqlite3 "$db" \
        "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
         VALUES('$SERVICE','$client',$client_type,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" \
        2>/dev/null && echo "  [ok] $client" || echo "  [skip] $client (may need --sudo)"
}

echo "=== Granting Accessibility TCC permissions ==="

# User-level TCC (no sudo needed)
mkdir -p "$(dirname "$TCC_DB_USER")"
if [ -f "$TCC_DB_USER" ]; then
    echo "User TCC.db:"
    tcc_insert "$TCC_DB_USER" "/usr/bin/swift"               1
    tcc_insert "$TCC_DB_USER" "com.apple.Terminal"           0
    tcc_insert "$TCC_DB_USER" "com.googlecode.iterm2"        0

    # Automation: sending Apple events, which the interface tests use for the
    # model-level verbs and for driving the menubar through System Events. A
    # different service from Accessibility, and keyed on the pair — sender *and*
    # target — hence the extra columns.
    #
    # Granted for two senders, because TCC blames the *responsible* process
    # rather than the one that literally sends the event. Over SSH that is
    # sshd-keygen-wrapper, so granting only osascript leaves the real client
    # denied — and the failure is silent: osascript returns -1743 and the test
    # quietly takes whatever fallback it has, appearing to pass.
    echo "Automation (Apple events):"
    for TARGET in com.windowthing.app com.apple.systemevents com.apple.TextEdit; do
        for SENDER in /usr/bin/osascript /usr/libexec/sshd-keygen-wrapper; do
            sqlite3 "$TCC_DB_USER" \
                "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
                 VALUES('kTCCServiceAppleEvents','$SENDER',1,2,4,1,NULL,NULL,0,'$TARGET',NULL,0,$TIMESTAMP);" \
                2>/dev/null && echo "  [ok] $SENDER -> $TARGET" \
                            || echo "  [skip] $SENDER -> $TARGET"
        done
    done
else
    echo "  [warn] User TCC.db not found — skipping user-level grants"
fi

# System-level TCC — Accessibility lives here, and only here.
#
# Writable only with SIP off. With SIP on the file is read-only even to root,
# and the failure is worth reporting loudly rather than skipping past: every
# interface assertion depends on this, so a silent skip turns one missing
# permission into a wall of unrelated-looking failures ("the surface did not
# open within 25s") that reads like the app is broken.
echo "System TCC.db (Accessibility):"
if sudo sqlite3 "$TCC_DB_SYSTEM" \
        "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
         VALUES('$SERVICE','/usr/bin/swift',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" 2>/dev/null; then
    echo "  [ok] /usr/bin/swift (system)"
    SYSTEM_TCC_WRITABLE=true
else
    SYSTEM_TCC_WRITABLE=false
    echo "  [read-only] SIP is on, so Accessibility cannot be granted from a script."
fi

# Pre-grant expected test binary paths.
# TCC matches by path string; the binary does not need to exist yet.
# swift test (not swift build --build-tests) compiles these, so we grant
# before the test run rather than after a separate build step.
echo "Pre-granting expected test binary paths:"
for TARGET in WindowThingTests WindowThingViewModelTests WindowThingCanvasTests; do
    EXPECTED_BIN="$PROJECT_DIR/.build/debug/${TARGET}.xctest/Contents/MacOS/${TARGET}"
    if [ -f "$TCC_DB_USER" ]; then
        tcc_insert "$TCC_DB_USER" "$EXPECTED_BIN" 1
    fi
    sudo sqlite3 "$TCC_DB_SYSTEM" \
        "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
         VALUES('$SERVICE','$EXPECTED_BIN',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" \
        2>/dev/null && echo "  [ok] $EXPECTED_BIN" || true
done

# The interface driver, compiled rather than run through `swift` so each of the
# suite's hundred-plus calls costs 0.03s instead of 0.6s. It is a separate client
# from /usr/bin/swift and needs its own grant; ui-lib.sh builds it at this exact
# path so the grant can be written before it exists.
echo "Interface driver:"
AX_DRIVER="$PROJECT_DIR/build/ax-driver"
if [ -f "$TCC_DB_USER" ]; then
    tcc_insert "$TCC_DB_USER" "$AX_DRIVER" 1
fi
sudo sqlite3 "$TCC_DB_SYSTEM" \
    "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
     VALUES('$SERVICE','$AX_DRIVER',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" \
    2>/dev/null && echo "  [ok] $AX_DRIVER (system)" || true

# Also grant any already-compiled bundles (covers re-runs)
while IFS= read -r -d '' TEST_BUNDLE; do
    TEST_BIN="$TEST_BUNDLE/Contents/MacOS/$(basename "$TEST_BUNDLE" .xctest)"
    if [ -f "$TEST_BIN" ]; then
        echo "Already-compiled bundle:"
        [ -f "$TCC_DB_USER" ] && tcc_insert "$TCC_DB_USER" "$TEST_BIN" 1
        sudo sqlite3 "$TCC_DB_SYSTEM" \
            "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
             VALUES('$SERVICE','$TEST_BIN',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" \
            2>/dev/null && echo "  [ok] $TEST_BIN" || true
    fi
done < <(find "$PROJECT_DIR/.build" -name "*.xctest" -path "*/debug/*" -print0 2>/dev/null)

# What is actually granted, and what to do when it isn't.
#
# The check is on the app rather than the driver because System Settings will
# only list a bundle; whoever approves the app will be in the right pane to
# approve the driver alongside it.
if [ "$SYSTEM_TCC_WRITABLE" != "true" ]; then
    APP_STATE=$(sudo sqlite3 "$TCC_DB_SYSTEM" \
        "select auth_value from access where service='$SERVICE' and client='com.windowthing.app';" 2>/dev/null)
    DRIVER_STATE=$(sudo sqlite3 "$TCC_DB_SYSTEM" \
        "select auth_value from access where service='$SERVICE' and client like '%ax-driver%';" 2>/dev/null)

    if [ "$APP_STATE" = "2" ] && [ "$DRIVER_STATE" = "2" ]; then
        echo "Accessibility: already approved for the app and the driver."
    else
        echo ""
        echo "  Accessibility is not approved in this VM, and with SIP on it cannot"
        echo "  be granted from here. Approve it once, in the VM's own screen:"
        echo ""
        echo "    System Settings > Privacy & Security > Accessibility"
        echo "      WindowThing        (currently: ${APP_STATE:-not listed})"
        echo "      ax-driver          (currently: ${DRIVER_STATE:-not listed})"
        echo ""
        echo "  auth_value 0 means listed but refused — switch it on rather than"
        echo "  adding it again. Add missing entries with '+' from:"
        echo "    $PROJECT_DIR/build/WindowThing.app"
        echo "    $PROJECT_DIR/build/ax-driver"
        echo ""
        echo "  It only needs doing once: both are signed with a Developer ID, so"
        echo "  the approval carries across rebuilds."
        echo ""
    fi
fi

echo "=== TCC grant complete ==="
