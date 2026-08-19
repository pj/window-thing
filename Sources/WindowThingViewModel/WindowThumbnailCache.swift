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
            await publish(state: .degraded, thumbnails: [:])
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

        await publish(state: .polling, thumbnails: captured)
    }

    @available(macOS 14.0, *)
    private static func screenshot(of window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        // Point-size rather than backing-store pixels: these are thumbnails, and
        // capturing Retina-resolution copies of every window every few seconds
        // is a lot of memory for no visible benefit. Matches the old capture's
        // .nominalResolution.
        config.width = max(1, Int(window.frame.width))
        config.height = max(1, Int(window.frame.height))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
    }

    private func publish(state newState: State, thumbnails newThumbnails: [CGWindowID: CGImage]) async {
        await MainActor.run {
            let changed = self.state != newState
            self.state = newState
            self.thumbnails = newThumbnails
            if changed { self.onStateChange?(newState) }
            self.onUpdate?()
        }
    }
}

// MARK: - CGImage → NSImage convenience

extension WindowThumbnailCache {
    /// Return a thumbnail as NSImage, or nil if not cached.
    public func nsImage(for windowID: CGWindowID) -> NSImage? {
        guard let cgImage = thumbnails[windowID] else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
