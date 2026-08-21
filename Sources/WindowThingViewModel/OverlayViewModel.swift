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
    @Published public var selectedMonitorKey: String = ScreenConfig.primaryKey
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
    /// The pane the open selector will act on, fixed when it opens.
    @Published public var appSelectorTargetPath: NodePath = .root

    /// Bumped each time the surface is shown. Views key transient state off it
    /// so a fresh presentation starts clean — the window is retained between
    /// showings, so SwiftUI state would otherwise survive from last time.
    @Published public var presentationCount: Int = 0

    /// True while a text field inside the surface holds focus. The overlay
    /// window intercepts plain keystrokes as commands — a bare letter is a cell
    /// address — so it has to stand down while those keystrokes are text.
    @Published public var isTextFieldFocused: Bool = false

    /// True while a confirmation is on screen. The window has to stand down for
    /// the same reason as above, and for one more: Esc peels a layer off the
    /// surface, so without this it would dismiss the surface out from under the
    /// dialog rather than cancelling it.
    @Published public var isConfirmationPresented: Bool = false

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
        selectedMonitorKey = ScreenConfig.primaryKey
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
        selectedMonitorKey = ScreenConfig.primaryKey
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
        // Use selectedMonitorKey if it exists in this screen set, otherwise fall back
        if screenSet.layouts[selectedMonitorKey] != nil {
            editingRootNode = screenSet.layouts[selectedMonitorKey]
        } else {
            let fallback = preferredMonitorKey(for: screenSet)
            selectedMonitorKey = fallback
            editingRootNode = screenSet.layouts[fallback] ?? screenSet.layouts.values.first
        }
    }

    /// The tree for one monitor of the current screen set.
    ///
    /// Per-screen overlays each render their own display, so they read by key
    /// rather than through `selectedMonitorKey`, which is a single cursor and
    /// can only describe one of them.
    public func rootNode(forMonitor key: String) -> LayoutNode? {
        guard let layout = editingLayout,
              let screenSet = layout.screenSets[safe: selectedScreenSetIndex] else { return nil }
        return screenSet.layouts[key]
    }

    /// Whether the current screen set describes this monitor at all.
    public func hasLayout(forMonitor key: String) -> Bool {
        rootNode(forMonitor: key) != nil
    }

    public func preferredMonitorKey(for screenSet: ScreenConfig) -> String {
        screenSet.layouts.keys.contains(ScreenConfig.primaryKey)
            ? ScreenConfig.primaryKey
            : screenSet.layouts.keys.sorted().first ?? ScreenConfig.primaryKey
    }

    // MARK: - Node Updates (internal)

    private func applyRootNodeUpdate(_ node: LayoutNode, forMonitor key: String) {
        guard var layout = editingLayout,
              selectedScreenSetIndex < layout.screenSets.count else { return }
        layout.screenSets[selectedScreenSetIndex].layouts[key] = node
        editingLayout = layout
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
        }
        // `editingRootNode` tracks the cursor monitor only.
        if key == selectedMonitorKey {
            editingRootNode = node
        }
    }

    private func applyRootNodeUpdate(_ node: LayoutNode) {
        applyRootNodeUpdate(node, forMonitor: selectedMonitorKey)
    }

    // MARK: - Live Update (drag, no undo)

    public func updateRootNodeLive(_ node: LayoutNode) {
        applyRootNodeUpdate(node)
    }

    public func updateRootNodeLive(_ node: LayoutNode, forMonitor key: String) {
        applyRootNodeUpdate(node, forMonitor: key)
    }

    // MARK: - Drag Snapshot

    public func captureDragSnapshot() {
        preDragSnapshot = editingRootNode
    }

    public func captureDragSnapshot(forMonitor key: String) {
        preDragSnapshot = rootNode(forMonitor: key)
    }

    /// Commit trees for several monitors as one undoable edit. The stack is a
    /// property of the whole layout, so moving it between screens has to change
    /// two monitors at once or the layout briefly has none — or two.
    public func commitEdits(_ updates: [String: LayoutNode], actionName: String) {
        guard !updates.isEmpty else { return }

        let previous = updates.keys.reduce(into: [String: LayoutNode]()) { result, key in
            if let node = rootNode(forMonitor: key) { result[key] = node }
        }
        undoManager.registerUndo(withTarget: self) { vm in
            vm.commitEdits(previous, actionName: actionName)
        }
        undoManager.setActionName(actionName)

        for (key, node) in updates {
            applyRootNodeUpdate(node, forMonitor: key)
        }
        autoSave()
    }

    public func commitDragFromSnapshot(to finalNode: LayoutNode) {
        commitDragFromSnapshot(to: finalNode, forMonitor: selectedMonitorKey)
    }

    public func commitDragFromSnapshot(to finalNode: LayoutNode, forMonitor key: String) {
        let prev = preDragSnapshot ?? rootNode(forMonitor: key)
        preDragSnapshot = nil
        undoManager.registerUndo(withTarget: self) { vm in
            vm.commitEdit(prev ?? finalNode, forMonitor: key, actionName: "Resize")
        }
        undoManager.setActionName("Resize")
        applyRootNodeUpdate(finalNode, forMonitor: key)
        autoSave()
    }

    // MARK: - Committed Edit (undo + implicit save)

    public func commitEdit(_ node: LayoutNode, actionName: String = "Edit Layout") {
        commitEdit(node, forMonitor: selectedMonitorKey, actionName: actionName)
    }

    public func commitEdit(
        _ node: LayoutNode,
        forMonitor key: String,
        actionName: String = "Edit Layout"
    ) {
        let prevNode = rootNode(forMonitor: key)
        undoManager.registerUndo(withTarget: self) { vm in
            vm.commitEdit(prevNode ?? node, forMonitor: key, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        applyRootNodeUpdate(node, forMonitor: key)
        autoSave()
    }

    // MARK: - Layout Rename
    //
    // The draft lives here rather than in the pill view so that a click landing
    // anywhere else in the window can commit it — an AppKit-hosted SwiftUI text
    // field doesn't resign focus just because something non-focusable was hit.

    @Published public var renameDraft: String = ""

    public func beginRename(_ layout: Layout) {
        renameDraft = layout.name
        renamingLayoutId = layout.id
    }

    /// Apply the draft name. No-op unless a rename is in progress.
    public func commitRename() {
        guard let id = renamingLayoutId else { return }
        renamingLayoutId = nil
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }

        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        layouts[index].name = trimmed.isEmpty ? "Untitled" : trimmed

        // Renaming a layout must not make it the one being edited.
        if editingLayout?.id == id {
            editingLayout?.name = layouts[index].name
        }
        layoutManager.updateLayout(layouts[index])
        persistLayouts()
    }

    public func cancelRename() {
        renamingLayoutId = nil
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

    /// Write the working list through to the layout manager and the config.
    ///
    /// Both, always. The manager's list is what the menubar shows and what
    /// `refresh()` re-reads whenever the surface opens, so saving only to the
    /// config left a newly added layout in the file and nowhere else — it
    /// appeared to save, then vanished the next time the surface was opened.
    private func persistLayouts() {
        layoutManager.setLayouts(layouts)
        configManager.saveLayouts(layouts)
    }

    /// Persist and apply layout changes to open windows.
    private func autoSave() {
        guard let layout = editingLayout else { return }
        layoutManager.updateLayout(layout)
        layoutManager.applyLayout(layout)
        persistLayouts()
    }

    /// Persist metadata-only changes (name, hotkey) without repositioning windows.
    private func autoSaveMeta() {
        if let layout = editingLayout {
            layoutManager.updateLayout(layout)
        }
        persistLayouts()
    }

    // MARK: - Save / Cancel

    public func saveEdits() {
        guard let layout = editingLayout else { return }
        layoutManager.updateLayout(layout)
        layoutManager.applyLayout(layout)
        originalLayouts = layouts
        persistLayouts()
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
        persistLayouts()
        selectLayout(at: layouts.count - 1)
        beginRename(newLayout)
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
        persistLayouts()
        if let newIdx = layouts.firstIndex(where: { $0.id == copy.id }) {
            selectLayout(at: newIdx)
        }
    }

    /// Delete `layout` and switch to the last remaining one. Falling back to a
    /// layout that definitely exists — rather than the deleted one's index —
    /// keeps the overlay on a valid selection instead of closing.
    public func deleteLayout(_ layout: Layout) {
        guard layouts.count > 1 else { return }
        layouts.removeAll { $0.id == layout.id }
        originalLayouts = layouts
        persistLayouts()
        selectLayout(at: layouts.count - 1)
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

    /// Whether the pane the selector is acting on is a stack (changes behavior).
    public var selectorIsForStack: Bool {
        selectorTargetNode?.type == .stack
    }

    /// The node the selector is acting on, resolved from the path captured when
    /// it opened. Nil if that pane no longer exists.
    private var selectorTargetNode: LayoutNode? {
        guard let root = editingRootNode else { return nil }
        return appSelectorTargetPath.isRoot ? root : appSelectorTargetPath.node(in: root)
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
        showAppSelector(for: selectedNodePath)
    }

    /// Open the selector against a specific pane.
    ///
    /// The path is captured up front rather than re-read from `selectedNodePath`
    /// when the choice is made: `startEditing` resets that field to root, so any
    /// refresh landing while the selector is open would silently retarget the
    /// selection at the whole layout.
    public func showAppSelector(for path: NodePath) {
        guard let root = editingRootNode else { return }
        // Verify it points to a leaf
        let node = path.isRoot ? root : path.node(in: root)
        guard let node, node.type != .columns, node.type != .rows else { return }

        appSelectorTargetPath = path
        selectedNodePath = path
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
        guard let app = filteredApps[safe: index] else { return }
        pinToSelectorTarget(PinnedConfig(application: app.name, bundleId: app.bundleId))
    }

    private func applyWindowSelection(at index: Int) {
        guard let window = filteredWindows[safe: index] else { return }

        // Identify the window by id as well as by app. The id is exact for as
        // long as the window lives, which titles are not — real ones carry
        // volatile detail like a zoom level or an unread count, and two
        // documents can share a name outright. Scoring treats all of these as
        // preferences, so once the id goes stale the pin falls back to the app
        // rather than the pane emptying out.
        pinToSelectorTarget(
            PinnedConfig(
                application: window.application,
                bundleId: window.bundleId,
                windowId: window.id
            )
        )
        // Bring window to front (behind overlay)
        bringWindowToFront(window)
    }

    /// Replace the selector's target pane with a pinned node.
    private func pinToSelectorTarget(_ pinned: PinnedConfig) {
        guard let root = editingRootNode, let target = selectorTargetNode else { return }
        let newNode = LayoutNode(type: .pinned, percentage: target.percentage, pinned: pinned)

        if appSelectorTargetPath.isRoot {
            // Only a leaf root may be replaced wholesale; a container root would
            // mean discarding the entire layout.
            guard root.type != .columns, root.type != .rows else { return }
            commitEdit(newNode)
        } else if let updated = root.replacingNode(
            at: appSelectorTargetPath.indices, with: newNode
        ) {
            commitEdit(updated)
        }
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

    // MARK: - Monitor Selection

    /// Keys in the current screen set, sorted with $PRIMARY first.
    public var monitorKeysForCurrentScreenSet: [String] {
        guard let layout = editingLayout,
              let screenSet = layout.screenSets[safe: selectedScreenSetIndex] else { return [] }
        let keys = Array(screenSet.layouts.keys)
        return keys.sorted { a, b in
            if a == ScreenConfig.primaryKey { return true }
            if b == ScreenConfig.primaryKey { return false }
            return a < b
        }
    }

    /// Display names of currently connected monitors.
    public var connectedDisplayNames: Set<String> {
        Set(displays.map { $0.name })
    }

    /// Whether a monitor key corresponds to a currently connected display.
    public func isMonitorConnected(_ key: String) -> Bool {
        if key == ScreenConfig.primaryKey {
            return !displays.isEmpty
        }
        return connectedDisplayNames.contains(key)
    }

    /// Connected displays not yet in the current screen set.
    public var availableDisplaysToAdd: [String] {
        let currentKeys = Set(monitorKeysForCurrentScreenSet)
        return displays
            .filter { !$0.isMain && !currentKeys.contains($0.name) }
            .map { $0.name }
            .sorted()
    }

    public func selectMonitor(_ key: String) {
        selectedMonitorKey = key
        selectedNodePath = .root
        refreshEditingRootNode()
    }

    public func addMonitorToScreenSet(_ displayName: String) {
        guard let layout = editingLayout,
              let screenSet = layout.screenSets[safe: selectedScreenSetIndex] else { return }

        // The layout has one stack across all its displays, so a new monitor
        // starts empty — unless nothing holds the stack yet.
        let defaultNode: LayoutNode = screenSet.containsStack ? .empty() : .stackAll()

        guard let updated = layout.addingDisplay(
            key: displayName,
            defaultNode: defaultNode,
            toScreenSetAt: selectedScreenSetIndex
        ) else { return }

        syncEditingLayout(updated)
        selectedMonitorKey = displayName
        refreshEditingRootNode()
        // Adding a display is a real change; it was previously left unsaved.
        layoutManager.updateLayout(updated)
        persistLayouts()
    }

    public func removeMonitorFromScreenSet(_ key: String) {
        guard key != ScreenConfig.primaryKey,
              var layout = editingLayout,
              let updated = layout.removingDisplay(key: key, fromScreenSetAt: selectedScreenSetIndex) else { return }
        syncEditingLayout(updated)
        if selectedMonitorKey == key {
            selectedMonitorKey = ScreenConfig.primaryKey
        }
        refreshEditingRootNode()
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
