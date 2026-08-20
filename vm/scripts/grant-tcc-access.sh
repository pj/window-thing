#!/bin/bash
# Grant Accessibility TCC permissions to the Swift test runner.
#
# Must be run inside the VM after building the project (so the test binary exists).
# Requires SIP to be disabled — cirruslabs base images ship with SIP off.
#
# Usage:
#   grant-tcc-access.sh <project-dir>
#
# The script grants access to three clients:
#   1. /usr/bin/swift          — covers `swift test` invocations from shell
#   2. The compiled XCTest bundle — covers direct test binary execution
#   3. Terminal.app            — covers interactive SSH sessions
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

    # Automation: sending Apple events to WindowThing, which the interface tests
    # use for the model-level verbs. A different service from Accessibility, and
    # it is keyed on the pair — sender *and* target — hence the extra columns.
    sqlite3 "$TCC_DB_USER" \
        "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
         VALUES('kTCCServiceAppleEvents','/usr/bin/osascript',1,2,4,1,NULL,NULL,0,'com.windowthing.app',NULL,0,$TIMESTAMP);" \
        2>/dev/null && echo "  [ok] osascript -> com.windowthing.app (automation)" \
                    || echo "  [skip] automation grant (rename test will be skipped)"
else
    echo "  [warn] User TCC.db not found — skipping user-level grants"
fi

# System-level TCC (needs sudo — fails gracefully if not available)
echo "System TCC.db (requires sudo):"
if [ -w "$TCC_DB_SYSTEM" ] || sudo -n true 2>/dev/null; then
    sudo sqlite3 "$TCC_DB_SYSTEM" \
        "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
         VALUES('$SERVICE','/usr/bin/swift',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" \
        2>/dev/null && echo "  [ok] /usr/bin/swift (system)" || echo "  [skip] could not write system TCC.db"
else
    echo "  [skip] sudo not available without password"
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

echo "=== TCC grant complete ==="
