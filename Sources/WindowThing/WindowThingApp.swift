import SwiftUI
import HotKey
import os.log
import WindowThingCore

let logger = Logger(subsystem: "com.windowthing", category: "main")

func debugLog(_ message: String) {
    logger.info("\(message)")
    // Also write to file for easy access
    let logFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("WindowThing/debug.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

@main
struct WindowThingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var overlayWindow: OverlayWindow?
    var hotKey: HotKey?
    var reloadConfigHotKey: HotKey?
    var openConfigHotKey: HotKey?

    let windowManager = WindowManager.shared
    let configManager = ConfigManager.shared
    let layoutManager = LayoutManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("App launched")

        // Hide dock icon - we're a menubar app
        NSApp.setActivationPolicy(.accessory)

        // Load configuration first so layouts are available for the menu
        loadConfiguration()

        setupStatusItem()

        // Request accessibility permissions
        requestAccessibilityPermissions()

        // Setup monitoring for automatic layout reconciliation
        setupMonitoring()

        debugLog(" Setup complete")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage.menuBarIcon()
            button.image?.accessibilityDescription = "WindowThing"
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusMenu()
    }

    private func updateStatusMenu() {
        let menu = NSMenu()

        // Get current displays for generating layout icons
        let displays = windowManager.getDisplays()

        // Layouts at top level (limited to 5)
        let layoutsToShow = Array(layoutManager.layouts.prefix(5))

        if layoutsToShow.isEmpty {
            let noLayoutsItem = NSMenuItem(title: "No layouts configured", action: nil, keyEquivalent: "")
            noLayoutsItem.isEnabled = false
            menu.addItem(noLayoutsItem)
        } else {
            for layout in layoutsToShow {
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(applyLayout(_:)),
                    keyEquivalent: layout.quickKey ?? ""
                )
                item.representedObject = layout
                item.target = self
                item.image = NSImage.layoutIcon(for: layout, displays: displays)
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Show overlay
        let showOverlayItem = NSMenuItem(title: "Show Overlay", action: #selector(showOverlayFromMenu), keyEquivalent: "")
        showOverlayItem.target = self
        menu.addItem(showOverlayItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit WindowThing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            // Show menu on right click
            statusItem?.menu = nil
            updateStatusMenu()
            statusItem?.button?.performClick(nil)
        } else {
            // Toggle overlay on left click
            toggleOverlay()
        }
    }

    @objc private func showOverlayFromMenu() {
        showOverlay()
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? WTLayout else { return }
        layoutManager.applyLayout(layout)
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func openConfigFile() {
        let configPath = configManager.configFilePath
        NSWorkspace.shared.open(configPath)
    }

    private func reloadConfig() {
        loadConfiguration()
        updateStatusMenu()
        debugLog("Configuration reloaded")
    }

    private func setupHotKey() {
        let config = configManager.config.activationHotKey
        debugLog(" Setting up hotkey: keyCode=\(config.keyCode), modifiers=\(config.modifiers)")

        // Convert our key code to Key (from HotKey module)
        guard let key = Key(carbonKeyCode: config.keyCode) else {
            debugLog(" ERROR: Invalid hotkey key code: \(config.keyCode)")
            return
        }
        debugLog(" Key resolved: \(key)")

        // Convert modifiers
        var modifiers: NSEvent.ModifierFlags = []
        for mod in config.modifiers {
            switch mod.lowercased() {
            case "command", "cmd":
                modifiers.insert(.command)
            case "option", "opt", "alt":
                modifiers.insert(.option)
            case "control", "ctrl":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            default:
                debugLog(" Unknown modifier: \(mod)")
            }
        }
        debugLog(" Modifiers: \(modifiers)")

        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            debugLog(" Hotkey pressed!")
            self?.toggleOverlay()
        }
        debugLog(" Hotkey registered: \(String(describing: hotKey))")

        // Reload config hotkey: Ctrl+Option+R
        reloadConfigHotKey = HotKey(key: .r, modifiers: [.control, .option])
        reloadConfigHotKey?.keyDownHandler = { [weak self] in
            debugLog(" Reload config hotkey pressed!")
            self?.reloadConfig()
        }

        // Open config hotkey: Ctrl+Option+,
        openConfigHotKey = HotKey(key: .comma, modifiers: [.control, .option])
        openConfigHotKey?.keyDownHandler = { [weak self] in
            debugLog(" Open config hotkey pressed!")
            self?.openConfigFile()
        }
    }

    private func loadConfiguration() {
        configManager.loadConfig()
        layoutManager.loadLayouts(from: configManager.config)
        layoutManager.loadSavedSetups()

        // Re-setup hotkey with new config
        setupHotKey()
    }

    private func setupMonitoring() {
        debugLog(" Setting up monitoring")

        // Set up callback for automatic layout reconciliation
        windowManager.onCacheRefresh = { [weak self] in
            self?.layoutManager.reconcileCurrentLayout()
        }

        // Start monitoring display changes (disconnects/reconnects)
        windowManager.startMonitoringDisplayChanges()

        // Start monitoring workspace (app launch/quit)
        windowManager.startMonitoringWorkspace()

        // Start polling for window changes
        windowManager.startPolling()

        debugLog(" Monitoring started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up monitoring
        windowManager.stopPolling()
        windowManager.stopMonitoringDisplayChanges()
        windowManager.stopMonitoringWorkspace()
    }

    func toggleOverlay() {
        debugLog(" toggleOverlay called")
        if let window = overlayWindow, window.isVisible {
            debugLog(" Hiding overlay")
            hideOverlay()
        } else {
            debugLog(" Showing overlay")
            showOverlay()
        }
    }

    func showOverlay() {
        if overlayWindow == nil {
            overlayWindow = OverlayWindow()
        }

        overlayWindow?.showOverlay()
    }

    func hideOverlay() {
        overlayWindow?.hideOverlay()
    }

    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            debugLog("Accessibility permissions required. Please grant access in System Preferences > Privacy & Security > Accessibility")
        }
    }
}
