import Foundation
import CoreFoundation
import os.log

/// Instrumentation for tracking down UI stalls.
///
/// Two things here. `MainThreadStallDetector` watches the main run loop and
/// reports any single iteration that takes long enough to be seen as a pause —
/// it does not care what caused it, which makes it the right thing to start
/// with. `RenderProbe` then times individual view bodies so the stall can be
/// attributed to one.
///
/// Both are compiled in but idle unless started, and both report through
/// `os_log`, so nothing touches the filesystem on a hot path.
enum RenderProbe {

    static let log = Logger(subsystem: "com.windowthing", category: "render")

    /// Off unless the app is launched with `--probe-render`.
    ///
    /// The probes sit inside view bodies that run dozens of times per pass, and
    /// the watchdog pings the main queue every 10ms. Neither is expensive, but
    /// neither should be paid for in normal use — an instrument that changes
    /// what it measures is not much of an instrument.
    static let isEnabled = CommandLine.arguments.contains("--probe-render")

    /// Bodies faster than this are not worth a line in the log.
    static var thresholdMs: Double = 2

    /// Time a view body (or any synchronous block) and report if it is slow.
    @inline(never)
    static func measure<T>(_ label: String, _ work: () -> T) -> T {
        guard isEnabled else { return work() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = work()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if ms >= thresholdMs {
            let text = String(format: "%.1f", ms)
            log.info("\(label, privacy: .public) body \(text, privacy: .public)ms")
        }
        return result
    }

    // MARK: - Breadcrumbs

    private static let crumbLock = NSLock()
    private static var _lastBreadcrumb = "none"
    private static var _lastBreadcrumbAt: CFAbsoluteTime = 0

    /// Record what the main thread is about to do. Deliberately trivial — a
    /// string store — so it can sit on paths that run constantly.
    static func breadcrumb(_ label: String) {
        guard isEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        crumbLock.lock()
        _lastBreadcrumb = label
        _lastBreadcrumbAt = now
        crumbLock.unlock()
    }

    /// The last breadcrumb *and how old it is*.
    ///
    /// The age is the point. Breadcrumbs are never cleared, so a stall with no
    /// view work in it still reports whichever body ran last — possibly seconds
    /// earlier and entirely unrelated. Without the age that reads as a
    /// confident attribution to the wrong place, which is worse than no
    /// attribution at all. A crumb a few ms old was plausibly the cause; one
    /// several seconds old says the stall happened somewhere uninstrumented.
    static var lastBreadcrumb: (label: String, ageMs: Double) {
        crumbLock.lock()
        defer { crumbLock.unlock() }
        guard _lastBreadcrumbAt > 0 else { return (_lastBreadcrumb, -1) }
        return (_lastBreadcrumb, (CFAbsoluteTimeGetCurrent() - _lastBreadcrumbAt) * 1000)
    }

    /// Record a character landing in a text field.
    ///
    /// The interface driver types at a fixed interval, so the gaps between
    /// these lines say directly whether keystrokes are being dropped and how
    /// that lines up with the stalls reported below.
    static func keystroke(_ field: String, value: String) {
        guard isEnabled else { return }
        log.info("keystroke \(field, privacy: .public) -> \(value.count, privacy: .public) chars: '\(value, privacy: .public)'")
    }

    // MARK: - Counting

    private static let countLock = NSLock()
    private static var counts: [String: Int] = [:]

    /// Count how often something is built, without a line per occurrence.
    /// Useful for views that are individually cheap but built in bulk.
    static func tally(_ label: String) {
        guard isEnabled else { return }
        countLock.lock()
        counts[label, default: 0] += 1
        countLock.unlock()
    }

    /// Report and reset the tallies.
    ///
    /// `always` matters when reporting a stall: "no view bodies were built" is
    /// itself the finding, since it rules out rendering as the cause. Staying
    /// silent there would leave the stall looking unexplained rather than
    /// explained-by-elimination.
    static func flushTallies(_ context: String, always: Bool = false) {
        countLock.lock()
        let snapshot = counts
        counts.removeAll()
        countLock.unlock()

        if snapshot.isEmpty {
            if always {
                log.info("\(context, privacy: .public): no view bodies built")
            }
            return
        }
        let summary = snapshot
            .sorted { $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        log.info("\(context, privacy: .public): \(summary, privacy: .public)")
    }
}

/// Reports main run loop iterations that take long enough to feel like a pause.
///
/// The run loop enters `beforeSources` when it starts doing work and
/// `beforeWaiting` when it has finished and is about to sleep. The gap is
/// everything that happened on the main thread in that turn — event handling,
/// SwiftUI layout and rendering, timers — so a stall shows up here no matter
/// which of those caused it.
final class MainThreadStallDetector {

    static let shared = MainThreadStallDetector()

    private var observer: CFRunLoopObserver?
    private var iterationStart: CFAbsoluteTime = 0
    private let thresholdMs: Double

    init(thresholdMs: Double = 20) {
        self.thresholdMs = thresholdMs
    }

    func start() {
        guard RenderProbe.isEnabled, observer == nil else { return }

        let activities = CFRunLoopActivity.beforeSources.rawValue
            | CFRunLoopActivity.beforeWaiting.rawValue

        observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, activities, true, 0
        ) { [weak self] _, activity in
            guard let self else { return }
            switch activity {
            case .beforeSources:
                self.iterationStart = CFAbsoluteTimeGetCurrent()
            case .beforeWaiting:
                guard self.iterationStart > 0 else { return }
                let ms = (CFAbsoluteTimeGetCurrent() - self.iterationStart) * 1000
                self.iterationStart = 0
                if ms >= self.thresholdMs {
                    let text = String(format: "%.1f", ms)
                    RenderProbe.log.warning("main thread stalled \(text, privacy: .public)ms")
                    RenderProbe.flushTallies("during stall", always: true)
                }
            default:
                break
            }
        }

        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        observer = nil
    }
}

/// Detects main-thread stalls from *outside* the main thread.
///
/// `MainThreadStallDetector` measures the run loop from within it, so it only
/// sees iterations of the modes it observes and cannot report a stall while one
/// is still happening. This instead pings the main queue from a background
/// thread and times how long the reply takes. Main-queue blocks are serviced in
/// common modes, which includes event tracking, so a pause during a menu or a
/// drag shows up here even though the run loop observer misses it.
///
/// It also reports the last breadcrumb the main thread passed and what views
/// were being built, which is usually enough to say where the time went.
final class MainThreadWatchdog {

