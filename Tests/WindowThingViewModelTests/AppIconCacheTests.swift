import Testing
import AppKit
@testable import WindowThingViewModel

/// Resolving an app icon costs a Launch Services lookup and a disk read —
/// measured at about 3ms. The choosers ask for one per app per pane on every
/// render, so the only thing that matters here is how often a lookup actually
/// happens.
@Suite("App icon cache")
struct AppIconCacheTests {

    /// Termination observing is off: these are about the caching, and a test
    /// shouldn't register for workspace notifications.
    private func makeCache() -> AppIconCache {
        AppIconCache(observingTermination: false)
    }

    @Test("A bundle id is resolved once, however often it is asked for")
    func bundleIdResolvedOnce() {
        let cache = makeCache()

        for _ in 0 ..< 50 {
            _ = cache.icon(bundleId: "com.apple.finder", appName: "Finder")
        }

        #expect(cache.resolutions == 1)
    }

    @Test("A process id is resolved once")
    func pidResolvedOnce() {
        let cache = makeCache()
        let me = ProcessInfo.processInfo.processIdentifier

        for _ in 0 ..< 50 {
            _ = cache.icon(pid: me)
        }

        #expect(cache.resolutions == 1)
    }

    @Test("A failed lookup is cached too")
    func missesAreCached() {
        // Otherwise an app whose icon can't be found is re-searched at full
        // price on every pass — the worst case, not the best.
        let cache = makeCache()

        for _ in 0 ..< 20 {
            _ = cache.icon(bundleId: "com.example.nothing.here", appName: "Nothing Here At All")
        }

        // One for the bundle id, one for the name fallback, then all hits.
        #expect(cache.resolutions <= 2)
    }

    @Test("Different apps are cached separately")
    func distinctAppsResolveSeparately() {
        let cache = makeCache()

        _ = cache.icon(bundleId: "com.apple.finder", appName: "Finder")
        _ = cache.icon(bundleId: "com.apple.dt.Xcode", appName: "Xcode")
        _ = cache.icon(bundleId: "com.apple.finder", appName: "Finder")

        #expect(cache.resolutions == 2)
    }

    @Test("clear() forces a fresh lookup")
    func clearInvalidates() {
        let cache = makeCache()

        _ = cache.icon(bundleId: "com.apple.finder", appName: "Finder")
        #expect(cache.resolutions == 1)

        cache.clear()
        _ = cache.icon(bundleId: "com.apple.finder", appName: "Finder")
        #expect(cache.resolutions == 2)
    }

    @Test("forget(pid:) drops only that process")
    func forgetIsTargeted() {
        // Process ids get reused, so a dead app's entry must go — but taking the
        // whole cache with it would undo the point.
        let cache = makeCache()
        let me = ProcessInfo.processInfo.processIdentifier

        _ = cache.icon(bundleId: "com.apple.finder", appName: "Finder")
        _ = cache.icon(pid: me)
        #expect(cache.resolutions == 2)

        cache.forget(pid: me)

        _ = cache.icon(pid: me)                                        // re-resolved
        _ = cache.icon(bundleId: "com.apple.finder", appName: "Finder") // still cached
        #expect(cache.resolutions == 3)
    }
}
