import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

// Private AX API to get a window's CGWindowID from its AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

public class WindowManager: WindowManaging {
    public static let shared = WindowManager()

    private var windowCache: [Window] = []
    private var displayCache: [Display] = []
    private var pollTimer: Timer?

    private init() {}

    // MARK: - Display Management

    public func getDisplays() -> [Display] {
        var displays: [Display] = []

        for (index, screen) in NSScreen.screens.enumerated() {
            let screenFrame = screen.frame
            let isMain = screen == NSScreen.main

            // Get display name from localized name
            let name = screen.localizedName

            displays.append(Display(
                id: index,
                name: name,
                frame: WindowFrame(from: screenFrame),
                isMain: isMain
            ))
        }

        displayCache = displays
        DisplayRegistry.shared.record(displays: displays)
        return displays
    }

    // MARK: - Window Management

    public func getWindows() -> [Window] {
        var windows: [Window] = []

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return windows
        }

        let minSize = ConfigManager.shared.config.minimumWindowSize
        // Cache AX window elements per PID to avoid repeated API calls
        var axWindowsByPID: [pid_t: [AXUIElement]] = [:]

        for windowInfo in windowList {
            guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0 // Normal window layer
            else {
                continue
            }

            // Skip transparent windows
            if let alpha = windowInfo[kCGWindowAlpha as String] as? CGFloat, alpha < 0.1 {
                continue
            }

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0

            // Skip small windows (utility windows, etc.)
            if width < minSize.width || height < minSize.height {
                continue
            }

            var title = windowInfo[kCGWindowName as String] as? String ?? ""

            // kCGWindowName requires Screen Recording permission and may be empty.
            // Fall back to AX API, matching by window position.
            if title.isEmpty {
                if axWindowsByPID[ownerPID] == nil {
                    let appElement = AXUIElementCreateApplication(ownerPID)
                    var ref: CFTypeRef?
                    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref) == .success {
                        axWindowsByPID[ownerPID] = ref as? [AXUIElement] ?? []
                    } else {
                        axWindowsByPID[ownerPID] = []
                    }
                }
                if let axWindows = axWindowsByPID[ownerPID] {
                    title = axTitle(from: axWindows, matchingX: x, y: y) ?? ""
                }
            }

            // Get bundle ID
            let bundleId = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier

            windows.append(Window(
                id: windowID,
                title: title,
                application: ownerName,
                bundleId: bundleId,
                frame: WindowFrame(x: x, y: y, width: width, height: height),
                pid: ownerPID
            ))
        }

        windowCache = windows
        return windows
    }

    /// Returns the AX window title that best matches the given screen position.
    private func axTitle(from axWindows: [AXUIElement], matchingX x: CGFloat, y: CGFloat) -> String? {
        for axWindow in axWindows {
            var posRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                  let posVal = posRef else { continue }
            var axPos = CGPoint.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &axPos)
            if abs(axPos.x - x) < 2 && abs(axPos.y - y) < 2 {
                var titleRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success else { continue }
                return titleRef as? String
            }
        }
        return nil
    }

    public func setWindowFrame(windowId: CGWindowID, frame: WindowFrame) -> Bool {
        // Find the window's application
        guard let window = windowCache.first(where: { $0.id == windowId }) else {
            return false
        }

        return setWindowFrame(pid: window.pid, windowTitle: window.title, frame: frame)
    }

    public func setWindowFrame(pid: pid_t, windowTitle: String? = nil, frame: WindowFrame) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        // Find the target window
        var targetWindow: AXUIElement?

        if let title = windowTitle {
            for window in windows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let windowTitle = titleRef as? String,
                   windowTitle == title {
                    targetWindow = window
                    break
                }
            }
        }

        // Use first window if no specific title or not found
        if targetWindow == nil {
            targetWindow = windows.first
        }

        guard let window = targetWindow else {
            return false
        }

        return applyFrame(frame, to: window)
    }

    public func setWindowFrame(pid: pid_t, windowId: CGWindowID, frame: WindowFrame) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        // Match by CGWindowID
        for window in windows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(window, &wid) == .success, wid == windowId {
                return applyFrame(frame, to: window)
            }
        }

        // Fallback: match by title from cache
        if let cached = windowCache.first(where: { $0.id == windowId }) {
            return setWindowFrame(pid: pid, windowTitle: cached.title, frame: frame)
        }

        return false
    }

    private func applyFrame(_ frame: WindowFrame, to window: AXUIElement) -> Bool {
        var position = CGPoint(x: frame.x, y: frame.y)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }

        var size = CGSize(width: frame.width, height: frame.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        return true
    }

    // MARK: - Focus Management

    public func getFocusedApplication() -> Application? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = frontApp.processIdentifier
        let name = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier

        // Get focused window
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)

        var focusedWindow: Window?

        if result == .success, let windowElement = focusedWindowRef {
            // Get window title
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""

            // Get window position
            var positionRef: CFTypeRef?
            var position = CGPoint.zero
            if AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXPositionAttribute as CFString, &positionRef) == .success {
                AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
            }

            // Get window size
            var sizeRef: CFTypeRef?
            var size = CGSize.zero
            if AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef) == .success {
                AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            }

            focusedWindow = Window(
                id: 0, // We don't have the CGWindowID here
                title: title,
                application: name,
                bundleId: bundleId,
                frame: WindowFrame(x: position.x, y: position.y, width: size.width, height: size.height),
                pid: pid
            )
        }

        return Application(
            id: pid,
            name: name,
            bundleId: bundleId,
            focusedWindow: focusedWindow
        )
    }

    public func focusApplication(bundleId: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return
        }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    public func focusApplication(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return
        }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    // MARK: - Caching

    public func getCachedWindows() -> [Window] {
        return windowCache
    }

    public func getCachedDisplays() -> [Display] {
        return displayCache
    }

    public func refreshCache() {
        _ = getDisplays()
        _ = getWindows()
    }

    // MARK: - Polling

    public var onCacheRefresh: (() -> Void)?

    public func startPolling() {
        let interval = TimeInterval(ConfigManager.shared.config.pollIntervalMs) / 1000.0
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshCache()
            self?.onCacheRefresh?()
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Display Change Notifications

    private var displayNotificationObserver: NSObjectProtocol?

    public func startMonitoringDisplayChanges() {
        // Monitor for display configuration changes
        displayNotificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCache()
            self?.onCacheRefresh?()
        }
    }

    public func stopMonitoringDisplayChanges() {
        if let observer = displayNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
            displayNotificationObserver = nil
        }
    }

    // MARK: - Workspace Notifications

    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminateObserver: NSObjectProtocol?
    private var appActivateObserver: NSObjectProtocol?

    public func startMonitoringWorkspace() {
        let workspace = NSWorkspace.shared

        // Monitor app launches
        appLaunchObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Wait a bit for windows to appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refreshCache()
                self?.onCacheRefresh?()
            }
        }

        // Monitor app terminations
        appTerminateObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCache()
            self?.onCacheRefresh?()
        }

        // Monitor app activations (window focus changes)
        appActivateObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCache()
        }
    }

    public func stopMonitoringWorkspace() {
        let workspace = NSWorkspace.shared

        if let observer = appLaunchObserver {
            workspace.notificationCenter.removeObserver(observer)
            appLaunchObserver = nil
        }

        if let observer = appTerminateObserver {
            workspace.notificationCenter.removeObserver(observer)
            appTerminateObserver = nil
        }

        if let observer = appActivateObserver {
            workspace.notificationCenter.removeObserver(observer)
            appActivateObserver = nil
        }
    }
}
