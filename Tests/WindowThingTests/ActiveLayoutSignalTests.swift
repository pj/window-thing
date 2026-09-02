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
            manager.onCurrentLayoutChange = { announced.append($0?.name) }

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
            manager.onCurrentLayoutChange = { announced.append($0?.name) }

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
            manager.onCurrentLayoutChange = { _ in count += 1 }

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
            manager.onCurrentLayoutChange = { announced.append($0?.name) }

            one.name = "Renamed"
            manager.updateLayout(one)

            #expect(announced == ["Renamed"])
            #expect(manager.currentLayout?.name == "Renamed")
        }
    }

    @Test("Nothing is announced before a layout is applied")
    func silentUntilApplied() {
        withManager { manager in
            var count = 0
            manager.onCurrentLayoutChange = { _ in count += 1 }

            manager.setLayouts([layout("One"), layout("Two")])

            // Loading layouts is not applying one. The menu bar shows its
            // generic mark until something actually takes effect.
            #expect(count == 0)
            #expect(manager.currentLayout == nil)
        }
    }
}
