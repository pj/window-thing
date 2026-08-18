import Testing
import Foundation
import CoreGraphics
@testable import WindowThingViewModel
@testable import WindowThingCore

// MARK: - Mocks

private class MockLayoutManager: LayoutManaging {
    var layouts: [Layout] = []
    var savedSetups: [SavedSetup] = []
    var currentLayout: Layout?
    var lastUsedLayout: Layout?
    var appliedLayouts: [Layout] = []
    var updatedLayouts: [Layout] = []

    func loadLayouts(from config: AppConfig) { layouts = config.layouts }
    func applyLayout(_ layout: Layout) { appliedLayouts.append(layout); currentLayout = layout; lastUsedLayout = layout }
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
    var saveCount = 0
    func loadConfig() {}
    func saveConfig() {}
    func saveLayouts(_ layouts: [Layout]) { savedLayouts = layouts; saveCount += 1 }
}

// MARK: - Fixtures

/// A layout spanning two monitors: the stack on the primary, a pinned pane and
/// an empty pane on the external.
private func twoMonitorLayout() -> Layout {
    Layout(name: "Spanning", screenSets: [
        ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .columns([.stackAll(percentage: 50), .empty(percentage: 50)]),
            "External": .pinned(app: "Mail")
        ])
    ])
}

private func makeVM(
    layouts: [Layout]
) -> (OverlayViewModel, MockLayoutManager, MockConfigManager) {
    let lm = MockLayoutManager()
    lm.layouts = layouts
    let wm = MockWindowManager()
    let cm = MockConfigManager()
    let vm = OverlayViewModel(windowManager: wm, layoutManager: lm, configManager: cm)
    vm.layouts = layouts
    vm.originalLayouts = layouts
    if let first = layouts.first { vm.startEditing(first) }
    return (vm, lm, cm)
}

// MARK: - Reading a monitor's tree

@Suite("OverlayViewModel.monitorScopedReads")
struct MonitorScopedReadTests {

    @Test("rootNode reads each monitor's own tree")
    func readsPerMonitor() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])

        #expect(vm.rootNode(forMonitor: ScreenConfig.primaryKey)?.type == .columns)
        #expect(vm.rootNode(forMonitor: "External")?.type == .pinned)
    }

    @Test("A monitor the layout doesn't describe has no tree")
    func unknownMonitorHasNoTree() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])

        #expect(vm.rootNode(forMonitor: "Unplugged") == nil)
        #expect(!vm.hasLayout(forMonitor: "Unplugged"))
        #expect(vm.hasLayout(forMonitor: "External"))
    }
}

// MARK: - Editing one monitor

@Suite("OverlayViewModel.monitorScopedEdits")
struct MonitorScopedEditTests {

    @Test("An edit lands on the named monitor and leaves the others alone")
    func editsOnlyTheNamedMonitor() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])
        let before = vm.rootNode(forMonitor: ScreenConfig.primaryKey)

        vm.commitEdit(.pinned(app: "Safari"), forMonitor: "External")

        #expect(vm.rootNode(forMonitor: "External")?.pinned?.application == "Safari")
        #expect(vm.rootNode(forMonitor: ScreenConfig.primaryKey) == before)
    }

    @Test("Editing a monitor other than the cursor leaves editingRootNode alone")
    func doesNotDisturbTheCursor() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])
        // The cursor is on the primary after startEditing.
        let cursorNode = vm.editingRootNode

        vm.commitEdit(.pinned(app: "Safari"), forMonitor: "External")

        #expect(vm.editingRootNode == cursorNode)
    }

    @Test("An edit persists through the layout manager and config")
    func editPersists() {
        let (vm, lm, cm) = makeVM(layouts: [twoMonitorLayout()])

        vm.commitEdit(.pinned(app: "Safari"), forMonitor: "External")

        #expect(lm.updatedLayouts.count == 1)
        #expect(cm.savedLayouts.first?.screenSets[0].layouts["External"]?.pinned?.application == "Safari")
    }

    @Test("Undo restores the monitor that was edited")
    func undoRestoresMonitor() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])

        vm.commitEdit(.pinned(app: "Safari"), forMonitor: "External")
        vm.undoManager.undo()

        #expect(vm.rootNode(forMonitor: "External")?.pinned?.application == "Mail")
    }
}

// MARK: - Editing several monitors at once

@Suite("OverlayViewModel.multiMonitorCommit")
struct MultiMonitorCommitTests {

