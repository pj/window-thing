import Testing
import Foundation
@testable import WindowThingCore

/// The menubar draws the applied layout and ticks it in the menu, and every way
/// of applying one — the menu, a global hotkey, the layout surface, a reconcile
/// after the displays change — goes through the manager. So the signal it emits
/// is what those all rely on.
///
/// Pinned to the main thread because the signal promises delivery there: off it,
/// the manager hops through the main queue and the callback would land after the
/// test had finished. Without this the suite passes or fails depending on which
/// thread the runner happened to use.
/// `UserDefaults` that keeps everything in memory, so a test writing a
/// preference leaves nothing behind on the machine running it.
private final class EphemeralDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    override func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    override func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}

@Suite("Active layout signal")
@MainActor
struct ActiveLayoutSignalTests {

    /// Run a test against a manager backed by defaults that never reach disk.
    ///
    /// Applying a layout records `lastUsedLayoutId`, so these cannot use the
    /// standard suite — that is the user's own. A named suite is no good either:
    /// `UserDefaults(suiteName:)` writes a real plist into ~/Library/Preferences,
    /// and removing the domain afterwards does not reliably take the file with
    /// it, because cfprefsd writes it back. A fresh suite name per run therefore
    /// left a growing pile of plists on the developer's machine.
    private func withManager(_ body: (LayoutManager) -> Void) {
        let wm = MockWindowManager()
        wm.displays = [
            Display(id: 1, name: "Built-in", frame: WindowFrame(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        ]
        body(LayoutManager(windowManager: wm, userDefaults: EphemeralDefaults()))
    }

    private func layout(_ name: String) -> Layout {
        Layout(name: name, screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()]))
    }

    @Test("Applying a layout announces it")
    func announcesOnApply() {
        withManager { manager in
            let one = layout("One")
            manager.setLayouts([one])

            var announced: [String?] = []
            manager.onActiveLayoutChange = { announced.append($0?.name) }

            manager.applyLayout(one)

            #expect(announced == ["One"])
        }
    }

    @Test("Switching layouts announces the new one")
    func announcesOnSwitch() {
        withManager { manager in
            let one = layout("One")
            let two = layout("Two")
            manager.setLayouts([one, two])

            var announced: [String?] = []
            manager.onActiveLayoutChange = { announced.append($0?.name) }

            manager.applyLayout(one)
            manager.applyLayout(two)

            #expect(announced == ["One", "Two"])
        }
    }

    @Test("Re-applying the same layout still announces it")
    func announcesOnReapply() {
        // Not deduplicated on identity: a layout edited while it is applied
        // keeps its id and loses its shape, and the icon draws the shape. A
        // signal that only fired on a change of identity would leave the menu
        // bar showing the layout as it used to look.
        withManager { manager in
            let one = layout("One")
            manager.setLayouts([one])

            var count = 0
            manager.onActiveLayoutChange = { _ in count += 1 }

            manager.applyLayout(one)
            manager.applyLayout(one)

            #expect(count == 2)
        }
    }

    @Test("A layout renamed while applied announces its new name")
    func announcesARename() {
        withManager { manager in
            var one = layout("One")
            manager.setLayouts([one])
            manager.applyLayout(one)

            var announced: [String?] = []
            manager.onActiveLayoutChange = { announced.append($0?.name) }

            one.name = "Renamed"
            manager.updateLayout(one)

            #expect(announced == ["Renamed"])
            #expect(manager.currentLayout?.name == "Renamed")
        }
    }

    @Test("With nothing ever applied there is no active layout")
    func noneUntilEverApplied() {
        withManager { manager in
            manager.setLayouts([layout("One"), layout("Two")])

            // A first run has nothing to show, and the menu bar falls back to
            // its generic mark rather than picking a layout arbitrarily.
            #expect(manager.activeLayout == nil)
        }
    }

    @Test("A relaunched app shows the layout last applied")
    func survivesRelaunch() {
        // The bug this exists for: nothing is re-applied at startup, so
        // `currentLayout` is nil however many times a layout has been applied
        // before. Reading only that left the menu bar showing its generic mark
        // after every restart, which is exactly what a user sees.
        // One store shared by both managers, standing in for the defaults
        // surviving a quit. In memory, so the test leaves no plist behind.
        let defaults = EphemeralDefaults()

        let one = layout("One")
        let two = layout("Two")
        var config = AppConfig.default
        config.layouts = [one, two]

        let first = LayoutManager(windowManager: MockWindowManager(), userDefaults: defaults)
        first.setLayouts([one, two])
        first.applyLayout(two)

        // A second manager over the same defaults stands in for a relaunch.
        let relaunched = LayoutManager(windowManager: MockWindowManager(), userDefaults: defaults)
        relaunched.loadLayouts(from: config)

        #expect(relaunched.currentLayout == nil, "nothing is applied at startup")
        #expect(relaunched.activeLayout?.name == "Two", "but the last one used is still what is in effect")
    }

    @Test("Restoring the last used layout announces it")
    func announcesOnRestore() {
        let defaults = EphemeralDefaults()

        let one = layout("One")
        var config = AppConfig.default
        config.layouts = [one]

        let first = LayoutManager(windowManager: MockWindowManager(), userDefaults: defaults)
        first.setLayouts([one])
        first.applyLayout(one)

        let relaunched = LayoutManager(windowManager: MockWindowManager(), userDefaults: defaults)
        var announced: [String?] = []
        relaunched.onActiveLayoutChange = { announced.append($0?.name) }
        relaunched.loadLayouts(from: config)

        #expect(announced == ["One"])
    }

    @Test("Applying a layout announces it once, not twice")
    func announcesOnceOnApply() {
        // `applyLayout` writes both `currentLayout` and `lastUsedLayout`, and
        // both can announce. The second must stay quiet or every apply
        // redraws the menubar twice.
        withManager { manager in
            let one = layout("One")
            manager.setLayouts([one])

            var count = 0
            manager.onActiveLayoutChange = { _ in count += 1 }
            manager.applyLayout(one)

            #expect(count == 1)
        }
    }
}
