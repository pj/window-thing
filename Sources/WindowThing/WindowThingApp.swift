import SwiftUI
import HotKey
import os.log
import Sparkle
import WindowThingCore
import WindowThingViewModel

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

    /// The live delegate.
    ///
    /// `NSApp.delegate` is not this object: SwiftUI's
    /// `@NSApplicationDelegateAdaptor` installs a proxy of its own that forwards
    /// to us, so casting `NSApp.delegate` to `AppDelegate` fails. Scripting
    /// commands need a way in, and this is it.
    private(set) static var shared: AppDelegate?

    var statusItem: NSStatusItem?
    var popover: NSPopover?
    let spaceOverlay = SpaceOverlayController()
    var quickMoveWindow: QuickMoveWindow?
    var onboardingWindow: OnboardingWindow?
    /// Retained so Preferences reopens the same window; see showSettings().
    var settingsWindow: NSWindow?
    var hotKey: HotKey?
    var reloadConfigHotKey: HotKey?
    var openConfigHotKey: HotKey?
    var cellPickerHotKey: HotKey?
    /// Retained cell hotkeys — releasing deallocates the Carbon shortcut.
    var cellHotKeys: [String: HotKey] = [:]

    let windowManager = WindowManager.shared
    let configManager = ConfigManager.shared
    let layoutManager = LayoutManager.shared

    /// Resolved so a symlinked or aliased copy (nix-darwin puts one in
    /// /Applications, home-manager in ~/Applications) reports where it really
    /// lives rather than where it is linked from.
    let updateChannel = UpdateChannelResolver.channel(
        forBundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path
    )

    /// Started only when the install is one Sparkle can actually replace; see
    /// UpdateChannel. `startingUpdater: true` kicks off the scheduled background
    /// checks as well as providing the menu action.
    private lazy var updaterController: SPUStandardUpdaterController? = {
        guard updateChannel.supportsInAppUpdates else { return nil }
        return SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        debugLog("App launched")

        // Hide dock icon - we're a menubar app
        NSApp.setActivationPolicy(.accessory)

        // Load configuration first so layouts are available for the menu
        loadConfiguration()

        setupStatusItem()

        MainThreadStallDetector.shared.start()
        MainThreadWatchdog.shared.start()

        // Proves the instruments actually fire, so a quiet log can be trusted
        // as "nothing stalled" rather than "nothing was watching".
        if CommandLine.arguments.contains("--selftest-stall") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                RenderProbe.breadcrumb("selftest")
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        // Request accessibility permissions
        requestAccessibilityPermissions()

        // Show first-run onboarding if not yet completed.
        // Under --screenshot the requested scene decides what appears, so the
        // first-run window can't end up covering it.
        if screenshotScene == nil, !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }

        // Setup monitoring for automatic layout reconciliation
        setupMonitoring()

        presentScreenshotScene()

        debugLog(" Setup complete")
    }

    /// The scene named by `--screenshot <overlay|quickmove|settings|onboarding>`,
    /// or nil for a normal launch.
    private var screenshotScene: String? {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "--screenshot"),
              flagIndex + 1 < args.count else { return nil }
        return args[flagIndex + 1]
    }

    /// Opens the named UI scene straight after launch so screenshots can be
    /// driven non-interactively (see `vm/capture-screenshots.sh`).
    private func presentScreenshotScene() {
        guard let scene = screenshotScene else { return }

        // Give the status item and window list a beat to settle before presenting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            // showSettingsWindow: is a no-op unless the app is already active.
            NSApp.activate(ignoringOtherApps: true)
            switch scene {
            // "overlay" is kept as an alias so existing capture scripts and
            // saved shots keep lining up after the editor was folded in here.
            case "space", "overlay":
                // Nothing holds key focus in an automated session, and the
                // overlay hides itself on resignKey — pin it open instead.
                self.spaceOverlay.staysVisibleWhenInactive = true
                self.toggleSpaceOverlay()
            case "quickmove":   self.toggleQuickMove()
            case "onboarding":  self.showOnboarding()
            case "settings":    self.showSettings()
            default:            debugLog("Unknown screenshot scene: \(scene)")
            }
            NSApp.activate(ignoringOtherApps: true)

            // Layout reconciliation can push our own window behind the windows
            // it just arranged; float it back to the front for the capture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                for window in NSApp.windows where window.isVisible {
                    // Never demote a window that deliberately sits higher
                    // (the space overlay is at .screenSaver).
                    window.level = max(window.level, .floating)
                    window.orderFrontRegardless()
                }
            }
        }
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

        let spaceItem = NSMenuItem(title: "Show Layout", action: #selector(showSpaceFromMenu), keyEquivalent: "")
        spaceItem.target = self
        menu.addItem(spaceItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        // Updates. Where Sparkle can't replace the bundle (a nix install, or a
        // bare development binary) the item says who owns updates instead of
        // offering a check that could only fail.
        if let updaterController {
            let updateItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            updateItem.target = updaterController
            menu.addItem(updateItem)
        } else if let reason = updateChannel.unavailableReason {
            let updateItem = NSMenuItem(title: reason, action: nil, keyEquivalent: "")
            updateItem.isEnabled = false
            menu.addItem(updateItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit WindowThing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            statusItem?.menu = nil
            updateStatusMenu()
            statusItem?.button?.performClick(nil)
        } else {
            // Left click → the activation surface
            toggleSpaceOverlay()
        }
    }

    @objc private func showSpaceFromMenu() {
        toggleSpaceOverlay()
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let layout = sender.representedObject as? WTLayout else { return }
        layoutManager.applyLayout(layout)
    }

    @objc private func openPreferences() {
        showSettings()
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
            self?.toggleSpaceOverlay()
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

        // Re-setup hotkeys with new config
        setupHotKey()
        setupCellHotKeys()
    }

    // MARK: - Cell Hotkeys

    private func setupCellHotKeys() {
        // Release previous registrations
        cellHotKeys = [:]
        cellPickerHotKey = nil

        let config = configManager.config

        // Register per-cell hotkeys
        if let cellHotKeyConfigs = config.cellHotKeys {
            for (addressString, hotKeyConfig) in cellHotKeyConfigs {
                guard let address = CellAddress(string: addressString),
                      let key = Key(carbonKeyCode: hotKeyConfig.keyCode) else { continue }
                let modifiers = modifierFlags(from: hotKeyConfig.modifiers)
                let hk = HotKey(key: key, modifiers: modifiers)
                hk.keyDownHandler = { [weak self] in
                    self?.moveFocusedWindowToCell(address)
                }
                cellHotKeys[addressString] = hk
            }
        }

        // Register cell-picker hotkey
        if let pickerConfig = config.cellPickerHotKey,
           let key = Key(carbonKeyCode: pickerConfig.keyCode) {
            let modifiers = modifierFlags(from: pickerConfig.modifiers)
            cellPickerHotKey = HotKey(key: key, modifiers: modifiers)
            cellPickerHotKey?.keyDownHandler = { [weak self] in
                self?.showCellPicker()
            }
        }
    }

    private func moveFocusedWindowToCell(_ address: CellAddress) {
        guard let focusedApp = windowManager.getFocusedApplication() else { return }
        let displays = windowManager.getDisplays()
        let windows = windowManager.getWindows()
        // Find the frontmost window of the focused app
        let window = focusedApp.focusedWindow
            ?? windows.first { $0.pid == focusedApp.id || $0.bundleId == focusedApp.bundleId }
        guard let window else { return }
        try? layoutManager.moveWindow(window, toCellAt: address, displays: displays)
    }

    private func showCellPicker() {
        // The picker lives inside the activation surface, so raise that first.
        spaceOverlay.showCellPickerForFocusedWindow()
    }

    private func modifierFlags(from strings: [String]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for mod in strings {
            switch mod.lowercased() {
            case "command", "cmd": flags.insert(.command)
            case "option", "opt", "alt": flags.insert(.option)
            case "control", "ctrl": flags.insert(.control)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        return flags
    }

    private func setupMonitoring() {
        debugLog(" Setting up monitoring")

        // Set up callback for automatic layout reconciliation + thumbnail refresh
        windowManager.onCacheRefresh = { [weak self] in
            guard let self else { return }

            // Not while the layout surface is open. It is an editor, and this
            // fires twice a second on the main thread: it would push every
            // half-dragged intermediate state out to real windows, and the AX
            // round trip to move them all stalls the drag it is reacting to,
            // which is what made resizing a pane move in visible steps.
            //
            // Saving applies the finished layout, so nothing is lost by waiting.
            if !self.spaceOverlay.isVisible {
                self.layoutManager.reconcileCurrentLayout()
            }

            WindowThumbnailCache.shared.start()  // no-op if already polling
        }

        // Start monitoring display changes (disconnects/reconnects)
        windowManager.startMonitoringDisplayChanges()

        // Start monitoring workspace (app launch/quit)
        windowManager.startMonitoringWorkspace()

        // Start polling for window changes
        windowManager.startPolling()

        // Request Screen Recording permission if not already granted
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        // Start thumbnail cache (requires Screen Recording permission — degrades gracefully)
        let interval = configManager.config.thumbnailCaptureInterval ?? 3.0
        WindowThumbnailCache.shared.updateInterval(interval)

        // The state at this point is only "we started"; whether capture actually
        // works isn't known until the first pass completes. Log the transitions
        // instead, so the log says why thumbnails are missing rather than
        // leaving it to be guessed at.
        WindowThumbnailCache.shared.onStateChange = { state in
            switch state {
            case .polling:
                debugLog(" Thumbnails: capturing (\(WindowThumbnailCache.shared.thumbnails.count) windows)")
            case .degraded:
                debugLog(" Thumbnails: unavailable — Screen Recording permission not granted."
                    + " Grant it in System Settings > Privacy & Security > Screen Recording;"
                    + " no restart needed.")
            case .unsupported:
                debugLog(" Thumbnails: unavailable — needs macOS 14 or later. Showing app icons.")
            case .stopped:
                debugLog(" Thumbnails: stopped")
            }
        }

        WindowThumbnailCache.shared.start()
        debugLog(" Thumbnail cache started, interval: \(interval)s")

        debugLog(" Monitoring started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up monitoring
        windowManager.stopPolling()
        windowManager.stopMonitoringDisplayChanges()
        windowManager.stopMonitoringWorkspace()
        WindowThumbnailCache.shared.stop()
    }

    func toggleQuickMove() {
        if let w = quickMoveWindow, w.isVisible {
            w.hide()
        } else {
            if quickMoveWindow == nil { quickMoveWindow = QuickMoveWindow() }
            quickMoveWindow?.show()
        }
    }

    func toggleSpaceOverlay() {
        spaceOverlay.toggle()
    }

    /// Open the surface unconditionally. Scripts say what they want rather than
    /// toggling, so a second `show` while it is open is not a close.
    func showSpaceOverlayForScripting() {
        NSApp.activate(ignoringOtherApps: true)
        if !spaceOverlay.isVisible { spaceOverlay.show() }
    }

    /// Hosts `SettingsView` in a plain window. SwiftUI's `Settings` scene is only
    /// reachable through `showSettingsWindow:`, which silently does nothing for
    /// an unbundled accessory binary — so we present the same view ourselves.
    private func showSettings() {
        if let existing = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 500, height: 400)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WindowThing Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindow()
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            debugLog("Accessibility permissions required. Please grant access in System Preferences > Privacy & Security > Accessibility")
        }
    }
}
