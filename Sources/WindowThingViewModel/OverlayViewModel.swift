import Foundation
import AppKit
import Combine
import WindowThingCore

// MARK: - App Selector Mode

public enum AppSelectorMode: Equatable, Sendable {
    case app
    case window
}

// MARK: - OverlayViewModel

public class OverlayViewModel: ObservableObject {
    @Published public var displays: [Display] = []
    @Published public var layouts: [Layout] = []

    // Editor state
    @Published public var renamingLayoutId: UUID?
    @Published public var recordingHotkeyLayoutId: UUID?
    @Published public var editingLayout: Layout?
    @Published public var selectedScreenSetIndex: Int = 0
    @Published public var selectedNodePath: NodePath = .root
    @Published public var editingRootNode: LayoutNode?
    @Published public var runningApps: [RunningAppInfo] = []
    @Published public var runningWindows: [Window] = []
    @Published public var thumbnailRevision: Int = 0

    /// The window that was focused when the editor opened — candidate for cell movement.
    @Published public var selectedMoveWindow: Window?

    // Carousel
    @Published public var carouselOffset: Int = 0
    public let carouselPageSize = 3

    // Cell picker state
    @Published public var isCellPickerVisible: Bool = false
    @Published public var pendingMoveWindow: Window?
    @Published public var pickerCells: [IndexedCell] = []
    @Published public var pickerGhostPositions: [GhostCellPosition] = []

    // App/Window selector state
    @Published public var isAppSelectorVisible: Bool = false
    @Published public var appSelectorMode: AppSelectorMode = .app
    @Published public var appSelectorSearchText: String = ""
    @Published public var appSelectorSelectedIndex: Int = 0

    // Undo
    public let undoManager = UndoManager()
    private var preDragSnapshot: LayoutNode?

    private let windowManager: any WindowManaging
    private let layoutManager: any LayoutManaging
    private let configManager: any ConfigProviding
    // internal (not private) so @testable tests can seed it
    var originalLayouts: [Layout] = []

    public init(
        windowManager: any WindowManaging = WindowManager.shared,
        layoutManager: any LayoutManaging = LayoutManager.shared,
        configManager: any ConfigProviding = ConfigManager.shared
    ) {
        self.windowManager = windowManager
        self.layoutManager = layoutManager
        self.configManager = configManager
    }

    // MARK: - Refresh

