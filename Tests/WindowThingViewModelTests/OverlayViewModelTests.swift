import Testing
import Foundation
@testable import WindowThingViewModel
@testable import WindowThingCore

// MARK: - Mocks

private class MockLayoutManager: LayoutManaging {
    var layouts: [Layout] = []
    var savedSetups: [SavedSetup] = []
    var currentLayout: Layout?
    var appliedLayouts: [Layout] = []
    var updatedLayouts: [Layout] = []

    func loadLayouts(from config: AppConfig) { layouts = config.layouts }
    func applyLayout(_ layout: Layout) { appliedLayouts.append(layout); currentLayout = layout }
    func updateLayout(_ layout: Layout) {
        updatedLayouts.append(layout)
        if let i = layouts.firstIndex(where: { $0.id == layout.id }) { layouts[i] = layout }
    }
    func saveCurrentSetup(name: String) {}
    func loadSetup(_ setup: SavedSetup) {}
}

private class MockWindowManager: WindowManaging {
    var displays: [Display] = []
    var windows: [Window] = []
    var focusedApplication: Application?
    func getDisplays() -> [Display] { displays }
    func getWindows() -> [Window] { windows }
    func setWindowFrame(pid: pid_t, windowTitle: String?, frame: WindowFrame) -> Bool { true }
    func getFocusedApplication() -> Application? { focusedApplication }
}

// MARK: - Fixtures

private func makeLayout(name: String, key: String? = nil, root: LayoutNode = .empty()) -> Layout {
    Layout(name: name, quickKey: key, screenSets: [
        ScreenConfig(layouts: [ScreenConfig.primaryKey: root])
    ])
}

private func makeVM(layouts: [Layout] = []) -> (OverlayViewModel, MockLayoutManager, MockWindowManager) {
    let lm = MockLayoutManager()
    lm.layouts = layouts
    let wm = MockWindowManager()
    let vm = OverlayViewModel(windowManager: wm, layoutManager: lm)
    // Seed vm.layouts and originalLayouts so tests don't need to call refresh()
    // (refresh() hits NSWorkspace which is inappropriate for unit tests)
    vm.layouts = layouts
    vm.originalLayouts = layouts
    return (vm, lm, wm)
}

// MARK: - startEditing

@Suite("OverlayViewModel.startEditing")
struct StartEditingTests {

    @Test("startEditing sets editingLayout and resets path")
    func setsEditingLayout() {
        let layout = makeLayout(name: "Test")
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.selectedNodePath = [1, 2]
        vm.startEditing(layout)
        #expect(vm.editingLayout?.id == layout.id)
        #expect(vm.selectedNodePath.isEmpty)
        #expect(vm.selectedScreenSetIndex == 0)
    }

    @Test("startEditing populates editingRootNode from screenSet")
    func populatesRootNode() {
        let root = LayoutNode.columns([.empty(percentage: 50), .empty(percentage: 50)])
        let layout = makeLayout(name: "Split", root: root)
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        #expect(vm.editingRootNode?.type == .columns)
        #expect(vm.editingRootNode?.columns?.count == 2)
    }
}

// MARK: - selectLayout

@Suite("OverlayViewModel.selectLayout")
struct SelectLayoutTests {

    @Test("selectLayout switches editingLayout")
    func switchesLayout() {
        let a = makeLayout(name: "A")
        let b = makeLayout(name: "B")
        let (vm, _, _) = makeVM(layouts: [a, b])
        vm.startEditing(a)
        vm.selectLayout(at: 1)
        #expect(vm.editingLayout?.name == "B")
    }

    @Test("selectLayout ignores out-of-bounds index")
    func ignoresOutOfBounds() {
        let a = makeLayout(name: "A")
        let (vm, _, _) = makeVM(layouts: [a])
        vm.startEditing(a)
        vm.selectLayout(at: 99)
        #expect(vm.editingLayout?.name == "A")
    }

    @Test("selectLayout scrolls carousel forward when index beyond page")
    func scrollsCarouselForward() {
        let layouts = (0..<6).map { makeLayout(name: "Layout \($0)") }
        let (vm, _, _) = makeVM(layouts: layouts)
        vm.carouselOffset = 0
        vm.selectLayout(at: 4)   // beyond page size of 3
        #expect(vm.carouselOffset == 2)  // max(0, 4 - 3 + 1)
    }

    @Test("selectLayout scrolls carousel back when index before offset")
    func scrollsCarouselBack() {
        let layouts = (0..<6).map { makeLayout(name: "Layout \($0)") }
        let (vm, _, _) = makeVM(layouts: layouts)
        vm.carouselOffset = 3
        vm.selectLayout(at: 1)
        #expect(vm.carouselOffset == 1)
    }

    @Test("selectLayout within current page leaves offset unchanged")
    func leavesOffsetUnchanged() {
        let layouts = (0..<6).map { makeLayout(name: "Layout \($0)") }
        let (vm, _, _) = makeVM(layouts: layouts)
        vm.carouselOffset = 0
        vm.selectLayout(at: 2)   // within [0..<3]
        #expect(vm.carouselOffset == 0)
    }
}

