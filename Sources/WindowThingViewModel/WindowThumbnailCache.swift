import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit
import WindowThingCore

// MARK: - WindowThumbnailCache

/// Background service that periodically captures and caches screenshot
/// thumbnails for all visible windows, using ScreenCaptureKit.
///
/// This used to use `CGWindowListCreateImage`, which Apple has withdrawn: it is
/// marked *unavailable* in the macOS 26 SDK and only still compiled here because
/// the package's deployment target is 13.0. It works at runtime today, but it is
/// a dead end.
///
/// `SCScreenshotManager` is macOS 14+, so on macOS 13 the cache reports
/// `.unsupported` and stays empty. Thumbnails are an optional nicety — callers
/// already fall back to app icons whenever the cache has nothing — so the app
/// keeps working, it just shows icons there. Raising the deployment target to
/// 14.0 would let the availability gate below be deleted.
///
/// Callers also fall back to app icons when Screen Recording permission is not
/// granted, which surfaces here as `.degraded`.
public final class WindowThumbnailCache: @unchecked Sendable {

    // MARK: - State

    public enum State: Equatable {
        case stopped
        case polling
        /// Screen Recording permission is missing or was revoked; thumbnails are cleared.
        case degraded
        /// This macOS is too old for ScreenCaptureKit screenshots (needs 14+).
        case unsupported
    }

    public private(set) var state: State = .stopped

    /// Current cache snapshot. Key = CGWindowID (the AX window's on-screen ID).
    public private(set) var thumbnails: [CGWindowID: CGImage] = [:]

    /// The same images wrapped for AppKit, built once per capture rather than
    /// per lookup. `nsImage(for:)` is called from view bodies — once per window
    /// tile, and every chooser pane lists every window — so building them there
    /// meant dozens of allocations on each pass of the render loop, including
    /// while dragging or switching layouts.
    private var nsImages: [CGWindowID: NSImage] = [:]

    /// Full-resolution copies, captured only for windows currently drawn large
    /// enough that the thumbnail cap would show. A chooser tile is a couple of
    /// hundred points wide and never needs one; a pane-filling preview does.
    private var fullImages: [CGWindowID: NSImage] = [:]

    /// Which windows want a full-resolution capture. Written from view
    /// lifecycle on the main thread, read from the capture task.
    private var fullResRequests: Set<CGWindowID> = []
    private let requestLock = NSLock()

    /// Called on the main queue after each successful refresh.
    public var onUpdate: (() -> Void)?

    /// Called on the main queue when `state` changes, and only then — capture
    /// runs every few seconds, so logging every refresh would drown the log.
    /// Transitions are the interesting part: losing permission, or regaining it
    /// without a restart.
    public var onStateChange: ((State) -> Void)?

    /// Capture interval in seconds. Clamped to [2, 5] at start time.
    public var captureInterval: TimeInterval

    /// How many windows to capture at once. ScreenCaptureKit screenshots carry
    /// more per-call overhead than the old synchronous CoreGraphics grab, so
    /// they run concurrently — but bounded, so a session with many windows
    /// doesn't produce a burst of work every few seconds.
    private static let maxConcurrentCaptures = 4

    /// Windows smaller than this in either dimension aren't worth a thumbnail.
    private static let minimumWindowEdge: CGFloat = 50

    /// Longest edge of a captured thumbnail, in pixels. Comfortably above the
    /// size they are drawn at — including on a Retina display — while keeping
    /// them small enough that drawing a paneful costs nothing noticeable.
    private static let maxThumbnailEdge: CGFloat = 480

    private var pollTask: Task<Void, Never>?

    /// How many times the capture loop has been started. Internal rather than
    /// private so tests can assert that repeated `start()` calls don't stack up
    /// loops — the bug this class had for as long as it degraded silently.
    private(set) var pollLoopStarts = 0

    // MARK: - Singleton

    public static let shared = WindowThumbnailCache()

