import Testing
import Foundation
import CoreGraphics
@testable import WindowThingViewModel
@testable import WindowThingCore

// MARK: - Mocks (duplicated from OverlayViewModelTests for test isolation)

private class MockLayoutManager: LayoutManaging {
    var layouts: [Layout] = []
    var savedSetups: [SavedSetup] = []
    var currentLayout: Layout?
    var lastUsedLayout: Layout?
    var appliedLayouts: [Layout] = []
    var updatedLayouts: [Layout] = []

    func loadLayouts(from config: AppConfig) { layouts = config.layouts }
    func applyLayout(_ layout: Layout) { appliedLayouts.append(layout); currentLayout = layout; lastUsedLayout = layout }
    func setLayouts(_ newLayouts: [Layout]) { layouts = newLayouts }

    func updateLayout(_ layout: Layout) {
        updatedLayouts.append(layout)
        if let i = layouts.firstIndex(where: { $0.id == layout.id }) { layouts[i] = layout }
    }
    func saveCurrentSetup(name: String) {}
    func loadSetup(_ setup: SavedSetup) {}
    func moveWindow(_ window: Window, toCellAt address: CellAddress, displays: [Display]) throws {}
    func cellAddresses(for layout: Layout, displays: [Display]) -> [IndexedCell] {
        CellIndexer.indexCells(layout: layout, displays: displays)
    }
}

private class MockWindowManager: WindowManaging {
    var displays: [Display] = []
    var windows: [Window] = []
    var focusedApplication: Application?
    func getDisplays() -> [Display] { displays }
    func getWindows() -> [Window] { windows }
    func setWindowFrame(pid: pid_t, windowTitle: String?, frame: WindowFrame) -> Bool { true }
    func setWindowFrame(pid: pid_t, windowId: CGWindowID, frame: WindowFrame) -> Bool { true }
    func getFocusedApplication() -> Application? { focusedApplication }
}

private class MockConfigManager: ConfigProviding {
    var config: AppConfig = .default
    var configFilePath: URL = URL(fileURLWithPath: "/tmp/test-config.yaml")
    var setupsFilePath: URL = URL(fileURLWithPath: "/tmp/test-setups.yaml")
    var savedLayouts: [Layout] = []
    func loadConfig() {}
    func saveConfig() {}
    func saveLayouts(_ layouts: [Layout]) { savedLayouts = layouts }
}

// MARK: - Display Helpers

private func display(id: Int, name: String, x: CGFloat = 0, width: CGFloat = 1920, height: CGFloat = 1080, isMain: Bool = false) -> Display {
    Display(id: id, name: name, frame: WindowFrame(x: x, y: 0, width: width, height: height), isMain: isMain)
}

private let singleDisplay = [
    display(id: 0, name: "Main Display", isMain: true)
]

private let dualDisplays = [
    display(id: 0, name: "Main Display", isMain: true),
    display(id: 1, name: "External Display", x: 1920)
]

private let tripleDisplays = [
    display(id: 0, name: "Main Display", isMain: true),
    display(id: 1, name: "External Display", x: 1920),
    display(id: 2, name: "Left Display", x: -1920)
]

private func makeVM(
    layouts: [Layout] = [],
    displays: [Display] = singleDisplay
) -> (OverlayViewModel, MockLayoutManager, MockWindowManager, MockConfigManager) {
    let lm = MockLayoutManager()
    lm.layouts = layouts
    let wm = MockWindowManager()
    wm.displays = displays
    let cm = MockConfigManager()
    let vm = OverlayViewModel(windowManager: wm, layoutManager: lm, configManager: cm)
    vm.layouts = layouts
    vm.originalLayouts = layouts
    vm.displays = displays
    return (vm, lm, wm, cm)
}

private func makeDualDisplayLayout() -> Layout {
    Layout(
        name: "Dual Setup",
        screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Xcode", percentage: 60),
                    .stackAll(percentage: 40)
                ]),
                "External Display": .columns([
                    .pinned(app: "Terminal", percentage: 50),
                    .pinned(app: "Safari", percentage: 50)
                ])
            ])
    )
}


// MARK: - Screen Set Selection

@Suite("OverlayViewModel.displayMap")
struct OverlayViewModelDisplayMapTests {

    /// A layout covering two displays. One map, not a choice between maps.
    private func twoDisplayLayout() -> Layout {
        Layout(
            name: "Desk",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Xcode", percentage: 60),
                    .stackAll(percentage: 40)
                ]),
                "External Display": .pinned(app: "Safari")
            ])
        )
    }

    @Test("preferredMonitorKey returns $PRIMARY when present")
    func preferredIsPrimary() {
        let (vm, _, _, _) = makeVM(layouts: [twoDisplayLayout()])
        #expect(vm.preferredMonitorKey(for: twoDisplayLayout().screens) == ScreenConfig.primaryKey)
    }

    @Test("preferredMonitorKey falls back to the first key sorted when there is no $PRIMARY")
    func preferredWithoutPrimary() {
        let (vm, _, _, _) = makeVM(layouts: [])
        let screens = ScreenConfig(layouts: [
            "Zebra": .stackAll(),
            "Alpha": .empty()
        ])
        #expect(vm.preferredMonitorKey(for: screens) == "Alpha")
    }

    @Test("Editing one monitor leaves the layout's other monitors alone")
    func editingOneMonitorIsScoped() {
        let layout = twoDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.editingLayout = layout

        vm.commitEdit(.stackAll(), forMonitor: ScreenConfig.primaryKey, actionName: "Edit")

        #expect(vm.editingLayout?.screens.layouts[ScreenConfig.primaryKey] == .stackAll())
        #expect(vm.editingLayout?.screens.layouts["External Display"] == .pinned(app: "Safari"))
    }

    @Test("Arranging a new monitor gives it a tree in the same map")
    func arrangingANewMonitor() {
        let layout = Layout(
            name: "Solo",
            screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        )
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.editingLayout = layout

        vm.commitEdit(.empty(), forMonitor: "External Display", actionName: "Touch")

        #expect(vm.editingLayout?.screens.layouts.count == 2)
        #expect(vm.editingLayout?.screens.layouts["External Display"] == .empty())
    }

    @Test("Removing a monitor takes only that display out")
    func removingAMonitor() {
        let layout = twoDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.editingLayout = layout

        vm.removeMonitor("External Display")

        #expect(vm.editingLayout?.screens.layouts["External Display"] == nil)
        #expect(vm.editingLayout?.screens.layouts[ScreenConfig.primaryKey] != nil)
    }

    @Test("The primary display cannot be removed, so a layout always applies")
    func primaryCannotBeRemoved() {
        let layout = twoDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])
        vm.editingLayout = layout

        vm.removeMonitor(ScreenConfig.primaryKey)

        #expect(vm.editingLayout?.screens.layouts[ScreenConfig.primaryKey] != nil)
    }

    @Test("Duplicating a layout copies its whole display map")
    func duplicatePreservesTheMap() {
        let layout = twoDisplayLayout()
        let (vm, _, _, _) = makeVM(layouts: [layout])

        vm.duplicateLayout(layout)

        let copy = vm.layouts.last
        #expect(copy?.screens.layouts.count == 2)
        #expect(copy?.screens.layouts["External Display"] == .pinned(app: "Safari"))
        #expect(copy?.id != layout.id)
    }
}