    /// Moving the stack between screens has to change both monitors together,
    /// or the layout briefly holds two stacks — or none.
    @Test("A combined commit writes every monitor it names")
    func writesAllMonitors() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])

        vm.commitEdits(
            [
                ScreenConfig.primaryKey: .columns([.empty(percentage: 50), .empty(percentage: 50)]),
                "External": .stackAll()
            ],
            actionName: "Move Stack"
        )

        #expect(vm.rootNode(forMonitor: "External")?.type == .stack)
        #expect(vm.rootNode(forMonitor: ScreenConfig.primaryKey)?.findStackLocation() == nil)
    }

    @Test("The layout still has exactly one stack afterwards")
    func keepsOneStack() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])

        vm.commitEdits(
            [
                ScreenConfig.primaryKey: .columns([.empty(percentage: 50), .empty(percentage: 50)]),
                "External": .stackAll()
            ],
            actionName: "Move Stack"
        )

        let screenSet = vm.editingLayout?.screenSets[0]
        #expect(screenSet?.stackKeys == ["External"])
    }

    @Test("Undo rolls back every monitor, not just one")
    func undoRestoresBothMonitors() {
        let (vm, _, _) = makeVM(layouts: [twoMonitorLayout()])

        vm.commitEdits(
            [
                ScreenConfig.primaryKey: .columns([.empty(percentage: 50), .empty(percentage: 50)]),
                "External": .stackAll()
            ],
            actionName: "Move Stack"
        )
        vm.undoManager.undo()

        #expect(vm.rootNode(forMonitor: "External")?.type == .pinned)
        #expect(vm.rootNode(forMonitor: ScreenConfig.primaryKey)?.findStackLocation() != nil)
    }

    @Test("An empty combined commit does nothing")
    func emptyCommitIsANoOp() {
        let (vm, lm, _) = makeVM(layouts: [twoMonitorLayout()])

        vm.commitEdits([:], actionName: "Nothing")

        #expect(lm.updatedLayouts.isEmpty)
    }
}

// MARK: - Adding a display

@Suite("OverlayViewModel.addMonitor")
struct AddMonitorTests {

    @Test("A new monitor starts empty when the layout already has a stack")
    func doesNotAddASecondStack() {
        // Regression: `addingDisplay` defaults to a full stack, so adding a
        // display used to leave the layout with two.
        let layout = Layout(name: "Solo", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])
        let (vm, _, _) = makeVM(layouts: [layout])

        vm.addMonitorToScreenSet("External")

        let screenSet = vm.editingLayout?.screenSets[0]
        #expect(screenSet?.stackKeys == [ScreenConfig.primaryKey])
        #expect(screenSet?.layouts["External"]?.type == .empty)
    }

    @Test("A new monitor takes the stack when nothing else holds it")
    func takesStackWhenLayoutHasNone() {
        let layout = Layout(name: "Solo", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .pinned(app: "Mail")])
        ])
        let (vm, _, _) = makeVM(layouts: [layout])

        vm.addMonitorToScreenSet("External")

        #expect(vm.editingLayout?.screenSets[0].stackKeys == ["External"])
    }

    @Test("Adding a display is saved, not just held in memory")
    func addingADisplayPersists() {
        let layout = Layout(name: "Solo", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])
        let (vm, lm, cm) = makeVM(layouts: [layout])

        vm.addMonitorToScreenSet("External")

        #expect(lm.updatedLayouts.count == 1)
        #expect(cm.savedLayouts.first?.screenSets[0].layouts["External"] != nil)
    }
}

// MARK: - Selector targeting

@Suite("OverlayViewModel.selectorTarget")
struct SelectorTargetTests {

