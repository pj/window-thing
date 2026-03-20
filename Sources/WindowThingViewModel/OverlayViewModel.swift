import Foundation
import AppKit
import Combine
import WindowThingCore

// MARK: - OverlayViewModel

public class OverlayViewModel: ObservableObject {
    @Published public var displays: [Display] = []
    @Published public var layouts: [Layout] = []

    // Editor state
    @Published public var editingLayout: Layout?
    @Published public var selectedScreenSetIndex: Int = 0
    @Published public var selectedNodePath: [Int] = []
    @Published public var editingRootNode: LayoutNode?
    @Published public var runningApps: [RunningAppInfo] = []
    @Published public var runningWindows: [Window] = []

    // Carousel
    @Published public var carouselOffset: Int = 0
    public let carouselPageSize = 3

    // Undo
    public let undoManager = UndoManager()
    private var preDragSnapshot: LayoutNode?

    private let windowManager: any WindowManaging
    private let layoutManager: any LayoutManaging
    // internal (not private) so @testable tests can seed it
    var originalLayouts: [Layout] = []

    public init(
        windowManager: any WindowManaging = WindowManager.shared,
        layoutManager: any LayoutManaging = LayoutManager.shared
    ) {
        self.windowManager = windowManager
        self.layoutManager = layoutManager
    }

    // MARK: - Refresh

    public func refresh() {
        displays = windowManager.getDisplays()
        layouts = layoutManager.layouts
        originalLayouts = layouts
        carouselOffset = 0
        refreshRunningApps()
        if let first = layouts.first {
            startEditing(first)
        }
    }

    public func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName else { return nil }
                return RunningAppInfo(name: name, bundleId: app.bundleIdentifier)
            }
            .sorted { $0.name < $1.name }
        runningWindows = windowManager.getWindows()
    }

    // MARK: - Navigation

    public func startEditing(_ layout: Layout) {
        editingLayout = layout
        selectedScreenSetIndex = 0
        selectedNodePath = []
        refreshEditingRootNode()
    }

    public func selectLayout(at index: Int) {
        guard index < layouts.count else { return }
        if index < carouselOffset {
            carouselOffset = index
        } else if index >= carouselOffset + carouselPageSize {
            carouselOffset = max(0, index - carouselPageSize + 1)
        }
        startEditing(layouts[index])
    }

    public func selectScreenSet(_ index: Int) {
        selectedScreenSetIndex = index
        selectedNodePath = []
        refreshEditingRootNode()
    }

    public var carouselCanGoBack: Bool { carouselOffset > 0 }
    public var carouselCanGoForward: Bool { carouselOffset + carouselPageSize < layouts.count }

    public func carouselPageBack() { if carouselCanGoBack { carouselOffset -= 1 } }
    public func carouselPageForward() { if carouselCanGoForward { carouselOffset += 1 } }

    public func refreshEditingRootNode() {
        guard let layout = editingLayout,
              let screenSet = layout.screenSets[safe: selectedScreenSetIndex] else {
            editingRootNode = nil
            return
        }
        let key = preferredMonitorKey(for: screenSet)
        editingRootNode = screenSet.layouts[key] ?? screenSet.layouts.values.first
    }

    public func preferredMonitorKey(for screenSet: ScreenConfig) -> String {
        screenSet.layouts.keys.contains(ScreenConfig.primaryKey)
            ? ScreenConfig.primaryKey
            : screenSet.layouts.keys.sorted().first ?? ScreenConfig.primaryKey
    }

    // MARK: - Node Updates (internal)

    private func applyRootNodeUpdate(_ node: LayoutNode) {
        guard var layout = editingLayout,
              selectedScreenSetIndex < layout.screenSets.count else { return }
        let key = preferredMonitorKey(for: layout.screenSets[selectedScreenSetIndex])
        layout.screenSets[selectedScreenSetIndex].layouts[key] = node
        editingLayout = layout
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
        }
        editingRootNode = node
    }

    // MARK: - Live Update (drag, no undo)

    public func updateRootNodeLive(_ node: LayoutNode) {
        applyRootNodeUpdate(node)
    }

    // MARK: - Drag Snapshot

    public func captureDragSnapshot() {
        preDragSnapshot = editingRootNode
    }

    public func commitDragFromSnapshot(to finalNode: LayoutNode) {
        let prev = preDragSnapshot ?? editingRootNode
        preDragSnapshot = nil
        undoManager.registerUndo(withTarget: self) { vm in
            vm.commitEdit(prev ?? finalNode, actionName: "Resize")
        }
        undoManager.setActionName("Resize")
        applyRootNodeUpdate(finalNode)
    }

    // MARK: - Committed Edit (undo, no auto-save)

    public func commitEdit(_ node: LayoutNode, actionName: String = "Edit Layout") {
        let prevNode = editingRootNode
        undoManager.registerUndo(withTarget: self) { vm in
            vm.commitEdit(prevNode ?? node, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        applyRootNodeUpdate(node)
    }

    // MARK: - Layout Metadata

    public func updateLayoutMeta(_ layout: Layout) {
        editingLayout = layout
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
        }
    }

    // MARK: - Save / Cancel

    public func saveEdits() {
        guard let layout = editingLayout else { return }
        layoutManager.updateLayout(layout)
        layoutManager.applyLayout(layout)
        originalLayouts = layouts
    }

    public func cancelEdits() {
        undoManager.removeAllActions()
        layouts = originalLayouts
        if let first = originalLayouts.first {
            startEditing(first)
        }
    }

    // MARK: - Screen Sets

    public func addScreenSet() {
        guard var layout = editingLayout else { return }
        layout.screenSets.append(ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()]))
        syncEditingLayout(layout)
        selectedScreenSetIndex = layout.screenSets.count - 1
        refreshEditingRootNode()
    }

    public func removeScreenSet(at index: Int) {
        guard var layout = editingLayout, layout.screenSets.count > 1 else { return }
        layout.screenSets.remove(at: index)
        syncEditingLayout(layout)
        selectedScreenSetIndex = min(selectedScreenSetIndex, layout.screenSets.count - 1)
        refreshEditingRootNode()
    }

    private func syncEditingLayout(_ layout: Layout) {
        editingLayout = layout
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
        }
    }
}

// MARK: - Array Safe Subscript

extension Array {
    public subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
