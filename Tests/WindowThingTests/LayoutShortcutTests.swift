import Testing
import Foundation
@testable import WindowThingCore

/// A layout's shortcut: one keystroke, described and registered the same way
/// everywhere.
@Suite("Layout shortcuts")
struct LayoutShortcutTests {

    private func layout(_ name: String, key: String? = nil) -> Layout {
        Layout(name: name, quickKey: key,
               screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()]))
    }

    @Test("A layout's shortcut is Control-Option plus its key")
    func describesWithTheSharedPrefix() {
        #expect(LayoutShortcuts.describe(layout("Fullscreen", key: "z")) == "⌃⌥Z")
        #expect(LayoutShortcuts.describe(layout("Half Split", key: "1")) == "⌃⌥1")
    }

    @Test("A layout with no key has no shortcut")
    func noKeyMeansNoShortcut() {
        // Not a positional fallback. Numbering by position made the shortcut
        // move when layouts were reordered, and left no way to say "none".
        #expect(LayoutShortcuts.describe(layout("Unbound")) == nil)
        #expect(LayoutShortcuts.describe(layout("Empty string", key: "")) == nil)
    }

    @Test("A new layout starts with no shortcut")
    func newLayoutsAreUnbound() {
        let fresh = Layout(name: "New",
                           screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()]))
        #expect(fresh.quickKey == nil)
        #expect(LayoutShortcuts.describe(fresh) == nil)
    }

    @Test("Case does not matter")
    func keysAreCaseInsensitive() {
        #expect(LayoutShortcuts.normalised(layout("Upper", key: "Z")) == "z")
        #expect(LayoutShortcuts.describe(layout("Upper", key: "Z")) == "⌃⌥Z")
    }

    @Test("A key the app already owns is reported rather than silently ignored")
    func conflictsAreReported() {
        // ⌃⌥W opens the surface and ⌃⌥M moves a window. A layout asking for
        // those cannot register, and a shortcut that quietly does nothing is
        // worse than one that is called out.
        let clash = layout("Wide", key: "w")
        let fine = layout("Thirds", key: "2")
        let conflicts = LayoutShortcuts.conflicting(in: [clash, fine])
        #expect(conflicts.map(\.id) == [clash.id])
    }

    @Test("Layouts that merely share a key are not reported as app conflicts")
    func duplicatesAreNotAppConflicts() {
        // Two layouts wanting the same key is a different problem: whichever
        // registers first wins, and neither is fighting the application.
        let a = layout("A", key: "a")
        let b = layout("B", key: "a")
        #expect(LayoutShortcuts.conflicting(in: [a, b]).isEmpty)
    }
}