    private func splitLayout() -> Layout {
        Layout(name: "Split", screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .stackAll(percentage: 50),
                    .empty(percentage: 50)
                ])
            ])
        ])
    }

    @Test("The selector holds the pane it opened on")
    func capturesItsTarget() {
        let (vm, _, _) = makeVM(layouts: [splitLayout()])

        vm.showAppSelector(for: NodePath([1]))

        #expect(vm.isAppSelectorVisible)
        #expect(vm.appSelectorTargetPath == NodePath([1]))
        #expect(!vm.selectorIsForStack)
    }

    /// The bug this guards: the target used to be re-read from
    /// `selectedNodePath` when the choice was made, and `startEditing` resets
    /// that to root. A refresh landing while the selector was open retargeted it
    /// at the whole layout — which, when the root was a stack, silently turned
    /// "pin this app here" into "raise this window".
    @Test("A refresh while the selector is open doesn't move its target")
    func targetSurvivesACursorReset() {
        let (vm, _, _) = makeVM(layouts: [splitLayout()])
        vm.showAppSelector(for: NodePath([1]))

        vm.selectedNodePath = .root      // what startEditing does

        #expect(vm.appSelectorTargetPath == NodePath([1]))
        #expect(!vm.selectorIsForStack)
    }

    @Test("Choosing an app pins it to the captured pane")
    func pinsToTheCapturedPane() {
        let (vm, _, _) = makeVM(layouts: [splitLayout()])

        vm.showAppSelector(for: NodePath([1]))
        // Seeded after opening: `showAppSelector` calls `refreshRunningApps`,
        // which reads the real NSWorkspace and would replace these.
        vm.runningApps = [RunningAppInfo(name: "Mail", bundleId: "com.apple.mail")]
        vm.selectedNodePath = .root      // the cursor drifts
        vm.applyAppSelectorSelection(at: 0)

        let root = vm.rootNode(forMonitor: ScreenConfig.primaryKey)
        #expect(root?.columns?[1].type == .pinned)
        #expect(root?.columns?[1].pinned?.application == "Mail")
        // The stack pane is untouched, and the layout still has its one stack.
        #expect(root?.columns?[0].type == .stack)
    }

    @Test("The selector reports a stack pane as such")
    func recognisesAStackPane() {
        let (vm, _, _) = makeVM(layouts: [splitLayout()])

        vm.showAppSelector(for: NodePath([0]))

        #expect(vm.selectorIsForStack)
    }

    @Test("The selector refuses to open on a container")
    func refusesContainers() {
        let (vm, _, _) = makeVM(layouts: [splitLayout()])

        vm.showAppSelector(for: .root)   // the root is a columns node

        #expect(!vm.isAppSelectorVisible)
    }
}

// MARK: - Layout list operations

@Suite("OverlayViewModel.layoutListEdits")
struct LayoutListEditTests {

    private func three() -> [Layout] {
        [
            Layout(name: "One", screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])]),
            Layout(name: "Two", screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])]),
            Layout(name: "Three", screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])])
        ]
    }

    @Test("Deleting a layout falls back to the last one, not the deleted index")
    func deleteSelectsLast() {
        let (vm, _, _) = makeVM(layouts: three())

        vm.deleteLayout(vm.layouts[0])

        #expect(vm.layouts.count == 2)
        #expect(vm.editingLayout?.name == "Three")
    }

    @Test("The last remaining layout can't be deleted")
    func keepsAtLeastOne() {
        let (vm, _, _) = makeVM(layouts: [three()[0]])

        vm.deleteLayout(vm.layouts[0])

        #expect(vm.layouts.count == 1)
    }

    @Test("Renaming applies the draft and clears the editing state")
    func renameCommits() {
        let (vm, _, cm) = makeVM(layouts: three())

        vm.beginRename(vm.layouts[1])
        vm.renameDraft = "  Renamed  "
        vm.commitRename()

        #expect(vm.layouts[1].name == "Renamed")
        #expect(vm.renamingLayoutId == nil)
        #expect(cm.savedLayouts[1].name == "Renamed")
    }

    @Test("An emptied name falls back rather than leaving a blank pill")
    func renameRejectsEmpty() {
        let (vm, _, _) = makeVM(layouts: three())

        vm.beginRename(vm.layouts[0])
        vm.renameDraft = "   "
        vm.commitRename()

        #expect(vm.layouts[0].name == "Untitled")
    }

    @Test("Cancelling a rename leaves the name alone")
    func renameCancels() {
        let (vm, _, _) = makeVM(layouts: three())

        vm.beginRename(vm.layouts[0])
        vm.renameDraft = "Discarded"
        vm.cancelRename()

        #expect(vm.layouts[0].name == "One")
        #expect(vm.renamingLayoutId == nil)
    }

    @Test("Renaming a layout doesn't make it the one being edited")
    func renameDoesNotStealTheCursor() {
        // `updateLayoutMeta` assigns `editingLayout`, which used to switch the
        // canvas to whichever layout was renamed without applying it.
        let (vm, _, _) = makeVM(layouts: three())
        vm.startEditing(vm.layouts[0])

        vm.beginRename(vm.layouts[2])
        vm.renameDraft = "Renamed"
        vm.commitRename()

        #expect(vm.editingLayout?.name == "One")
    }
}
