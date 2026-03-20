#!/bin/bash
set -euo pipefail

echo "=== WindowThing VM Setup ==="

# Ensure Homebrew is in PATH
eval "$(/opt/homebrew/bin/brew shellenv)"

# Verify Xcode Command Line Tools
echo "Checking Xcode Command Line Tools..."
if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install || true
    # Wait for installation (this may require user interaction)
    sleep 5
fi

# Accept Xcode license
echo "Accepting Xcode license..."
sudo xcodebuild -license accept 2>/dev/null || true

# Verify Swift is available
echo "Checking Swift..."
swift --version

# Create test windows script for integration tests
echo "Creating test helper scripts..."
mkdir -p ~/Projects/windowthing-helpers

cat > ~/Projects/windowthing-helpers/create-test-windows.swift << 'SWIFT'
#!/usr/bin/env swift
import Cocoa

// Create simple test windows for integration testing
class TestWindowApp: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create 3 test windows
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

        // Keep running for testing
        // Exit after 60 seconds if not terminated
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = TestWindowApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
SWIFT

chmod +x ~/Projects/windowthing-helpers/create-test-windows.swift

# Create script to set up virtual displays using BetterDisplay CLI
cat > ~/Projects/windowthing-helpers/setup-virtual-displays.sh << 'BASH'
#!/bin/bash
# Set up virtual displays for multi-monitor testing
# Requires BetterDisplay to be installed and running

# Check if BetterDisplay CLI is available
if ! command -v betterdisplaycli &> /dev/null; then
    echo "BetterDisplay CLI not found. Install BetterDisplay first."
    exit 1
fi

# Create a second virtual display (1920x1080)
echo "Creating virtual display..."
betterdisplaycli create \
    -devicetype=virtualscreen \
    -virtualscreenname="Virtual Monitor 2" \
    -aspectWidth=16 \
    -aspectHeight=9 \
    -maxWidth=1920 \
    -maxHeight=1080 || true

echo "Virtual display created. Check System Settings > Displays."
BASH

chmod +x ~/Projects/windowthing-helpers/setup-virtual-displays.sh

echo "=== Setup Complete ==="
echo ""
echo "Next steps after VM is built:"
echo "1. Grant Accessibility permissions to Terminal"
echo "2. Grant Accessibility permissions to WindowThing"
echo "3. Run BetterDisplay and configure virtual displays if needed"
echo ""
echo "To run tests, clone WindowThing repo to ~/Projects/window_thing"