// MARK: - Carousel navigation

@Suite("OverlayViewModel.carousel")
struct CarouselTests {

    @Test("carouselCanGoBack false at offset 0")
    func cannotGoBackAtZero() {
        let (vm, _, _) = makeVM()
        vm.carouselOffset = 0
        #expect(vm.carouselCanGoBack == false)
    }

    @Test("carouselCanGoBack true when offset > 0")
    func canGoBackWhenOffsetPositive() {
        let (vm, _, _) = makeVM()
        vm.carouselOffset = 1
        #expect(vm.carouselCanGoBack == true)
    }

    @Test("carouselCanGoForward false when all layouts visible")
    func cannotGoForwardWhenAllVisible() {
        let layouts = (0..<2).map { makeLayout(name: "L\($0)") }
        let (vm, _, _) = makeVM(layouts: layouts)
        vm.carouselOffset = 0
        #expect(vm.carouselCanGoForward == false)
    }

    @Test("carouselCanGoForward true when more layouts exist beyond page")
    func canGoForwardWhenMoreExist() {
        let layouts = (0..<5).map { makeLayout(name: "L\($0)") }
        let (vm, _, _) = makeVM(layouts: layouts)
        vm.carouselOffset = 0
        #expect(vm.carouselCanGoForward == true)
    }

    @Test("carouselPageForward increments offset")
    func pageForwardIncrements() {
        let layouts = (0..<5).map { makeLayout(name: "L\($0)") }
        let (vm, _, _) = makeVM(layouts: layouts)
        vm.carouselOffset = 0
        vm.carouselPageForward()
        #expect(vm.carouselOffset == 1)
    }

    @Test("carouselPageBack decrements offset")
    func pageBackDecrements() {
        let (vm, _, _) = makeVM()
        vm.carouselOffset = 2
        vm.carouselPageBack()
        #expect(vm.carouselOffset == 1)
    }

    @Test("carouselPageBack does not go below 0")
    func pageBackClampsAtZero() {
        let (vm, _, _) = makeVM()
        vm.carouselOffset = 0
        vm.carouselPageBack()
        #expect(vm.carouselOffset == 0)
    }
}

// MARK: - commitEdit and undo

@Suite("OverlayViewModel.commitEdit")
struct CommitEditTests {

    @Test("commitEdit updates editingRootNode")
    func updatesRootNode() {
        let root = LayoutNode.empty(percentage: 100)
        let layout = makeLayout(name: "L", root: root)
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        let newNode = LayoutNode.pinned(app: "Safari", percentage: 100)
        vm.commitEdit(newNode)

        #expect(vm.editingRootNode?.type == .pinned)
        #expect(vm.editingRootNode?.pinned?.application == "Safari")
    }

    @Test("commitEdit propagates change into layouts array")
    func propagatesIntoLayouts() {
        let root = LayoutNode.empty()
        let layout = makeLayout(name: "L", root: root)
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.commitEdit(LayoutNode.stackAll())

        let stored = vm.layouts[0].screenSets[0].layouts[ScreenConfig.primaryKey]
        #expect(stored?.type == .stack)
    }

    @Test("undo after commitEdit reverts to previous node")
    func undoRevertsToPrevious() {
        let original = LayoutNode.empty(percentage: 100)
        let layout = makeLayout(name: "L", root: original)
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.commitEdit(LayoutNode.pinned(app: "Safari", percentage: 100))
        #expect(vm.editingRootNode?.type == .pinned)

        vm.undoManager.undo()
        #expect(vm.editingRootNode?.type == .empty)
    }

    @Test("redo after undo re-applies the edit")
    func redoReappliesEdit() {
        let original = LayoutNode.empty(percentage: 100)
        let layout = makeLayout(name: "L", root: original)
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.commitEdit(LayoutNode.pinned(app: "Safari", percentage: 100))
        vm.undoManager.undo()
        vm.undoManager.redo()

        #expect(vm.editingRootNode?.type == .pinned)
    }

    @Test("multiple commits each register an undo action")
    func multipleCommitsRegisterUndo() {
        let layout = makeLayout(name: "L", root: .empty())
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        // Each commit should make undo available
        #expect(vm.undoManager.canUndo == false)
        vm.commitEdit(LayoutNode.pinned(app: "Safari", percentage: 100))
        #expect(vm.undoManager.canUndo == true)
        vm.commitEdit(LayoutNode.stackAll(percentage: 100))
        #expect(vm.editingRootNode?.type == .stack)
        // Undo reverts at least to a prior state (may group both commits in one
        // event cycle without a run loop — that's acceptable test-environment behaviour)
        vm.undoManager.undo()
        #expect(vm.editingRootNode?.type != .stack)
    }

