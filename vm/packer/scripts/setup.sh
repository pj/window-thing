#!/bin/bash
set -euo pipefail

echo "=== WindowThing VM Setup ==="

# Ensure Homebrew is in PATH
eval "$(/opt/homebrew/bin/brew shellenv)"

# --------------------------------------------------------------------------- #
# Xcode toolchain                                                               #
# Full Xcode is pre-installed in the macos-tahoe-xcode base image.              #
# --------------------------------------------------------------------------- #
echo "Verifying Xcode toolchain..."
sudo xcodebuild -license accept 2>/dev/null || true
xcodebuild -version
swift --version

# --------------------------------------------------------------------------- #
# Accessibility TCC permissions                                                 #
#                                                                               #
# Cirruslabs base images ship with SIP disabled, so we can write to TCC.db    #
# directly.  We grant access to /usr/bin/swift (covers `swift test`) and to   #
# Terminal.app (covers interactive SSH sessions).  The compiled test bundle    #
# path isn't known at image-build time; run-tests.sh handles it at runtime.   #
# --------------------------------------------------------------------------- #
echo "Pre-granting Accessibility TCC permissions..."

TCC_DB_USER="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
TCC_DB_SYSTEM="/Library/Application Support/com.apple.TCC/TCC.db"
TIMESTAMP=$(date +%s)

tcc_insert() {
    local db="$1" client="$2" client_type="$3"
    sqlite3 "$db" \
        "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
         VALUES('kTCCServiceAccessibility','$client',$client_type,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" \
        2>/dev/null && echo "  granted: $client" || echo "  skipped: $client"
}

# User-level TCC
mkdir -p "$(dirname "$TCC_DB_USER")"
if [ -f "$TCC_DB_USER" ]; then
    tcc_insert "$TCC_DB_USER" "/usr/bin/swift"           1
    tcc_insert "$TCC_DB_USER" "com.apple.Terminal"       0
    tcc_insert "$TCC_DB_USER" "com.googlecode.iterm2"    0
fi

# System-level TCC
if [ -f "$TCC_DB_SYSTEM" ]; then
    sudo sqlite3 "$TCC_DB_SYSTEM" \
        "INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) \
         VALUES('kTCCServiceAccessibility','/usr/bin/swift',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$TIMESTAMP);" \
        2>/dev/null && echo "  granted: /usr/bin/swift (system)" || echo "  skipped system TCC"
fi

# --------------------------------------------------------------------------- #
# Power / sleep management                                                      #
# --------------------------------------------------------------------------- #
echo "Disabling sleep and screen saver..."
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
defaults write com.apple.screensaver idleTime 0 2>/dev/null || true

# Disable Spotlight (speeds up builds)
sudo mdutil -a -i off 2>/dev/null || true

# --------------------------------------------------------------------------- #
# Test helper scripts                                                           #
# --------------------------------------------------------------------------- #
# --------------------------------------------------------------------------- #
# Working directory for WindowThing source                                      #
# --------------------------------------------------------------------------- #
mkdir -p ~/Projects

echo ""
echo "=== Setup Complete ==="
echo "Accessibility TCC pre-granted for /usr/bin/swift and Terminal."
echo "The compiled test bundle will be granted at run-test time by run-tests.sh."
echo "Projects sync into ~/Projects/<name>; from one of those run:"
echo "  swift test"
