import Testing
import Foundation
import CoreGraphics
@testable import WindowThingCore

/// Frame writes are several Accessibility round trips each, so arranging a few
/// dozen windows takes longer than the half-second reconcile tick. What happens
/// when the two overlap decides whether a layout lands or visibly stops halfway.
@Suite("Interrupting a layout apply")
@MainActor
struct ApplyInterruptionTests {

    private func windows(_ count: Int) -> [Window] {
        (0 ..< count).map {
            Window(
                id: CGWindowID(100 + $0),
                title: "Window \($0)",
                application: "App\($0)",
                bundleId: "com.example.app\($0)",
                frame: WindowFrame(x: 0, y: 0, width: 400, height: 300),
                pid: pid_t(500 + $0)
            )
        }
    }

    private func makeManager(windowCount: Int, delay: TimeInterval)
        -> (LayoutManager, MockWindowManager) {
        let wm = MockWindowManager()
        wm.displays = [
            Display(id: 1, name: "Built-in",
                    frame: WindowFrame(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        ]
        wm.windows = windows(windowCount)
        wm.frameWriteDelay = delay
        let manager = LayoutManager(windowManager: wm, userDefaults: EphemeralApplyDefaults())
        return (manager, wm)
    }

    private func layout(_ name: String) -> Layout {
        Layout(name: name, screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()]))
    }

    /// Collects how each pass ended.
    ///
    /// Counting frame writes instead does not work, and the first version of
    /// these tests made exactly that mistake: a reconcile that cancels an apply
    /// goes on to write the same frames itself, so the total comes out the same
    /// either way and the test passes with the bug present. What distinguishes
    /// them is whether any pass was cut short.
    private func recordingOutcomes(_ manager: LayoutManager) -> Outcomes {
        let outcomes = Outcomes()
        manager.onApplyFinished = { moved, wanted, cancelled in
            outcomes.record(moved: moved, wanted: wanted, cancelled: cancelled)
        }
        return outcomes
    }

    @Test("A reconcile does not cut short the layout the user asked for")
    func reconcileDoesNotInterruptAnApply() {
        // The reported bug: switching layout moved some windows and stopped.
        // The apply was still running when the reconcile timer fired, and the
        // reconcile cancelled it — measured on a real machine at 10 of 27.
        let (manager, _) = makeManager(windowCount: 12, delay: 0.02)
        let one = layout("One")
        manager.setLayouts([one])
        let outcomes = recordingOutcomes(manager)

        manager.applyLayout(one)
        // The tick that used to land mid-apply.
        manager.reconcileCurrentLayout()
        manager.waitForPendingApply()

        #expect(!outcomes.anyCancelled, "the apply should have been left to finish")
        #expect(outcomes.completedAll(12), "all twelve windows should have been placed by one pass")
    }

    @Test("Several reconciles in a row still do not cut it short")
    func repeatedReconcilesDoNotInterrupt() {
        // The timer does not fire once. A long apply overlaps several ticks, and
        // any one of them cancelling is enough to leave the screen half-done.
        let (manager, _) = makeManager(windowCount: 12, delay: 0.02)
        let one = layout("One")
        manager.setLayouts([one])
        let outcomes = recordingOutcomes(manager)

        manager.applyLayout(one)
        for _ in 0 ..< 5 { manager.reconcileCurrentLayout() }
        manager.waitForPendingApply()

        #expect(!outcomes.anyCancelled)
        #expect(outcomes.completedAll(12))
    }