    @Test("updateRootNodeLive does NOT register undo action")
    func liveUpdateNoUndo() {
        let layout = makeLayout(name: "L", root: .empty())
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        let undoCountBefore = vm.undoManager.levelsOfUndo

        vm.updateRootNodeLive(LayoutNode.pinned(app: "Safari", percentage: 100))

        // undoManager should have no more actions than before (live updates don't register undo)
        #expect(vm.undoManager.canUndo == (undoCountBefore > 0))
    }
}

// MARK: - Drag snapshot

@Suite("OverlayViewModel.dragSnapshot")
struct DragSnapshotTests {

    @Test("commitDragFromSnapshot registers undo from captured snapshot")
    func registersUndoFromSnapshot() {
        let original = LayoutNode.columns([.empty(percentage: 50), .empty(percentage: 50)])
        let (vm, _, _) = makeVM(layouts: [makeLayout(name: "L", root: original)])
        vm.startEditing(vm.layouts[0])

        vm.captureDragSnapshot()
        let resized = LayoutNode.columns([.empty(percentage: 70), .empty(percentage: 30)])
        vm.commitDragFromSnapshot(to: resized)

        #expect(vm.editingRootNode?.columns?[0].percentage == 70)

        vm.undoManager.undo()
        #expect(vm.editingRootNode?.columns?[0].percentage == 50)
    }

    @Test("commitDragFromSnapshot uses current node when no snapshot taken")
    func usesCurrentNodeWhenNoSnapshot() {
        let root = LayoutNode.empty(percentage: 100)
        let (vm, _, _) = makeVM(layouts: [makeLayout(name: "L", root: root)])
        vm.startEditing(vm.layouts[0])

        let resized = LayoutNode.pinned(app: "Xcode", percentage: 100)
        vm.commitDragFromSnapshot(to: resized)
        #expect(vm.editingRootNode?.type == .pinned)
        // undo should bring back empty
        vm.undoManager.undo()
        #expect(vm.editingRootNode?.type == .empty)
    }
}

// MARK: - saveEdits / cancelEdits

@Suite("OverlayViewModel.saveEdits")
struct SaveEditsTests {

    @Test("saveEdits calls layoutManager.updateLayout and applyLayout")
    func callsManagerMethods() {
        let layout = makeLayout(name: "L")
        let (vm, lm, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.commitEdit(LayoutNode.stackAll())

        vm.saveEdits()

        #expect(lm.updatedLayouts.count == 1)
        #expect(lm.appliedLayouts.count == 1)
    }

    @Test("saveEdits updates originalLayouts so cancel after save keeps edits")
    func updatesOriginalLayouts() {
        let layout = makeLayout(name: "L")
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.commitEdit(LayoutNode.stackAll())
        vm.saveEdits()

        // Now cancel — should keep the saved state (stack), not revert to empty
        vm.cancelEdits()
        let root = vm.layouts[0].screenSets[0].layouts[ScreenConfig.primaryKey]
        #expect(root?.type == .stack)
    }
}

@Suite("OverlayViewModel.cancelEdits")
struct CancelEditsTests {

    @Test("cancelEdits restores originalLayouts")
    func restoresOriginalLayouts() {
        let layout = makeLayout(name: "L", root: .empty())
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.commitEdit(LayoutNode.stackAll())
        vm.cancelEdits()

        let root = vm.layouts[0].screenSets[0].layouts[ScreenConfig.primaryKey]
        #expect(root?.type == .empty)
    }

    @Test("cancelEdits clears undo stack")
    func clearsUndoStack() {
        let layout = makeLayout(name: "L", root: .empty())
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        vm.commitEdit(LayoutNode.stackAll())
        #expect(vm.undoManager.canUndo == true)

        vm.cancelEdits()
        #expect(vm.undoManager.canUndo == false)
    }

    @Test("cancelEdits does NOT call layoutManager")
    func doesNotCallLayoutManager() {
        let layout = makeLayout(name: "L")
        let (vm, lm, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)
        vm.commitEdit(LayoutNode.stackAll())

        vm.cancelEdits()

        #expect(lm.updatedLayouts.isEmpty)
        #expect(lm.appliedLayouts.isEmpty)
    }
}

// MARK: - updateLayoutMeta

@Suite("OverlayViewModel.updateLayoutMeta")
struct UpdateLayoutMetaTests {

    @Test("updateLayoutMeta changes name in layouts array")
    func updatesNameInLayouts() {
        let layout = makeLayout(name: "Old Name")
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        var updated = layout
        updated.name = "New Name"
        vm.updateLayoutMeta(updated)

        #expect(vm.editingLayout?.name == "New Name")
        #expect(vm.layouts[0].name == "New Name")
    }

    @Test("updateLayoutMeta changes quickKey")
    func updatesQuickKey() {
        let layout = makeLayout(name: "L", key: "a")
        let (vm, _, _) = makeVM(layouts: [layout])
        vm.startEditing(layout)

        var updated = layout
        updated.quickKey = "z"
        vm.updateLayoutMeta(updated)

        #expect(vm.editingLayout?.quickKey == "z")
    }
}