    public func refresh() {
        displays = windowManager.getDisplays()
        layouts = layoutManager.layouts
        originalLayouts = layouts
        carouselOffset = 0
        refreshRunningApps()
        let active = layoutManager.lastUsedLayout
            ?? layoutManager.currentLayout
            ?? layouts.first
        if let active {
            startEditing(active)
            // Adjust carousel so the active layout is visible
            if let idx = layouts.firstIndex(where: { $0.id == active.id }) {
                if idx >= carouselOffset + carouselPageSize {
                    carouselOffset = max(0, idx - carouselPageSize + 1)
                } else if idx < carouselOffset {
                    carouselOffset = idx
                }
            }
        }
        WindowThumbnailCache.shared.onUpdate = { [weak self] in
            self?.thumbnailRevision += 1
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
        selectedNodePath = .root
        refreshEditingRootNode()
    }

    public func selectLayout(at index: Int) {
        guard index < layouts.count else { return }
        if index < carouselOffset {
            carouselOffset = index
        } else if index >= carouselOffset + carouselPageSize {
            carouselOffset = max(0, index - carouselPageSize + 1)
        }
        let layout = layouts[index]
        startEditing(layout)
        layoutManager.applyLayout(layout)
    }

    /// Apply the currently editing layout to windows without changing any selection state.
    public func applyCurrentLayout() {
        guard let layout = editingLayout else { return }
        layoutManager.applyLayout(layout)
    }

    public func selectScreenSet(_ index: Int) {
        selectedScreenSetIndex = index
        selectedNodePath = .root
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
        autoSave()
    }

    // MARK: - Committed Edit (undo + implicit save)

    public func commitEdit(_ node: LayoutNode, actionName: String = "Edit Layout") {
        let prevNode = editingRootNode
        undoManager.registerUndo(withTarget: self) { vm in
            vm.commitEdit(prevNode ?? node, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        applyRootNodeUpdate(node)
        autoSave()
    }

    // MARK: - Hotkey Recording

    /// Start recording a hotkey for the given layout.
    public func startRecordingHotkey(for layoutId: UUID) {
        recordingHotkeyLayoutId = layoutId
    }

    /// Cancel hotkey recording without changes.
    public func cancelRecordingHotkey() {
        recordingHotkeyLayoutId = nil
    }

    // MARK: - Layout Metadata

    public func updateLayoutMeta(_ layout: Layout) {
        editingLayout = layout
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
        }
        autoSaveMeta()
    }

    /// Persist and apply layout changes to open windows.
    private func autoSave() {
        guard let layout = editingLayout else { return }
        layoutManager.updateLayout(layout)
        layoutManager.applyLayout(layout)
        configManager.saveLayouts(layouts)
    }

    /// Persist metadata-only changes (name, hotkey) without repositioning windows.
    private func autoSaveMeta() {
        if let layout = editingLayout {
            layoutManager.updateLayout(layout)
        }
        configManager.saveLayouts(layouts)
    }

    // MARK: - Save / Cancel

    public func saveEdits() {
        guard let layout = editingLayout else { return }
        layoutManager.updateLayout(layout)
        layoutManager.applyLayout(layout)
        originalLayouts = layouts
        configManager.saveLayouts(layouts)
    }

    public func cancelEdits() {
        undoManager.removeAllActions()
        layouts = originalLayouts
        if let first = originalLayouts.first {
            startEditing(first)
        }
    }

    // MARK: - Layout CRUD

    /// Create a new layout (single full-screen stackAll), begin editing it,
    /// and immediately enter rename mode so the user can type a name.
    public func addLayout() {
        let newLayout = Layout(
            name: "",
            screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])]
        )
        layouts.append(newLayout)
        configManager.saveLayouts(layouts)
        selectLayout(at: layouts.count - 1)
        renamingLayoutId = newLayout.id
    }

    /// Duplicate `layout` with a new UUID and name suffix, insert after the original.
    public func duplicateLayout(_ layout: Layout) {
        let copy = Layout(
            id: UUID(),
            name: layout.name + " Copy",
            quickKey: nil,
            screenSets: layout.screenSets
        )
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts.insert(copy, at: idx + 1)
        } else {
            layouts.append(copy)
        }
        configManager.saveLayouts(layouts)
        if let newIdx = layouts.firstIndex(where: { $0.id == copy.id }) {
            selectLayout(at: newIdx)
        }
    }

    /// Delete `layout`. Switches editor to the nearest remaining layout.
    public func deleteLayout(_ layout: Layout) {
        guard layouts.count > 1 else { return }
        let idx = layouts.firstIndex(where: { $0.id == layout.id }) ?? 0
        layouts.removeAll { $0.id == layout.id }
        originalLayouts = layouts
        configManager.saveLayouts(layouts)
        let nextIdx = min(idx, layouts.count - 1)
        selectLayout(at: nextIdx)
    }

    // MARK: - Cell Picker

    /// Show the cell picker for `window`. Computes current cells + ghost positions.
    public func showCellPicker(for window: Window) {
        guard let layout = editingLayout else { return }
        pickerCells = layoutManager.cellAddresses(for: layout, displays: displays)
        pickerGhostPositions = CellIndexer.ghostPositions(layout: layout, displays: displays)
        pendingMoveWindow = window
        isCellPickerVisible = true
    }

    public func hideCellPicker() {
        isCellPickerVisible = false
        pendingMoveWindow = nil
        pickerCells = []
        pickerGhostPositions = []
    }

    /// Move the pending window to the selected cell address.
    public func selectCell(_ address: CellAddress) {
        guard let window = pendingMoveWindow else { return }
        try? layoutManager.moveWindow(window, toCellAt: address, displays: displays)
        hideCellPicker()
    }

    /// Append a ghost position's column/row to the current layout tree, then move pending window there.
    public func selectGhostCell(_ position: GhostCellPosition) {
        guard let window = pendingMoveWindow,
              let currentNode = editingRootNode else { return }

        let newNode: LayoutNode
        switch position.direction {
        case .trailingColumn:
            newNode = LayoutModification.appendTrailingColumn(to: currentNode)
        case .trailingRow:
            newNode = LayoutModification.appendTrailingRow(to: currentNode)
        }

        // Commit the new root node (registers undo, updates editingLayout/layouts)
        commitEdit(newNode, actionName: "Add Cell")

        // Re-index against the now-updated editingLayout
        if let layout = editingLayout {
            let updatedCells = layoutManager.cellAddresses(for: layout, displays: displays)
            if let lastCell = updatedCells.last {
                try? layoutManager.moveWindow(window, toCellAt: lastCell.address, displays: displays)
            }
        }
        hideCellPicker()
    }

    // MARK: - App/Window Selector

    /// Whether the selected pane is a stack (changes selector behavior).
    public var selectorIsForStack: Bool {
        guard let root = editingRootNode else { return false }
        let path = selectedNodePath
        if path.isRoot { return root.type == .stack }
        return path.node(in: root)?.type == .stack
    }

    public var filteredApps: [RunningAppInfo] {
        let q = appSelectorSearchText.lowercased()
        if q.isEmpty { return runningApps }
        return runningApps.filter { $0.name.lowercased().contains(q) }
    }

    public var filteredWindows: [Window] {
        let q = appSelectorSearchText.lowercased()
        let windows = runningWindows.filter { $0.application != "WindowThing" }
        if q.isEmpty { return windows }
        return windows.filter {
            $0.application.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
    }

    /// Windows that belong in the stack (not pinned elsewhere in the layout).
    public var stackWindows: [Window] {
        guard let root = editingRootNode else { return [] }
        let pinnedApps = collectPinnedApps(in: root)
        let q = appSelectorSearchText.lowercased()
        return runningWindows.filter { window in
            if window.application == "WindowThing" { return false }
            let isPinned = pinnedApps.contains { app in
                if let bundleId = app.bundleId, window.bundleId == bundleId { return true }
                if let name = app.application,
                   window.application.localizedCaseInsensitiveCompare(name) == .orderedSame { return true }
                return false
            }
            if isPinned { return false }
            if q.isEmpty { return true }
            return window.application.lowercased().contains(q) || window.title.lowercased().contains(q)
        }
    }

    private func collectPinnedApps(in node: LayoutNode) -> [PinnedConfig] {
        switch node.type {
        case .pinned:
            if let p = node.pinned { return [p] }
            return []
        case .columns:
            return (node.columns ?? []).flatMap { collectPinnedApps(in: $0) }
        case .rows:
            return (node.rows ?? []).flatMap { collectPinnedApps(in: $0) }
        default:
            return []
        }
    }

    public func showAppSelector() {
        guard let root = editingRootNode else { return }
        let path = selectedNodePath
        // Verify it points to a leaf
        if !path.isRoot {
            guard let node = path.node(in: root) else { return }
            if node.type == .columns || node.type == .rows { return }
        } else if root.type == .columns || root.type == .rows {
            return
        }
        refreshRunningApps()
        appSelectorMode = .app
        appSelectorSearchText = ""
        appSelectorSelectedIndex = 0
        isAppSelectorVisible = true
    }

    public func hideAppSelector() {
        isAppSelectorVisible = false
        appSelectorSearchText = ""
    }

    public func toggleAppSelectorMode() {
        appSelectorMode = appSelectorMode == .app ? .window : .app
        appSelectorSelectedIndex = 0
    }

    /// Apply the selection. For empty/pinned panes, pins the app. For stack, sets selectedMoveWindow.
    public func applyAppSelectorSelection(at index: Int) {
        if selectorIsForStack {
            if appSelectorMode == .app {
                applyStackAppSelection(at: index)
            } else {
                applyStackSelection(at: index)
            }
        } else if appSelectorMode == .app {
            applyAppSelection(at: index)
        } else {
            applyWindowSelection(at: index)
        }
        hideAppSelector()
    }

    private func applyAppSelection(at index: Int) {
        guard let root = editingRootNode,
              let app = filteredApps[safe: index] else { return }
        let currentNode = selectedNodePath.isRoot ? root : selectedNodePath.node(in: root)
        guard let currentNode else { return }
        let pinned = PinnedConfig(application: app.name, bundleId: app.bundleId)
        let newNode = LayoutNode(type: .pinned, percentage: currentNode.percentage, pinned: pinned)
        if selectedNodePath.isRoot {
            commitEdit(newNode)
        } else if let updated = root.replacingNode(at: selectedNodePath.indices, with: newNode) {
            commitEdit(updated)
        }
    }

    private func applyWindowSelection(at index: Int) {
        guard let root = editingRootNode,
              let window = filteredWindows[safe: index] else { return }
        let currentNode = selectedNodePath.isRoot ? root : selectedNodePath.node(in: root)
        guard let currentNode else { return }
        let pinned = PinnedConfig(
            application: window.application,
            bundleId: window.bundleId,
            windowTitles: window.title.isEmpty ? nil : [window.title]
        )
        let newNode = LayoutNode(type: .pinned, percentage: currentNode.percentage, pinned: pinned)
        if selectedNodePath.isRoot {
            commitEdit(newNode)
        } else if let updated = root.replacingNode(at: selectedNodePath.indices, with: newNode) {
            commitEdit(updated)
        }
        // Bring window to front (behind overlay)
        bringWindowToFront(window)
    }

    private func applyStackAppSelection(at index: Int) {
        guard let app = filteredApps[safe: index] else { return }
        // Find the first stack window matching this app
        let window = stackWindows.first { w in
            if let bundleId = app.bundleId, w.bundleId == bundleId { return true }
            return w.application.localizedCaseInsensitiveCompare(app.name) == .orderedSame
        }
        if let window {
            selectedMoveWindow = window
            bringWindowToFront(window)
        }
    }

    private func applyStackSelection(at index: Int) {
        guard let window = stackWindows[safe: index] else { return }
        selectedMoveWindow = window
        bringWindowToFront(window)
    }

    private func bringWindowToFront(_ window: Window) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        app?.activate(options: [])
        // Re-activate our app after a brief delay so overlay stays on top
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
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
