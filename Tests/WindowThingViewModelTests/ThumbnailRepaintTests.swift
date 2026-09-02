import Testing
import Foundation
import CoreGraphics
@testable import WindowThingViewModel
@testable import WindowThingCore

/// Thumbnail captures land every few seconds and invalidate every tile on the
/// surface. That repaint runs on the main thread, which is also where typed
/// characters are delivered, so one landing mid-word used to swallow the
/// keystrokes typed during it — five characters of a fifteen-character name, in
/// the run that first showed this up.
// Mocks kept local to this file. Constructing an OverlayViewModel with no
// arguments would reach the real ConfigManager and the user's own config file,
// which is never what a test wants.
private class StubLayoutManager: LayoutManaging {
    var layouts: [Layout] = []
    var savedSetups: [SavedSetup] = []
    var currentLayout: Layout?
    var lastUsedLayout: Layout?
    func loadLayouts(from config: AppConfig) { layouts = config.layouts }
    func applyLayout(_ layout: Layout) {}
    func updateLayout(_ layout: Layout) {}
    func setLayouts(_ newLayouts: [Layout]) { layouts = newLayouts }
    func saveCurrentSetup(name: String) {}
    func loadSetup(_ setup: SavedSetup) {}
    func moveWindow(_ window: Window, toCellAt address: CellAddress, displays: [Display]) throws {}
    func cellAddresses(for layout: Layout, displays: [Display]) -> [IndexedCell] {
        CellIndexer.indexCells(layout: layout, displays: displays)
    }
}

private class StubWindowManager: WindowManaging {
    func getDisplays() -> [Display] { [] }
    func getWindows() -> [Window] { [] }
    func setWindowFrame(pid: pid_t, windowTitle: String?, frame: WindowFrame) -> Bool { true }
    func setWindowFrame(pid: pid_t, windowId: CGWindowID, frame: WindowFrame) -> Bool { true }
    func getFocusedApplication() -> Application? { nil }
}

private class StubConfigManager: ConfigProviding {
    var config: AppConfig = .default
    var configFilePath: URL = URL(fileURLWithPath: "/tmp/test-config.yaml")
    var setupsFilePath: URL = URL(fileURLWithPath: "/tmp/test-setups.yaml")
    func loadConfig() {}
    func saveConfig() {}
    func saveLayouts(_ layouts: [Layout]) {}
}

private func makeThumbnailTestVM(
    layouts: [Layout]
) -> (OverlayViewModel, StubLayoutManager, StubConfigManager) {
    let lm = StubLayoutManager()
    lm.layouts = layouts
    let cm = StubConfigManager()
    let vm = OverlayViewModel(
        windowManager: StubWindowManager(), layoutManager: lm, configManager: cm)
    vm.layouts = layouts
    vm.originalLayouts = layouts
    return (vm, lm, cm)
}

@Suite("Thumbnail repaints and typing")
struct ThumbnailRepaintTests {

    private func vmWithLayouts() -> OverlayViewModel {
        let (vm, _, _) = makeThumbnailTestVM(layouts: [Layout(name: "One"), Layout(name: "Two")])
        return vm
    }

    @Test("A capture landing while nothing is focused repaints straight away")
    func repaintsWhenIdle() {
        let vm = vmWithLayouts()
        let before = vm.thumbnailRevision

        vm.noteThumbnailUpdate()

        #expect(vm.thumbnailRevision == before + 1)
    }

    @Test("A capture landing during a rename does not repaint")
    func heldDuringRename() {
        let vm = vmWithLayouts()
        vm.renamingLayoutId = vm.layouts[0].id
        let before = vm.thumbnailRevision

        vm.noteThumbnailUpdate()

        #expect(vm.thumbnailRevision == before)
    }

    @Test("A capture landing during a search does not repaint")
    func heldDuringSearch() {
        let vm = vmWithLayouts()
        vm.isSearchFieldFocused = true
        let before = vm.thumbnailRevision

        vm.noteThumbnailUpdate()

        #expect(vm.thumbnailRevision == before)
    }

    @Test("The held repaint arrives once the rename ends")
    func flushesAfterRename() {
        let vm = vmWithLayouts()
        vm.renamingLayoutId = vm.layouts[0].id
        let before = vm.thumbnailRevision
        vm.noteThumbnailUpdate()

        vm.renamingLayoutId = nil

        // Held rather than dropped: the tiles are stale until this lands, so
        // losing it would leave the surface showing old previews indefinitely.
        #expect(vm.thumbnailRevision == before + 1)
    }

    @Test("The held repaint arrives once the search field lets go")
    func flushesAfterSearch() {
        let vm = vmWithLayouts()
        vm.isSearchFieldFocused = true
        let before = vm.thumbnailRevision
        vm.noteThumbnailUpdate()

        vm.isSearchFieldFocused = false

        #expect(vm.thumbnailRevision == before + 1)
    }

    @Test("Several captures held during one rename collapse into one repaint")
    func manyHeldCollapseToOne() {
        let vm = vmWithLayouts()
        vm.renamingLayoutId = vm.layouts[0].id
        let before = vm.thumbnailRevision

        vm.noteThumbnailUpdate()
        vm.noteThumbnailUpdate()
        vm.noteThumbnailUpdate()
        vm.renamingLayoutId = nil

        // Only the newest capture is worth anything, so the backlog must not
        // turn into a burst of repaints the moment the field lets go.
        #expect(vm.thumbnailRevision == before + 1)
    }

    @Test("Ending a rename with nothing held does not repaint")
    func noSpuriousFlush() {
        let vm = vmWithLayouts()
        vm.renamingLayoutId = vm.layouts[0].id
        let before = vm.thumbnailRevision

        vm.renamingLayoutId = nil

        #expect(vm.thumbnailRevision == before)
    }

    @Test("A rename still holds captures while a search field is also focused")
    func bothFocusedStillHolds() {
        let vm = vmWithLayouts()
        vm.isSearchFieldFocused = true
        vm.renamingLayoutId = vm.layouts[0].id
        let before = vm.thumbnailRevision
        vm.noteThumbnailUpdate()

        // One field letting go is not the end of typing when the other still
        // has focus, so the repaint has to keep waiting.
        vm.isSearchFieldFocused = false
        #expect(vm.thumbnailRevision == before)

        vm.renamingLayoutId = nil
        #expect(vm.thumbnailRevision == before + 1)
    }
}
