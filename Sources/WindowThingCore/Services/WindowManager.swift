import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import os.log

// Private AX API to get a window's CGWindowID from its AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

public class WindowManager: WindowManaging {
    public static let shared = WindowManager()

    static let perfLog = Logger(subsystem: "com.windowthing", category: "perf")

    /// Above this, a poll tick is stealing enough of the main thread to be felt.
    static let slowPollThresholdMs: Double = 20

    private var windowCache: [Window] = []
    private var displayCache: [Display] = []
    private var pollTimer: Timer?

    /// Guards the two caches. They are written from the main thread by
    /// `getWindows`/`getDisplays` and read from the layout-apply workers, which
    /// run several processes' frame writes at once.
    private let cacheLock = NSLock()

    /// Whether a window is one the layout should place, by CGWindowID.
    ///
    /// Answering costs a round trip into the owning app, but the answer never
    /// changes for a given window, so it is asked once when the window is first
    /// seen rather than on every refresh.
    private var manageableCache: [CGWindowID: Bool] = [:]

    private func cachedWindow(id: CGWindowID) -> Window? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return windowCache.first { $0.id == id }
    }

    private init() {}

    // MARK: - Display Management

    /// Convert a screen's Cocoa frame into the global coordinate space windows
    /// live in.
    ///
    /// `NSScreen.frame` is Cocoa: origin bottom-left of the primary screen, y
    /// increasing upwards. Window frames — read from `CGWindowListCopyWindowInfo`
    /// and written back through `kAXPositionAttribute` — are global CG: origin
    /// top-left of the primary screen, y increasing downwards. The two agree
    /// only on the primary screen itself, so without this a layout places
    /// windows at the wrong height on every other display.
    public static func globalFrame(
        forScreenFrame cocoa: CGRect,
        primaryHeight: CGFloat
    ) -> WindowFrame {
        WindowFrame(
            x: cocoa.minX,
            y: primaryHeight - cocoa.maxY,
            width: cocoa.width,
            height: cocoa.height
        )
    }

    public func getDisplays() -> [Display] {
        var displays: [Display] = []

        // The primary screen is the one with the menu bar, always first and
        // always at the Cocoa origin — its height is the flip axis.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        for (index, screen) in NSScreen.screens.enumerated() {
            let isMain = screen == NSScreen.main

            // Get display name from localized name
            let name = screen.localizedName

            displays.append(Display(
                id: index,
                name: name,
                // visibleFrame, not frame: the menu bar and Dock are not ours to
                // place windows under. macOS clamps any window that tries, so
                // targets derived from the full frame can never be reached — the
                // reconcile timer would see every window as misplaced and rewrite
                // it, several Accessibility round trips each, twice a second,
                // forever, without ever winning.
                //
                // The flip axis stays the *full* height of the primary screen,
                // since that is where the global coordinate origin is.
                frame: Self.globalFrame(
                    forScreenFrame: screen.visibleFrame,
                    primaryHeight: primaryHeight
                ),
                isMain: isMain
            ))
        }

        cacheLock.lock()
        displayCache = displays
        cacheLock.unlock()
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
        let exclusions = ConfigManager.shared.config.effectiveExclusions
        // Cache AX window elements per PID to avoid repeated API calls
        // Outer nil: not fetched yet. Inner nil: the app could not be asked, so
        // its windows fail open rather than silently dropping out of layouts.
        var axWindowsByPID: [pid_t: [AXUIElement]?] = [:]

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

            // Menus, popovers and panels that happen to be layer-0 and large
            // enough to pass the checks above. Resolved from the Accessibility
            // subrole, and cached per window, so the round trip is paid once
            // when a window first appears rather than on every refresh — most
            // passes ask nothing at all.
            let alreadyJudged = manageableCacheContains(windowID)
            if !alreadyJudged, axWindowsByPID[ownerPID] == nil {
                axWindowsByPID[ownerPID] = Self.axWindows(ofProcess: ownerPID)
            }
            guard isStandardWindow(
                pid: ownerPID, windowId: windowID,
                axWindows: alreadyJudged ? nil : axWindowsByPID[ownerPID] ?? nil
            ) else { continue }

            var title = windowInfo[kCGWindowName as String] as? String ?? ""

            // kCGWindowName requires Screen Recording permission and may be empty.
            // Fall back to AX API, matching by window position.
            if title.isEmpty {
                if axWindowsByPID[ownerPID] == nil {
                    axWindowsByPID[ownerPID] = Self.axWindows(ofProcess: ownerPID)
                }
                if let axWindows = axWindowsByPID[ownerPID] ?? nil {
                    title = axTitle(from: axWindows, matchingX: x, y: y) ?? ""
                }
            }

            // Get bundle ID
            let bundleId = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier

            let candidate = Window(
                id: windowID,
                title: title,
                application: ownerName,
                bundleId: bundleId,
                frame: WindowFrame(x: x, y: y, width: width, height: height),
                pid: ownerPID
            )

            // Windows named in the config. Some real windows are simply
            // indistinguishable from transient ones by any attribute — Finder's
            // Get Info is a standard, movable, resizable window — so they have
            // to be asked for by name rather than guessed at.
            if exclusions.excludes(candidate) { continue }

            windows.append(candidate)
        }

        cacheLock.lock()
        windowCache = windows
        cacheLock.unlock()
        pruneManageableCache(keeping: Set(
            windowList.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }))
        return windows
    }

    /// The app's Accessibility window list, or nil when it cannot be read.
    private static func axWindows(ofProcess pid: pid_t) -> [AXUIElement]? {
        let appElement = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &ref) == .success else { return nil }
        return ref as? [AXUIElement] ?? []
    }

    private func manageableCacheContains(_ windowID: CGWindowID) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return manageableCache[windowID] != nil
    }

    /// Forget windows that have gone, so the cache tracks what is on screen.
    private func pruneManageableCache(keeping live: Set<CGWindowID>) {
        cacheLock.lock()
        manageableCache = manageableCache.filter { live.contains($0.key) }
        cacheLock.unlock()
    }

    /// Whether the Accessibility API considers this a standard, placeable
    /// window — as opposed to a menu, popover, sheet or panel.
    ///
    /// The size and layer checks in `getWindows` don't catch these: an app is
    /// free to draw its right-click menu as an ordinary layer-0 window big
    /// enough to pass, and several do. `AXStandardWindow` is the marker of a
    /// real window; menus and popovers either report a different subrole or are
    /// not in the app's Accessibility window list at all.
    ///
    /// Fails *open*. If the app can't be asked — permissions, or it simply isn't
    /// answering — its windows are managed as before. Treating silence as "not a
    /// window" would make an unresponsive app drop out of every layout, which is
    /// far worse than occasionally moving a menu.
    /// The rule itself, separated from the round trips that gather its inputs
    /// so the policy — particularly what happens when an app won't answer — can
    /// be checked without a running window server.
    ///
    /// - Parameters:
    ///   - subrole: the window's Accessibility subrole, nil if it has none.
    ///   - foundInAXList: whether the app listed this window at all.
    ///   - axListReadable: whether the app's window list could be read.
    public static func isManageable(
        subrole: String?, foundInAXList: Bool, axListReadable: Bool
    ) -> Bool {
        // Silence is not a verdict. An app that cannot be asked keeps the
        // behaviour it had before this filter existed.
        guard axListReadable else { return true }
        // Listed by CoreGraphics but not by Accessibility: a menu or popover.
        guard foundInAXList else { return false }
        return subrole == kAXStandardWindowSubrole as String
    }

    private func isStandardWindow(
        pid: pid_t, windowId: CGWindowID, axWindows: [AXUIElement]?
    ) -> Bool {
        cacheLock.lock()
        if let cached = manageableCache[windowId] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // nil means the app's window list could not be read: fail open.
        guard let axWindows else { return true }

        var subrole: String?
        var found = false
        for element in axWindows {
            var elementId: CGWindowID = 0
            guard _AXUIElementGetWindow(element, &elementId) == .success,
                  elementId == windowId else { continue }

            found = true
            var subroleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element, kAXSubroleAttribute as CFString, &subroleRef) == .success {
                subrole = subroleRef as? String
            }
            break
        }

        let result = Self.isManageable(
            subrole: subrole, foundInAXList: found, axListReadable: true)

        cacheLock.lock()
        manageableCache[windowId] = result
        cacheLock.unlock()
        return result
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
        guard let window = cachedWindow(id: windowId) else {
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
        // Resolving a window id to its AX element costs one round trip to list
        // the app's windows plus one per window to read its id. Applying a
        // layout calls this once per window, so without memoising, an app with
        // ten placed windows gets its whole window list walked ten times.
        if let element = axWindowElement(pid: pid, windowId: windowId) {
            return applyFrame(frame, to: element)
        }

        // Fallback: match by title from cache
        if let cached = cachedWindow(id: windowId) {
            return setWindowFrame(pid: pid, windowTitle: cached.title, frame: frame)
        }

        return false
    }

    /// AX elements for a process's windows, keyed by CGWindowID.
    ///
    /// Valid only for the duration of one reconcile pass — windows open and
    /// close — so `beginFrameBatch()`/`endFrameBatch()` bracket its lifetime and
    /// it stays empty outside one.
    private var axElementCache: [pid_t: [CGWindowID: AXUIElement]] = [:]
    private var batchDepth = 0

    /// Guards the two above. Batches run on the layout-apply queue, but frames
    /// are also set directly from the main thread (moving a window to a cell,
    /// restoring a setup), so both can be touched at once.
    private let batchLock = NSLock()

    /// Memoise AX window lookups until the matching `endFrameBatch()`.
    ///
    /// Callers that set many frames at once should bracket the run; a single
    /// `setWindowFrame` outside a batch resolves directly and caches nothing, so
    /// it can't act on a stale element.
    public func beginFrameBatch() {
        batchLock.lock()
        batchDepth += 1
        batchLock.unlock()
    }

    public func endFrameBatch() {
        batchLock.lock()
        batchDepth = max(0, batchDepth - 1)
        if batchDepth == 0 { axElementCache.removeAll() }
        batchLock.unlock()
    }

    private func axWindowElement(pid: pid_t, windowId: CGWindowID) -> AXUIElement? {
        batchLock.lock()
        let batching = batchDepth > 0
        let cached = batching ? axElementCache[pid] : nil
        batchLock.unlock()

        if let cached { return cached[windowId] }

        // The AX round trips stay outside the lock — they reach into another
        // process and can block, and holding a lock across that would serialise
        // every caller behind the slowest app.
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        var byId: [CGWindowID: AXUIElement] = [:]

        if AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for window in windows {
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(window, &wid) == .success {
                    byId[wid] = window
                }
            }
        }

        if batching {
            batchLock.lock()
            // Only if a batch is still open — one may have ended while the AX
            // calls above were in flight, and caching then would outlive it.
            if batchDepth > 0 { axElementCache[pid] = byId }
            batchLock.unlock()
        }

        return byId[windowId]
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
            let t0 = CFAbsoluteTimeGetCurrent()
            self?.refreshCache()
            self?.onCacheRefresh?()

            // Silent while healthy. This runs twice a second on the main
            // thread, so anything slow here is felt directly as dropped frames
            // — worth saying so rather than logging every tick into the noise.
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            if elapsedMs > WindowManager.slowPollThresholdMs {
                let ms = String(format: "%.1f", elapsedMs)
                WindowManager.perfLog.warning("slow poll tick: \(ms, privacy: .public)ms on the main thread")
            }
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
