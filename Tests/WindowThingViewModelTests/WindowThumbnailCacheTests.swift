import Testing
import Foundation
import CoreGraphics
@testable import WindowThingViewModel

/// The capture itself needs a real ScreenCaptureKit session and Screen Recording
/// permission, so it can't be unit tested. These cover the decisions made around
/// it, which is where the behaviour actually lives.
@Suite("Window thumbnail cache")
struct WindowThumbnailCacheTests {

    // MARK: - Capture interval

    @Test("Interval is clamped into the supported range")
    func clampsInterval() {
        // Too frequent is a real cost now: each tick is N ScreenCaptureKit
        // screenshots, not one cheap CoreGraphics call.
        #expect(WindowThumbnailCache.clamp(0.1) == 2.0)
        #expect(WindowThumbnailCache.clamp(1.9) == 2.0)
        #expect(WindowThumbnailCache.clamp(3.0) == 3.0)
        #expect(WindowThumbnailCache.clamp(60.0) == 5.0)
    }

    @Test("updateInterval stores the clamped value, not the raw one")
    func updateIntervalClamps() {
        let cache = WindowThumbnailCache(captureInterval: 3.0)

        cache.updateInterval(0.5)
        #expect(cache.captureInterval == 2.0)

        cache.updateInterval(4.0)
        #expect(cache.captureInterval == 4.0)
    }

    // MARK: - Which windows are worth capturing

    @Test("Normal application windows are captured")
    func capturesNormalWindows() {
        #expect(WindowThumbnailCache.shouldCapture(width: 800, height: 600, layer: 0))
    }

    @Test("Chrome above the normal window layer is skipped")
    func skipsNonZeroLayers() {
        // Layer 0 is ordinary app windows; menus, the Dock and status items sit
        // above it and would be noise in a window picker.
        #expect(!WindowThumbnailCache.shouldCapture(width: 800, height: 600, layer: 25))
        #expect(!WindowThumbnailCache.shouldCapture(width: 800, height: 600, layer: -1))
    }

    @Test("Windows too small to read as a thumbnail are skipped")
    func skipsTinyWindows() {
        #expect(!WindowThumbnailCache.shouldCapture(width: 20, height: 600, layer: 0))
        #expect(!WindowThumbnailCache.shouldCapture(width: 800, height: 20, layer: 0))
        #expect(!WindowThumbnailCache.shouldCapture(width: 50, height: 50, layer: 0))
        // Just over the threshold still counts.
        #expect(WindowThumbnailCache.shouldCapture(width: 51, height: 51, layer: 0))
    }

    // MARK: - Lifecycle

    @Test("A fresh cache is stopped and empty")
    func startsStopped() {
        let cache = WindowThumbnailCache()

        #expect(cache.state == .stopped)
        #expect(cache.thumbnails.isEmpty)
        #expect(cache.nsImage(for: 1) == nil)
    }

    @Test("stop() returns the cache to the stopped state")
    func stopResets() {
        let cache = WindowThumbnailCache()
        cache.start()
        cache.stop()

        #expect(cache.state == .stopped)
    }

    // start() is called from a window-refresh callback that fires constantly.
    // The guard used to be on `state`, so once capture degraded for want of
    // permission every callback spawned another loop.
    @Test("Repeated start() calls do not stack up capture loops",
          .enabled(if: ProcessInfo.processInfo.isOperatingSystemAtLeast(
              .init(majorVersion: 14, minorVersion: 0, patchVersion: 0))))
    func startIsIdempotent() {
        let cache = WindowThumbnailCache()
        cache.start()
        for _ in 0 ..< 20 { cache.start() }

        #expect(cache.pollLoopStarts == 1, "start() spawned an extra capture loop")
        cache.stop()

        // Stopping releases the loop, so it can legitimately be started again.
        cache.start()
        #expect(cache.pollLoopStarts == 2)
        cache.stop()
    }

    @Test("On macOS 13 the cache reports unsupported rather than pretending to poll")
    func reportsUnsupportedBelowSonoma() {
        // SCScreenshotManager is macOS 14+. Below that there is no capture path
        // at all, and callers need to know to show app icons instead.
        let cache = WindowThumbnailCache()
        cache.start()

        if #available(macOS 14.0, *) {
            #expect(cache.state != .unsupported)
        } else {
            #expect(cache.state == .unsupported)
            #expect(cache.thumbnails.isEmpty)
        }

        cache.stop()
    }
}

/// Thumbnails are capped in size so a paneful of them is cheap to draw, but a
/// pane-filling preview is drawn far larger and would show the downscaling. Those
/// few windows are captured at native size as well.
@Suite("Full-resolution requests")
struct WindowThumbnailFullResolutionTests {

    @Test("A window is only captured at native size while something asks")
    func requestsAreTracked() {
        let cache = WindowThumbnailCache()
        #expect(cache.fullResolutionRequestCount == 0)

        cache.requestFullResolution(for: 1)
        #expect(cache.fullResolutionRequestCount == 1)

        cache.releaseFullResolution(for: 1)
        #expect(cache.fullResolutionRequestCount == 0)
    }

    @Test("Requests are counted, so overlapping views don't cancel each other")
    func requestsAreCounted() {
        // This was a set, and it was wrong. SwiftUI rebuilds a tile by bringing
        // the replacement on before taking the old one off, so the sequence is
        // request(new), release(old) — with a set that left no request at all
        // while a tile was still on screen, and the preview visibly dropped back
        // to the capped thumbnail a moment after appearing.
        let cache = WindowThumbnailCache()

        cache.requestFullResolution(for: 7)   // tile appears
        cache.requestFullResolution(for: 7)   // replacement appears
        cache.releaseFullResolution(for: 7)   // original goes away

        #expect(cache.fullResolutionRequestCount == 1, "a live tile lost its request")

        cache.releaseFullResolution(for: 7)   // replacement goes away too
        #expect(cache.fullResolutionRequestCount == 0)
    }

    @Test("Releasing more often than requesting doesn't go negative")
    func unbalancedReleaseIsHarmless() {
        let cache = WindowThumbnailCache()

        cache.requestFullResolution(for: 3)
        cache.releaseFullResolution(for: 3)
        cache.releaseFullResolution(for: 3)
        #expect(cache.fullResolutionRequestCount == 0)

        // And the window can still be requested again afterwards.
        cache.requestFullResolution(for: 3)
        #expect(cache.fullResolutionRequestCount == 1)
    }

    @Test("Windows are requested independently")
    func requestsArePerWindow() {
        let cache = WindowThumbnailCache()

        cache.requestFullResolution(for: 1)
        cache.requestFullResolution(for: 2)
        cache.releaseFullResolution(for: 1)

        #expect(cache.fullResolutionRequestCount == 1)
    }

    @Test("No native-size image until a capture has produced one")
    func noImageBeforeCapture() {
        let cache = WindowThumbnailCache()
        cache.requestFullResolution(for: 1)

        // Callers fall back to the ordinary thumbnail meanwhile, so a tile is
        // never blank while waiting for the next capture.
        #expect(cache.fullImage(for: 1) == nil)
    }
}