    public init(captureInterval: TimeInterval = 3.0) {
        self.captureInterval = captureInterval
    }

    // MARK: - Lifecycle

    /// Idempotent: callers invoke this from refresh callbacks that fire often,
    /// so it must be cheap and must not restart a loop that is already running.
    ///
    /// The guard is on the loop, not on `state`. Keying off `state` looks right
    /// but isn't: once capture degrades for want of permission the state is no
    /// longer `.polling`, so every subsequent call would spawn another capture
    /// loop. The loop already retries on its own schedule and recovers by
    /// itself when permission is granted, so there is nothing to restart.
    public func start() {
        guard pollTask == nil, state != .unsupported else { return }

        guard #available(macOS 14.0, *) else {
            state = .unsupported
            thumbnails = [:]
            return
        }

        state = .polling
        startPolling(interval: Self.clamp(captureInterval))
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        state = .stopped
    }

    /// Update the capture interval and restart the loop if currently polling.
    public func updateInterval(_ interval: TimeInterval) {
        captureInterval = Self.clamp(interval)
        guard state == .polling else { return }
        guard #available(macOS 14.0, *) else { return }
        startPolling(interval: captureInterval)
    }

    /// Ask for this window to also be captured at its native size, for as long
    /// as something is drawing it large. Reference-counted by caller pairs of
    /// request/release, so two panes showing the same window both have to let go.
    public func requestFullResolution(for windowID: CGWindowID) {
        requestLock.lock()
        fullResRequests.insert(windowID)
        requestLock.unlock()
    }

    public func releaseFullResolution(for windowID: CGWindowID) {
        requestLock.lock()
        fullResRequests.remove(windowID)
        requestLock.unlock()
    }

    /// How many windows currently want a native-size capture. Internal so tests
    /// can check the request bookkeeping without a capture session.
    var fullResolutionRequestCount: Int { currentFullResRequests().count }

    /// Taking the lock in a synchronous method: NSLock cannot be used directly
    /// from an async context, and the capture task needs this snapshot.
    private func currentFullResRequests() -> Set<CGWindowID> {
        requestLock.lock()
        defer { requestLock.unlock() }
        return fullResRequests
    }

    /// The native-size image for a window, if one was requested and captured.
    /// Callers fall back to the ordinary thumbnail until the next capture lands.
    public func fullImage(for windowID: CGWindowID) -> NSImage? {
        fullImages[windowID]
    }

    static func clamp(_ interval: TimeInterval) -> TimeInterval {
        max(2.0, min(5.0, interval))
    }

    /// Whether a window is worth capturing: normal application windows only
    /// (layer 0 excludes menus, docks and other chrome), big enough to be
    /// recognisable as a thumbnail.
    static func shouldCapture(width: CGFloat, height: CGFloat, layer: Int) -> Bool {
        layer == 0 && width > minimumWindowEdge && height > minimumWindowEdge
    }

    // MARK: - Capture

    /// The interval is passed in rather than read from `captureInterval` inside
    /// the loop: the property is written from the main queue, and re-reading it
    /// on a background task would be a data race. Changing it restarts the loop.
    @available(macOS 14.0, *)
    private func startPolling(interval: TimeInterval) {
        pollLoopStarts += 1
        pollTask?.cancel()
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.captureOnce()
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return  // cancelled
                }
            }
        }
    }

    @available(macOS 14.0, *)
    private func captureOnce() async {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true)
        } catch {
            // ScreenCaptureKit throws here when Screen Recording has not been
            // granted. Unlike the old preflight check this also asks the system
            // for access, so a first run can still surface the prompt. The loop
            // keeps running, so granting permission recovers without a restart.
            await publish(state: .degraded, thumbnails: [:], nsImages: [:], fullImages: [:])
            return
        }

        let targets = content.windows.filter {
            Self.shouldCapture(width: $0.frame.width, height: $0.frame.height, layer: $0.windowLayer)
        }

        var captured: [CGWindowID: CGImage] = [:]

        await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            var pending = targets.makeIterator()

            // Prime the group up to the concurrency cap, then top it up as each
            // capture lands, so at most `maxConcurrentCaptures` are in flight.
            for _ in 0 ..< Self.maxConcurrentCaptures {
                guard let window = pending.next() else { break }
                group.addTask { (window.windowID, await Self.screenshot(of: window)) }
            }

            while let (windowID, image) = await group.next() {
                if let image { captured[windowID] = image }
                if let window = pending.next() {
                    group.addTask { (window.windowID, await Self.screenshot(of: window)) }
                }
            }
        }

        // Wrapping happens here, on the capture task, not on whatever thread
        // happens to be drawing.
        let wrapped = captured.mapValues {
            NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }

        let wanted = currentFullResRequests()

        // Only ever a few — one per pane drawing a window large — so these are
        // captured at the display's own pixel density without reintroducing the
        // cost the cap removed.
        let pixelScale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }

        var full: [CGWindowID: NSImage] = [:]
        for window in targets where wanted.contains(window.windowID) {
            if let image = await Self.screenshot(of: window, maxEdge: nil, pixelScale: pixelScale) {
                // Size in *points*, not pixels. That is what tells AppKit the
                // image has more pixels than points — i.e. that it is a Retina
                // representation — so it is drawn at full density rather than
                // being treated as an oversized 1x image.
                full[window.windowID] = NSImage(
                    cgImage: image,
                    size: NSSize(width: window.frame.width, height: window.frame.height))
            }
        }

        await publish(state: .polling, thumbnails: captured, nsImages: wrapped, fullImages: full)
    }

    @available(macOS 14.0, *)
    /// - Parameters:
    ///   - maxEdge: cap on the longest edge, in pixels, or nil for no cap.
    ///   - pixelScale: pixels per point to capture at. ScreenCaptureKit sizes
    ///     are in pixels while `window.frame` is in points, so capturing at 1
    ///     yields a non-Retina image — which reads as blur anywhere it is drawn
    ///     near its own size on a Retina display.
    private static func screenshot(
        of window: SCWindow,
        maxEdge: CGFloat? = maxThumbnailEdge,
        pixelScale: CGFloat = 1
    ) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()

        // Captured at thumbnail size, not window size.
        //
        // These are only ever drawn a couple of hundred points wide, but they
        // used to be captured at the window's full dimensions — so a chooser
        // showing 26 of them made SwiftUI downscale 26 full-size images on every
        // render pass. Measured at ~280ms of blocked main thread for one pane.
        // Scaling once here, on the capture task, costs nothing extra: the
        // compositor is doing it either way.
        let longestEdge = max(window.frame.width, window.frame.height)
        let fit: CGFloat = {
            guard let maxEdge, longestEdge > maxEdge else { return 1 }
            return maxEdge / longestEdge
        }()
        config.width = max(1, Int(window.frame.width * fit * pixelScale))
        config.height = max(1, Int(window.frame.height * fit * pixelScale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
    }

    private func publish(
        state newState: State,
        thumbnails newThumbnails: [CGWindowID: CGImage],
        nsImages newImages: [CGWindowID: NSImage],
        fullImages newFullImages: [CGWindowID: NSImage]
    ) async {
        await MainActor.run {
            let changed = self.state != newState
            self.state = newState
            self.thumbnails = newThumbnails
            self.nsImages = newImages
            self.fullImages = newFullImages
            if changed { self.onStateChange?(newState) }
            self.onUpdate?()
        }
    }
}

// MARK: - CGImage → NSImage convenience

extension WindowThumbnailCache {
    /// Return a thumbnail as NSImage, or nil if not cached.
    ///
    /// A dictionary lookup: the wrapping was done when the image was captured.
    public func nsImage(for windowID: CGWindowID) -> NSImage? {
        nsImages[windowID]
    }
}