    @Test("Choosing another layout does interrupt the one being applied")
    func explicitApplyStillInterrupts() {
        // The other half of the rule. A second choice is the user changing their
        // mind, so the newer instruction wins and the older one stops — otherwise
        // the screen finishes arranging itself into a layout nobody asked for.
        let (manager, _) = makeManager(windowCount: 40, delay: 0.02)
        let one = layout("One")
        let two = layout("Two")
        manager.setLayouts([one, two])
        let outcomes = recordingOutcomes(manager)

        manager.applyLayout(one)
        manager.applyLayout(two)
        manager.waitForPendingApply()

        #expect(manager.currentLayout?.name == "Two")
        // Not "a pass reported itself cancelled": an item cancelled before the
        // queue reaches it never runs, so it reports nothing at all, and
        // asserting on the cancellation made this flaky. What holds either way
        // is that only one of the two passes ran to completion.
        #expect(outcomes.completedPasses == 1,
                "exactly one of the two applies should have finished")
    }

    @Test("A pass cancelled before it starts still frees the queue")
    func cancelledBeforeStartDoesNotLeak() {
        // A work item cancelled before the queue reaches it never runs its body.
        // Book-keeping done inside the body is therefore skipped, and a count of
        // passes in flight only ever rises — after which every reconcile stands
        // down for work that finished long ago and the layout quietly stops
        // being maintained. This is the test for that, not for the cancelling.
        // The first pass is made slow on purpose so the ones fired behind it sit
        // in the queue and are cancelled there, never running. A fast first pass
        // lets every item start before the next cancel arrives, which is the
        // state this is specifically not about — checked by reintroducing the
        // bug, where a fast version of this test still passed.
        let (manager, wm) = makeManager(windowCount: 20, delay: 0.05)
        let one = layout("One")
        let two = layout("Two")
        manager.setLayouts([one, two])

        manager.applyLayout(one)
        for _ in 0 ..< 10 { manager.applyLayout(two) }
        manager.waitForPendingApply()
        // `notify` is submitted when an item ends, so it can land just after the
        // queue barrier above returns.
        Thread.sleep(forTimeInterval: 0.3)

        // If the count leaked, this reconcile is skipped and nothing is written.
        wm.windows[0] = Window(
            id: wm.windows[0].id, title: wm.windows[0].title,
            application: wm.windows[0].application, bundleId: wm.windows[0].bundleId,
            frame: WindowFrame(x: 900, y: 700, width: 200, height: 200),
            pid: wm.windows[0].pid)
        let before = wm.setWindowFrameCalls.count

        manager.reconcileCurrentLayout()
        manager.waitForPendingApply()

        #expect(wm.setWindowFrameCalls.count > before,
                "reconciliation should still happen after a run of superseded applies")
    }

    @Test("A reconcile with nothing in flight still runs")
    func reconcileRunsWhenIdle() {
        // Skipping a tick is only correct while something better is running.
        // An idle reconcile is the mechanism that pulls a dragged window back.
        let (manager, wm) = makeManager(windowCount: 4, delay: 0)
        let one = layout("One")
        manager.setLayouts([one])

        manager.applyLayout(one)
        manager.waitForPendingApply()
        let afterApply = wm.setWindowFrameCalls.count

        // Move one away, as a person dragging it would.
        wm.windows[0] = Window(
            id: wm.windows[0].id, title: wm.windows[0].title,
            application: wm.windows[0].application, bundleId: wm.windows[0].bundleId,
            frame: WindowFrame(x: 900, y: 700, width: 200, height: 200),
            pid: wm.windows[0].pid)

        manager.reconcileCurrentLayout()
        manager.waitForPendingApply()

        #expect(wm.setWindowFrameCalls.count > afterApply,
                "the stray window should have been pulled back")
    }
}

/// Thread-safe tally of how passes ended; reports arrive on the apply queue.
private final class Outcomes {
    private let lock = NSLock()
    private var reports: [(moved: Int, wanted: Int, cancelled: Bool)] = []

    func record(moved: Int, wanted: Int, cancelled: Bool) {
        lock.lock(); reports.append((moved, wanted, cancelled)); lock.unlock()
    }

    var anyCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return reports.contains { $0.cancelled }
    }

    func completedAll(_ count: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reports.contains { !$0.cancelled && $0.moved == count && $0.wanted == count }
    }

    var completedPasses: Int {
        lock.lock(); defer { lock.unlock() }
        return reports.count { !$0.cancelled && $0.moved == $0.wanted }
    }
}

/// Defaults that never reach disk: applying a layout records `lastUsedLayoutId`,
/// and the standard suite belongs to whoever is running the tests.
private final class EphemeralApplyDefaults: UserDefaults {
    private var storage: [String: Any] = [:]
    override func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }
    override func object(forKey defaultName: String) -> Any? { storage[defaultName] }
    override func string(forKey defaultName: String) -> String? { storage[defaultName] as? String }
    override func removeObject(forKey defaultName: String) { storage.removeValue(forKey: defaultName) }
}
