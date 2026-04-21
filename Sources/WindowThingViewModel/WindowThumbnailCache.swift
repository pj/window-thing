import Foundation
import CoreGraphics
import AppKit
import WindowThingCore

// MARK: - WindowThumbnailCache

/// Background service that periodically captures and caches screenshot thumbnails
/// for all visible windows using CGWindowListCreateImage.
///
/// Callers fall back to app icons when Screen Recording permission is not granted
/// (CGPreflightScreenCaptureAccess() returns false) — the cache simply stays empty.
public final class WindowThumbnailCache: @unchecked Sendable {

    // MARK: - State

    public enum State: Equatable {
        case stopped
        case polling
        /// Screen Recording permission was revoked after start(); thumbnails are cleared.
        case degraded
    }

    public private(set) var state: State = .stopped

    /// Current cache snapshot. Key = CGWindowID (the AX window's on-screen ID).
    public private(set) var thumbnails: [CGWindowID: CGImage] = [:]

    /// Called on the main queue after each successful refresh.
    public var onUpdate: (() -> Void)?

    /// Capture interval in seconds. Clamped to [2, 5] at start time.
    public var captureInterval: TimeInterval

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.windowthing.thumbnail-cache", qos: .utility)

    // MARK: - Singleton

    public static let shared = WindowThumbnailCache()

    public init(captureInterval: TimeInterval = 3.0) {
        self.captureInterval = captureInterval
    }

    // MARK: - Lifecycle

    public func start() {
        guard state == .stopped || state == .degraded else { return }

        guard CGPreflightScreenCaptureAccess() else {
            state = .degraded
            thumbnails = [:]
            return
        }

        state = .polling
        scheduleTimer()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        state = .stopped
    }

    /// Update the capture interval and restart the timer if currently polling.
    public func updateInterval(_ interval: TimeInterval) {
        captureInterval = max(2.0, min(5.0, interval))
        if state == .polling {
            timer?.cancel()
            scheduleTimer()
        }
    }

    // MARK: - Capture

    private func scheduleTimer() {
        let effectiveInterval = max(2.0, min(5.0, captureInterval))
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + effectiveInterval, repeating: effectiveInterval)
        t.setEventHandler { [weak self] in self?.capture() }
        t.resume()
        timer = t
    }

    private func capture() {
        guard CGPreflightScreenCaptureAccess() else {
            DispatchQueue.main.async { [weak self] in
                self?.state = .degraded
                self?.thumbnails = [:]
                self?.onUpdate?()
            }
            return
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        var captured: [CGWindowID: CGImage] = [:]

        for info in windowInfos {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,   // normal application windows only
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = boundsDict["Width"], let h = boundsDict["Height"],
                  w > 50, h > 50 else { continue }

            let cgBounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: w,
                height: h
            )

            let image = CGWindowListCreateImage(
                cgBounds,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .nominalResolution]
            )
            if let image {
                captured[windowID] = image
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.thumbnails = captured
            self?.onUpdate?()
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
