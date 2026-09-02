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

    /// Where the window-server list is fetched, off the main thread.
    private let pollQueue = DispatchQueue(label: "com.windowthing.window-poll", qos: .userInitiated)

    /// Whether a tick is between its off-main fetch and its main-thread finish.
    /// Main thread only.
    private var pollInFlight = false

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

    /// Fingerprint of the window list the cache was last built from, and when.
    ///
    /// `getWindows` runs twice a second on the main thread, and most of its
    /// cost is Accessibility round trips into other processes — one per app to
    /// list its windows, plus a position read per window — paid whenever a
    /// window's `kCGWindowName` comes back empty. Almost every tick asks all of
    /// that again to arrive at exactly the answer it already had: measured at
    /// 88-91ms per tick, on the thread that is also handling keystrokes.
    ///
    /// `CGWindowListCopyWindowInfo` itself is cheap, so its contents make a
    /// serviceable "has anything moved, opened or closed" check. When the
    /// fingerprint matches, the expensive half is skipped and the cached list
    /// returned as-is.
    private var lastWindowFingerprint: Int?
    private var lastWindowBuild: CFAbsoluteTime = 0

    /// When titles were last read through Accessibility, tracked separately
    /// from the rebuild time on purpose.
    ///
    /// Timing the refresh off `lastWindowBuild` would mean that while anything
    /// is moving — a drag, a layout being applied — every tick rebuilds, resets
    /// the clock, and the age never reaches the limit, so titles would go
    /// stale indefinitely in exactly the situation where windows are most
    /// active. This clock only moves when titles are actually re-read.
    private var lastTitleRefresh: CFAbsoluteTime = 0

    /// How long a matching fingerprint may go on standing in for a real refresh.
    ///
    /// A window whose title changes without moving — switching tabs, say — is
    /// invisible to the fingerprint when the title only exists behind
    /// Accessibility. Rebuilding anyway on this cadence bounds how stale a
    /// title can get, while still skipping the great majority of ticks.
    static let windowCacheMaxAge: CFAbsoluteTime = 5

    /// Window titles that had to be read through Accessibility, by CGWindowID.
    ///
    /// `kCGWindowName` is empty for every window unless Screen Recording has
    /// been granted, so on most machines every window falls through to the
    /// Accessibility path: list the owning app's windows, then read each one's
    /// position to find the match. Measured at 33ms of a 35ms rebuild, for 28
    /// windows, and it was being paid twice a second to arrive at titles that
    /// had not changed.
    ///
    /// A window new to this pass is never served from here, so a window
    /// appearing is still titled immediately; only re-reading is avoided.
    private var titleCache: [CGWindowID: String] = [:]

    /// Bundle identifiers by process, which do not change for a running process.
    private var bundleIdCache: [pid_t: String?] = [:]

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

    /// Ask the window server what is on screen.
    ///
    /// Split out because it is synchronous IPC and, measured, by far the most
    /// expensive thing the poll does — 88ms, 122ms, 192ms on consecutive ticks
    /// with everything else cached away. Nothing here touches this class's
    /// state, so the poll can make this call off the main thread and leave only
    /// the cheap half on it.
    static func copyWindowList() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    public func getWindows() -> [Window] {
        let start = CFAbsoluteTimeGetCurrent()
        let list = Self.copyWindowList()
        return buildWindows(from: list, listMs: (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    /// A cheap summary of what is on screen, used to decide whether the
    /// expensive half of a rebuild can be skipped.
    ///
    /// Covers what a placement depends on: which windows exist, where they are,
    /// how big they are, and what the window server says they are called. A
    /// change the fingerprint misses is a change the caches never notice, so it
    /// errs towards noticing too much — a reordering of the same windows counts
    /// as a change, which costs one needless rebuild rather than risking a
    /// stale answer.
    static func fingerprint(of windowList: [[String: Any]]) -> Int {
        var hasher = Hasher()
        for info in windowList {
            hasher.combine(info[kCGWindowNumber as String] as? CGWindowID ?? 0)
            hasher.combine(info[kCGWindowName as String] as? String ?? "")
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] {
                hasher.combine(bounds["X"] ?? 0)
                hasher.combine(bounds["Y"] ?? 0)
                hasher.combine(bounds["Width"] ?? 0)
                hasher.combine(bounds["Height"] ?? 0)
            }
        }
        return hasher.finalize()
    }

    /// Turn a window-server listing into the windows a layout can place.
    ///
    /// Main thread only: it reads the config, and the caches it fills are also
    /// read by the layout-apply workers.
    func buildWindows(from windowList: [[String: Any]], listMs: Double) -> [Window] {
        var windows: [Window] = []
        let callStart = CFAbsoluteTimeGetCurrent() - (listMs / 1000)

        // Cheap first: if nothing on screen has changed since the last build,
        // the answer is the one already cached and none of the Accessibility
        // work below needs doing.
        let fingerprint = Self.fingerprint(of: windowList)

        cacheLock.lock()
        let unchanged = lastWindowFingerprint == fingerprint
        let now = CFAbsoluteTimeGetCurrent()
        let age = now - lastWindowBuild
        let titleAge = now - lastTitleRefresh
        let cached = windowCache
        cacheLock.unlock()

        if unchanged, age < Self.windowCacheMaxAge {
            // Reported from the cheap path too. A tick can be slow without
            // rebuilding anything — asking the window server for the list is
            // itself work — and a breakdown that only covers rebuilds makes
            // that look like time going nowhere.
            let earlyMs = (CFAbsoluteTimeGetCurrent() - callStart) * 1000
            if earlyMs > Self.slowPollThresholdMs {
                let total = String(format: "%.1f", earlyMs)
                let list = String(format: "%.1f", listMs)
                Self.perfLog.warning(
                    "slow window list (nothing changed): \(total, privacy: .public)ms, of which the window-server list was \(list, privacy: .public)ms")
            }
            return cached
        }

        // A rebuild forced by the age limit is the one that refreshes titles. A
        // rebuild forced by something moving reuses them: what moved is the
        // geometry, and re-reading every title to discover that they are all
        // unchanged is the cost this is here to avoid.
        let refreshTitles = titleAge >= Self.windowCacheMaxAge

        let buildStart = callStart
        let minSize = ConfigManager.shared.config.minimumWindowSize
        let exclusions = ConfigManager.shared.config.effectiveExclusions
        // Cache AX window elements per PID to avoid repeated API calls
        // Outer nil: not fetched yet. Inner nil: the app could not be asked, so
        // its windows fail open rather than silently dropping out of layouts.
        var axWindowsByPID: [pid_t: [AXUIElement]?] = [:]

        // Where a rebuild's time actually goes. Each of these is a synchronous
        // round trip into another process, so counting them says whether a slow
        // tick is one expensive app or a hundred cheap calls.
        var axListCalls = 0
        var axTitleCalls = 0
        var runningAppLookups = 0
        var axMs: Double = 0
        var scanned = 0

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
            scanned += 1
            let alreadyJudged = manageableCacheContains(windowID)
            if !alreadyJudged, axWindowsByPID[ownerPID] == nil {
                let t = CFAbsoluteTimeGetCurrent()
                axWindowsByPID[ownerPID] = Self.axWindows(ofProcess: ownerPID)
                axMs += (CFAbsoluteTimeGetCurrent() - t) * 1000
                axListCalls += 1
            }
            guard isStandardWindow(
                pid: ownerPID, windowId: windowID,
                axWindows: alreadyJudged ? nil : axWindowsByPID[ownerPID] ?? nil
            ) else { continue }

            var title = windowInfo[kCGWindowName as String] as? String ?? ""

            // kCGWindowName requires Screen Recording permission and may be empty.
            // Fall back to AX API, matching by window position.
            if title.isEmpty {
                if !refreshTitles, let known = cachedTitle(for: windowID) {
                    title = known
                } else {
                    let t = CFAbsoluteTimeGetCurrent()
                    if axWindowsByPID[ownerPID] == nil {
                        axWindowsByPID[ownerPID] = Self.axWindows(ofProcess: ownerPID)
                        axListCalls += 1
                    }
                    if let axWindows = axWindowsByPID[ownerPID] ?? nil {
                        title = axTitle(from: axWindows, matchingX: x, y: y) ?? ""
                    }
                    axMs += (CFAbsoluteTimeGetCurrent() - t) * 1000
                    axTitleCalls += 1
                    cacheTitle(title, for: windowID)
                }
            }

            let bundleId = cachedBundleId(for: ownerPID) ?? {
                runningAppLookups += 1
                let resolved = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
                cacheBundleId(resolved, for: ownerPID)
                return resolved
            }()

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
        lastWindowFingerprint = fingerprint
        lastWindowBuild = CFAbsoluteTimeGetCurrent()
        if refreshTitles { lastTitleRefresh = lastWindowBuild }
        cacheLock.unlock()

        pruneManageableCache(keeping: Set(
            windowList.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }))

        let buildMs = (CFAbsoluteTimeGetCurrent() - buildStart) * 1000
        if buildMs > Self.slowPollThresholdMs {
            let total = String(format: "%.1f", buildMs)
            let ax = String(format: "%.1f", axMs)
            let list = String(format: "%.1f", listMs)
            Self.perfLog.warning(
                "slow window rebuild: \(total, privacy: .public)ms for \(scanned, privacy: .public) windows (window-server list \(list, privacy: .public)ms, accessibility \(ax, privacy: .public)ms over \(axListCalls, privacy: .public) window-list calls and \(axTitleCalls, privacy: .public) title lookups, \(runningAppLookups, privacy: .public) bundle-id lookups)")
        }
        return windows
    }

    /// The app's Accessibility window list, or nil when it cannot be read.
    ///
    /// Asks for `kAXWindows` and falls back to the application element's
    /// children when that comes back empty. Finder is why: it answers
    /// `kAXWindows` with success and an empty array while its window sits in
    /// `AXChildren` as a perfectly ordinary, resizable `AXWindow`. Every path
    /// that looked windows up through `kAXWindows` alone therefore found
    /// nothing for Finder and left its windows where they were, while
    /// reporting no error anywhere.
    private static func axWindows(ofProcess pid: pid_t) -> [AXUIElement]? {
        let appElement = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &ref) == .success else { return nil }

        let windows = ref as? [AXUIElement] ?? []
        if !windows.isEmpty { return windows }

        // Only reached for an app that reports no windows, so the extra round
        // trip is not paid by apps that answer the question properly.
        return childWindows(of: appElement)
    }

    /// Windows found among an application element's children.
    private static func childWindows(of appElement: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return [] }

        // A menu bar and a scroll area sit alongside the window in Finder's
        // children, so this cannot take them wholesale.
        return children.filter { child in
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                child, kAXRoleAttribute as CFString, &roleRef) == .success else { return false }
            return roleRef as? String == kAXWindowRole as String
        }
    }

    private func cachedTitle(for windowID: CGWindowID) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return titleCache[windowID]
    }

    private func cacheTitle(_ title: String, for windowID: CGWindowID) {
        cacheLock.lock()
        titleCache[windowID] = title
        cacheLock.unlock()
    }

    /// Nested optional deliberately: the outer says whether the process has been
    /// asked, the inner whether it has a bundle id. Flattening them would make
    /// an app without one get asked again on every pass.
    private func cachedBundleId(for pid: pid_t) -> String?? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return bundleIdCache[pid]
    }

    private func cacheBundleId(_ bundleId: String?, for pid: pid_t) {
        cacheLock.lock()
        bundleIdCache[pid] = bundleId
        cacheLock.unlock()
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
        titleCache = titleCache.filter { live.contains($0.key) }
        cacheLock.unlock()
    }

    /// Forget a process's cached bundle id. Called when an app terminates, so a
    /// pid reused by a different app is not answered from the old one.
    public func forgetProcess(_ pid: pid_t) {
        cacheLock.lock()
        bundleIdCache.removeValue(forKey: pid)
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
        guard let windows = Self.axWindows(ofProcess: pid), !windows.isEmpty else {
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
        var byId: [CGWindowID: AXUIElement] = [:]

        for window in Self.axWindows(ofProcess: pid) ?? [] {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(window, &wid) == .success {
                byId[wid] = window
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

    /// Report what a window actually did with the frame it was given.
    ///
    /// Two Accessibility reads per window on top of the writes, so it is off
    /// unless asked for: `--probe-frames`. Worth having because a window that
    /// refuses a frame looks exactly like one that was never asked, and the
    /// settle tracker then records the refusal as the best it can do.
    static let verifyFrames = CommandLine.arguments.contains("--probe-frames")

    private static func readFrame(of window: AXUIElement) -> WindowFrame? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return WindowFrame(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    private func applyFrame(_ frame: WindowFrame, to window: AXUIElement) -> Bool {
        var positionError: AXError = .success
        var position = CGPoint(x: frame.x, y: frame.y)
        if let positionValue = AXValueCreate(.cgPoint, &position) {
            positionError = AXUIElementSetAttributeValue(
                window, kAXPositionAttribute as CFString, positionValue)
        }

        var sizeError: AXError = .success
        var size = CGSize(width: frame.width, height: frame.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            sizeError = AXUIElementSetAttributeValue(
                window, kAXSizeAttribute as CFString, sizeValue)
        }

        if Self.verifyFrames {
            let got = Self.readFrame(of: window)
            let landed = got.map {
                String(format: "%.0f,%.0f %.0fx%.0f", $0.x, $0.y, $0.width, $0.height)
            } ?? "unreadable"
            let wanted = String(format: "%.0f,%.0f %.0fx%.0f",
                                frame.x, frame.y, frame.width, frame.height)
            if got == nil || got!.needsMove(to: frame) {
                Self.perfLog.warning(
                    "frame refused: wanted \(wanted, privacy: .public), got \(landed, privacy: .public) (setPosition \(positionError.rawValue, privacy: .public), setSize \(sizeError.rawValue, privacy: .public))")
            } else {
                Self.perfLog.info("frame applied: \(wanted, privacy: .public)")
            }
        }

        // The writes are reported rather than the read-back, so this says
        // whether the window accepted the instruction, not whether it obeyed —
        // a window with a minimum size returns success and stays put.
        return positionError == .success && sizeError == .success
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
            guard let self else { return }

            // A tick still in flight means the window server is answering more
            // slowly than the poll asks. Starting another would queue work
            // faster than it drains and land every reply on the main thread at
            // once — the opposite of what moving it off there is for.
            guard !self.pollInFlight else { return }
            self.pollInFlight = true

            self.pollQueue.async { [weak self] in
                guard let self else { return }
                let tList = CFAbsoluteTimeGetCurrent()
                let list = Self.copyWindowList()
                let listMs = (CFAbsoluteTimeGetCurrent() - tList) * 1000

                DispatchQueue.main.async {
                    self.finishPollTick(list: list, listMs: listMs)
                }
            }
        }
    }

    /// The half of a poll tick that has to be on the main thread.
    private func finishPollTick(list: [[String: Any]], listMs: Double) {
        defer { pollInFlight = false }
        let t0 = CFAbsoluteTimeGetCurrent()
        _ = getDisplays()
        let tDisplays = CFAbsoluteTimeGetCurrent()
        _ = buildWindows(from: list, listMs: 0)
        let tWindows = CFAbsoluteTimeGetCurrent()
        onCacheRefresh?()
        let tDone = CFAbsoluteTimeGetCurrent()

        // Silent while healthy. This runs twice a second on the main thread, so
        // anything slow here is felt directly as dropped frames — worth saying
        // so rather than logging every tick into the noise.
        //
        // Broken down by phase because the total on its own does not say who to
        // blame: the two cache reads and the reconcile that follows them have
        // entirely separate causes, and a tick that is slow for one of them
        // looks exactly like a tick that is slow for another. The window-server
        // time is reported alongside but is no longer part of the total — it is
        // now paid off the main thread, and the two being confusable is what
        // sent the first pass at this looking in the wrong place.
        let elapsedMs = (tDone - t0) * 1000
        if elapsedMs > WindowManager.slowPollThresholdMs {
            let ms = String(format: "%.1f", elapsedMs)
            let d = String(format: "%.1f", (tDisplays - t0) * 1000)
            let w = String(format: "%.1f", (tWindows - tDisplays) * 1000)
            let r = String(format: "%.1f", (tDone - tWindows) * 1000)
            let l = String(format: "%.1f", listMs)
            WindowManager.perfLog.warning(
                "slow poll tick: \(ms, privacy: .public)ms on the main thread (displays \(d, privacy: .public)ms, windows \(w, privacy: .public)ms, reconcile \(r, privacy: .public)ms; the window-server list took \(l, privacy: .public)ms off it)")
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
        ) { [weak self] note in
            // Drop the dead process's cached bundle id first: pids are reused,
            // and answering for a new app out of the old one's entry would
            // quietly mis-match every pin that names it.
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication {
                self?.forgetProcess(app.processIdentifier)
            }
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
