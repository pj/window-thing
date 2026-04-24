#!/bin/bash
set -euo pipefail

echo "=== WindowThing VM Setup ==="

# Ensure Homebrew is in PATH
eval "$(/opt/homebrew/bin/brew shellenv)"

# --------------------------------------------------------------------------- #
# Xcode toolchain                                                               #
# Full Xcode is pre-installed in the macos-sequoia-xcode base image.           #
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
echo "Creating test helper scripts..."
mkdir -p ~/Projects/windowthing-helpers

# create-test-windows.swift — spawns 3 real AppKit windows for integration tests
cat > ~/Projects/windowthing-helpers/create-test-windows.swift << 'SWIFT'
#!/usr/bin/env swift
import Cocoa

class TestWindowApp: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        for i in 1...3 {
            let window = NSWindow(
                contentRect: NSRect(x: 100 + i * 50, y: 100 + i * 50, width: 400, height: 300),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Test Window \(i)"
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        print("Created \(windows.count) test windows")
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = TestWindowApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
SWIFT
chmod +x ~/Projects/windowthing-helpers/create-test-windows.swift

# --------------------------------------------------------------------------- #
# Working directory for WindowThing source                                      #
# --------------------------------------------------------------------------- #
mkdir -p ~/Projects/window_thing

echo ""
echo "=== Setup Complete ==="
echo "Accessibility TCC pre-granted for /usr/bin/swift and Terminal."
echo "The compiled test bundle will be granted at run-test time by run-tests.sh."
echo "Drop the WindowThing source into ~/Projects/window_thing and run:"
echo "  cd ~/Projects/window_thing && swift test"