    static let shared = MainThreadWatchdog()

    /// Pauses at or above this are worth reporting.
    private let thresholdMs: Double
    /// How often to ping. Frequent enough to catch a stall while it is running,
    /// cheap enough to leave on: a semaphore signal on an idle main thread.
    private let sampleIntervalMs: UInt32

    private var thread: Thread?
    private var running = false

    init(thresholdMs: Double = 20, sampleIntervalMs: UInt32 = 10) {
        self.thresholdMs = thresholdMs
        self.sampleIntervalMs = sampleIntervalMs
    }

    func start() {
        guard RenderProbe.isEnabled, thread == nil else { return }
        running = true

        let thread = Thread { [weak self] in
            guard let self else { return }
            while self.running {
                let semaphore = DispatchSemaphore(value: 0)
                let sent = CFAbsoluteTimeGetCurrent()

                DispatchQueue.main.async { semaphore.signal() }

                let deadline = DispatchTime.now() + .milliseconds(Int(self.thresholdMs))
                if semaphore.wait(timeout: deadline) == .timedOut {
                    // Still blocked. Wait it out so the true duration is known.
                    semaphore.wait()
                    let ms = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                    let text = String(format: "%.1f", ms)
                    let crumb = RenderProbe.lastBreadcrumb
                    let age = String(format: "%.0f", crumb.ageMs)
                    RenderProbe.log.warning(
                        "main thread blocked \(text, privacy: .public)ms (last breadcrumb: \(crumb.label, privacy: .public), \(age, privacy: .public)ms ago)")
                    RenderProbe.flushTallies("while blocked", always: true)
                }

                usleep(self.sampleIntervalMs * 1000)
            }
        }
        thread.name = "com.windowthing.watchdog"
        thread.qualityOfService = .utility
        thread.start()
        self.thread = thread
    }

    func stop() {
        running = false
        thread = nil
    }
}
