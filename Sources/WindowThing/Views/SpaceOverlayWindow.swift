import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WindowThingCore
import WindowThingViewModel

// MARK: - Drag payload

/// Identifies a pane being dragged onto another. Only its path in the layout
/// tree travels — the nodes are looked up on drop, so a stale subtree can never
/// be written back.
struct DraggedPane: Codable, Transferable {
    let indices: [Int]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .layoutPane)
    }
}

extension UTType {
    static let layoutPane = UTType(exportedAs: "com.windowthing.layout-pane")
}

enum SplitAxis {
    case vertical, horizontal
}

/// Which edge of a pane a split button sits on.
///
/// The button marks one end of the divider it will draw. A vertical divider
/// runs between the top and bottom edges, so the buttons at the middle of those
/// edges are its two ends and both create it; the left and right buttons are
/// likewise the two ends of a horizontal divider. Each pair is one action
/// offered at whichever end is nearer.
enum SplitEdge: CaseIterable {
    case top, bottom, leading, trailing

    /// `.vertical` means a vertical divider — columns.
    var axis: SplitAxis {
        switch self {
        case .top, .bottom:       return .vertical
        case .leading, .trailing: return .horizontal
        }
    }

    /// What the button does, for the tooltip.
    var action: String {
        axis == .vertical ? "Split into columns" : "Split into rows"
    }

    /// Where it sits, which is the only thing separating the two ends of the
    /// same divider. Spelled out so the accessibility labels stay unique —
    /// four controls sharing a name are indistinguishable to VoiceOver and to
    /// anything driving the interface.
    var origin: String {
        switch self {
        case .top:      return "from the top"
        case .bottom:   return "from the bottom"
        case .leading:  return "from the left"
        case .trailing: return "from the right"
        }
    }

    /// The icons the pane bar used, kept so the two agree.
    var systemName: String {
        axis == .vertical ? "rectangle.split.2x1" : "rectangle.split.1x2"
    }
}

// MARK: - Palette

/// The surface runs in the opposite appearance to the system, so nothing in it
/// hard-codes a colour. `Color.primary` covers the foreground (it already flips
/// with the scheme); `ground` is its opposite, for the slabs the foreground
/// sits on.
private extension ColorScheme {
    var ground: Color { self == .dark ? .black : .white }
}

// MARK: - Window

/// The app's single activation surface, in the spirit of Mission Control or
/// Launchpad: it covers the whole display including the menu bar, blurs whatever
/// is behind it, and draws the layout's cells at their true on-screen positions
/// so every control sits directly over the region it acts on.
///
/// This is both the window browser and the layout editor — there is no separate
/// editor window. Cells are drawn where the windows actually are, so editing the
/// layout and rearranging windows are the same gesture vocabulary.
final class SpaceOverlayWindow: NSWindow {
    let viewModel: OverlayViewModel
    /// The screen this overlay covers. One window per screen, each showing that
    /// screen's own slice of the layout. Named to avoid NSWindow.screen.
    let targetScreen: NSScreen
    /// This screen's key in a screen set: `$PRIMARY` for the main display.
    let monitorKey: String
    /// Closing any overlay closes them all — it's one surface across screens.
    private let dismissAll: () -> Void

    init(
        viewModel: OverlayViewModel,
        screen: NSScreen,
        monitorKey: String,
        dismissAll: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.targetScreen = screen
        self.monitorKey = monitorKey
        self.dismissAll = dismissAll

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Above the menu bar and the Dock, the way Mission Control sits.
        level = .screenSaver
        appearance = Self.invertedSystemAppearance()
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(
            rootView: SpaceOverlayView(
                viewModel: viewModel,
                monitorKey: monitorKey,
                dismiss: dismissAll
            )
        )
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = host
    }

    /// The surface deliberately takes the opposite appearance to the system, so
    /// it reads as a layer over the desktop rather than part of it. Every colour
    /// in the view tree is derived from the appearance, so this one line flips
    /// the whole palette.
    private static func invertedSystemAppearance() -> NSAppearance? {
        let systemIsDark = NSApp.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSAppearance(named: systemIsDark ? .aqua : .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// Routes ⌘Z through the view model's undo stack rather than the app's.
    override var undoManager: UndoManager? { viewModel.undoManager }

    /// Set while capturing screenshots — nothing holds key focus in an
    /// automated session and the surface would dismiss itself immediately.
    var staysVisibleWhenInactive = false

    /// Present this screen's overlay. Shared model state — refresh, the focused
    /// window, the presentation counter — is handled once by the controller.
    func show() {
        // Re-read on every open: the system may have switched mode, or crossed
        // an auto-appearance boundary, since the window was built.
        appearance = Self.invertedSystemAppearance()

        // Re-fit: resolution may have changed since the window was built.
        setFrame(targetScreen.frame, display: false)
        (contentView as? NSHostingView<SpaceOverlayView>)?.frame =
            NSRect(origin: .zero, size: targetScreen.frame.size)

        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    /// Open the surface with the cell picker already up for the frontmost window.
    func showCellPickerForFocusedWindow() {
        if !isVisible { show() }
        if let window = viewModel.selectedMoveWindow {
            viewModel.showCellPicker(for: window)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        dismissTopmostLayer()
    }

    /// Esc and the close button dismiss the whole surface, not one screen of it.
    private func closeSurface() {
        dismissAll()
    }

    override func resignKey() {
        super.resignKey()
        guard !staysVisibleWhenInactive else { return }

        // Our own transient windows take key focus too — a context menu, a
        // menu-button popup — and destroying the view that owns an open menu
        // (deleting a layout, say) can leave key focus unclaimed. Only dismiss
        // once AppKit has settled and the user has genuinely left the app.
        // Deliberately no re-keying here: while a menu is tracking it owns key
        // focus, and grabbing it back would dismiss the menu out from under the
        // user. Suppressing the hide is enough — the surface stays usable by
        // mouse, and a click on it restores key focus.
        // With one overlay per screen, focus moving between them is still "our
        // app is active" — only a genuine switch away closes the surface.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.staysVisibleWhenInactive else { return }
            guard !NSApp.isActive else { return }
            self.dismissAll()
        }
    }

    /// Esc peels one layer at a time: selector, then picker, then selection,
    /// then the surface itself.
    private func dismissTopmostLayer() {
        // A confirmation is the topmost layer and handles its own dismissal.
        if viewModel.isConfirmationPresented { return }

        if viewModel.isTextFieldFocused, viewModel.renamingLayoutId == nil {
            // Searching: give focus back before the surface starts closing.
            viewModel.isSearchFieldFocused = false
            makeFirstResponder(nil)
            return
        }
        if viewModel.renamingLayoutId != nil {
            viewModel.cancelRename()
            makeFirstResponder(nil)
            return
        }
        if viewModel.isAppSelectorVisible { viewModel.hideAppSelector(); return }
        if viewModel.isCellPickerVisible { viewModel.hideCellPicker(); return }
        closeSurface()
    }

    override func sendEvent(_ event: NSEvent) {
        // A click anywhere outside the rename field ends the rename. SwiftUI
        // won't do this for us: clicking a non-focusable area of an
        // NSHostingView leaves the text field as first responder.
        if event.type == .leftMouseDown,
           viewModel.renamingLayoutId != nil,
           !clickLandsInFirstResponder(event) {
            viewModel.commitRename()
            makeFirstResponder(nil)
        }

        if event.type == .keyDown, handleKeyDown(event) { return }

        // Shift toggles app/window mode while the selector is up.
        if event.type == .flagsChanged,
           viewModel.isAppSelectorVisible,
           event.modifierFlags.contains(.shift) {
            viewModel.toggleAppSelectorMode()
        }

        super.sendEvent(event)
    }

    /// Whether a mouse event falls inside the view currently holding focus —
    /// while renaming that's the text field's editor, and clicks there should
    /// just move the caret.
    private func clickLandsInFirstResponder(_ event: NSEvent) -> Bool {
        guard let view = firstResponder as? NSView else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    /// Returns true when the event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Escape
        if event.keyCode == 53 {
            dismissTopmostLayer()
            return true
        }

        // While a text field has focus its keystrokes are text, not commands:
        // a bare letter is a cell address here, and space closes the surface.
        if viewModel.isTextFieldFocused { return false }

        // A confirmation owns the keyboard while it is up — including Esc, which
        // should cancel it rather than close the surface behind it.
        if viewModel.isConfirmationPresented { return false }

        // ⌘Z / ⇧⌘Z — the surface saves as you go, so undo is the only way back.
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if modifiers.contains(.shift) {
                viewModel.undoManager.redo()
            } else {
                viewModel.undoManager.undo()
            }
            return true
        }

        // ⌘1…⌘9 apply a layout. Plain digits are reserved for cell addresses,
        // which are the surface's primary verb.
        if modifiers == [.command],
           let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), digit >= 1, digit <= viewModel.layouts.count {
            viewModel.selectLayout(at: digit - 1)
            return true
        }

        if viewModel.isAppSelectorVisible {
            if let handled = handleAppSelectorKey(event), handled { return true }
            return false   // let letters and backspace reach the search field
        }

        if viewModel.isCellPickerVisible { return false }

        guard modifiers.isEmpty, let chars = event.charactersIgnoringModifiers else { return false }

        if event.keyCode == 49 {   // Space
            closeSurface()
            return true
        }

        // A bare cell address moves the window that was focused on activation.
        if chars.count == 1, let address = CellAddress(string: chars) {
            moveSelectedWindow(to: address)
            closeSurface()
            return true
        }

        return false
    }

    /// Handle key events while the app selector is visible.
    /// Returns true if consumed, nil to let the event through to SwiftUI.
    private func handleAppSelectorKey(_ event: NSEvent) -> Bool? {
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let ch = chars.first else { return nil }

        if let digit = ch.wholeNumberValue, digit >= 1, digit <= 9 {
            viewModel.applyAppSelectorSelection(at: digit - 1)
            return true
        }

        if event.keyCode == 36 {   // Return
            viewModel.applyAppSelectorSelection(at: viewModel.appSelectorSelectedIndex)
            return true
        }

        let columnCount = 4   // matches the selector grid's adaptive width
        switch event.keyCode {
        case 123:   // left
            viewModel.appSelectorSelectedIndex = max(0, viewModel.appSelectorSelectedIndex - 1)
            return true
        case 124:   // right
            viewModel.appSelectorSelectedIndex = min(viewModel.appSelectorSelectedIndex + 1, maxSelectorIndex)
            return true
        case 126:   // up
            let newIdx = viewModel.appSelectorSelectedIndex - columnCount
            if newIdx >= 0 { viewModel.appSelectorSelectedIndex = newIdx }
            return true
        case 125:   // down
            let newIdx = viewModel.appSelectorSelectedIndex + columnCount
            if newIdx <= maxSelectorIndex { viewModel.appSelectorSelectedIndex = newIdx }
            return true
        default:
            return nil
        }
    }

    private var maxSelectorIndex: Int {
        let count: Int
        if viewModel.appSelectorMode == .app {
            count = viewModel.filteredApps.count
        } else if viewModel.selectorIsForStack {
            count = viewModel.stackWindows.count
        } else {
            count = viewModel.filteredWindows.count
        }
        return max(0, count - 1)
    }

    private func moveSelectedWindow(to address: CellAddress) {
        guard let window = viewModel.selectedMoveWindow else { return }
        let displays = viewModel.displays.isEmpty ? WindowManager.shared.getDisplays() : viewModel.displays
        try? LayoutManager.shared.moveWindow(window, toCellAt: address, displays: displays)
        viewModel.refreshRunningApps()
    }
}

// MARK: - Backdrop

/// Live blur of the desktop behind the window. `.behindWindow` blending is what
/// makes this read as a system surface rather than a translucent panel.
private struct BlurBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Flattened layout geometry

/// A leaf cell resolved to its rect in overlay-window coordinates. Because the
/// window covers the display exactly, that rect is also where the real windows
/// assigned to this cell will land.
private struct TileSlot: Identifiable {
    let path: NodePath
    let node: LayoutNode
    let rect: CGRect
    let cellIndex: Int?

    var id: NodePath { path }
    var addressLabel: String? { cellIndex.flatMap { CellAddress.from(index: $0)?.stringValue } }
}

/// The boundary between two siblings — a resize target.
private struct DividerSlot: Identifiable {
    let parentPath: NodePath
    let index: Int
    let axis: SplitAxis
    let rect: CGRect
    let aPct: Double
    let bPct: Double
    let containerLength: CGFloat
    /// Sum of *every* sibling's percentage in this container, which is what
    /// `containerLength` spans. Percentages need not add to 100 — flattenTree
    /// normalises by this sum — so converting points to percent needs it.
    let siblingsPctSum: Double

    var id: String { "\(parentPath.indices.map(String.init).joined(separator: "."))#\(index)" }
}

private let dividerThickness: CGFloat = 14

/// Bumped each time the thumbnail cache refreshes.
///
/// Carried through the environment rather than passed down as a property.
/// As a property it was part of every intermediate view's value, so a capture
/// invalidated the whole chooser tree and forced a full re-layout — measured at
/// ~112ms of blocked main thread every few seconds. Read from the environment,
/// only the tiles that actually draw a thumbnail are invalidated.
private struct ThumbnailRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var thumbnailRevision: Int {
        get { self[ThumbnailRevisionKey.self] }
        set { self[ThumbnailRevisionKey.self] = newValue }
    }
}

/// Walk the tree once, resolving every leaf and every sibling boundary to a
/// concrete rect. Doing this up front (rather than nesting HStacks) keeps each
/// cell's true screen rect available for window hit-testing.
private func flattenTree(
    _ node: LayoutNode,
    root: LayoutNode,
    path: NodePath,
    rect: CGRect,
    tiles: inout [TileSlot],
    dividers: inout [DividerSlot]
) {
    func pctSum(_ children: [LayoutNode]) -> Double {
        let defaultP = children.isEmpty ? 100.0 : 100.0 / Double(children.count)
        return max(children.reduce(0.0) { $0 + ($1.percentage ?? defaultP) }, 0.001)
    }

    func childLengths(_ children: [LayoutNode], total: CGFloat) -> [CGFloat] {
        let defaultP = children.isEmpty ? 100.0 : 100.0 / Double(children.count)
        return children.map { CGFloat(($0.percentage ?? defaultP) / pctSum(children)) * total }
    }

    switch node.type {
    case .columns:
        guard let cols = node.columns, !cols.isEmpty else { break }
        let widths = childLengths(cols, total: rect.width)
        var x = rect.minX
        for (i, child) in cols.enumerated() {
            let childRect = CGRect(x: x, y: rect.minY, width: widths[i], height: rect.height)
            flattenTree(child, root: root, path: path.appending(i), rect: childRect,
                        tiles: &tiles, dividers: &dividers)
            x += widths[i]
            if i < cols.count - 1 {
                let defaultP = 100.0 / Double(cols.count)
                dividers.append(DividerSlot(
                    parentPath: path, index: i, axis: .vertical,
                    rect: CGRect(x: x - dividerThickness / 2, y: rect.minY,
                                 width: dividerThickness, height: rect.height),
                    aPct: cols[i].percentage ?? defaultP,
                    bPct: cols[i + 1].percentage ?? defaultP,
                    containerLength: rect.width,
                    siblingsPctSum: pctSum(cols)
                ))
            }
        }
        return

    case .rows:
        guard let rs = node.rows, !rs.isEmpty else { break }
        let heights = childLengths(rs, total: rect.height)
        var y = rect.minY
        for (i, child) in rs.enumerated() {
            let childRect = CGRect(x: rect.minX, y: y, width: rect.width, height: heights[i])
            flattenTree(child, root: root, path: path.appending(i), rect: childRect,
                        tiles: &tiles, dividers: &dividers)
            y += heights[i]
            if i < rs.count - 1 {
                let defaultP = 100.0 / Double(rs.count)
                dividers.append(DividerSlot(
                    parentPath: path, index: i, axis: .horizontal,
                    rect: CGRect(x: rect.minX, y: y - dividerThickness / 2,
                                 width: rect.width, height: dividerThickness),
                    aPct: rs[i].percentage ?? defaultP,
                    bPct: rs[i + 1].percentage ?? defaultP,
                    containerLength: rect.height,
                    siblingsPctSum: pctSum(rs)
                ))
            }
        }
        return

    default:
        break
    }

    tiles.append(TileSlot(path: path, node: node, rect: rect, cellIndex: root.leafIndex(at: path)))
}

// MARK: - Root view

struct SpaceOverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    /// The screen set key this overlay edits — its own screen, not a cursor.
    let monitorKey: String
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var scheme

    @State private var closeHovering = false
    @State private var dropTarget: NodePath?
    @State private var hoveredPath: NodePath?

    private var root: LayoutNode? { viewModel.rootNode(forMonitor: monitorKey) }

    /// The display this overlay covers.
    private var display: Display? {
        if monitorKey == ScreenConfig.primaryKey {
            return viewModel.displays.first(where: { $0.isMain })
        }
        return viewModel.displays.first(where: { $0.name == monitorKey })
    }

    /// Every window, on every screen. The layout draws from a single pool, so
    /// a pane here can claim a window currently sitting on another display —
    /// pinning it is how you move it across.
    private var managedWindows: [WTWindow] {
        viewModel.runningWindows.filter {
            $0.pid != ProcessInfo.processInfo.processIdentifier
        }
    }

    /// Global centre point, in the same space as `Display.frame`.
    private func centre(of window: WTWindow) -> CGPoint {
        CGPoint(
            x: window.frame.x + window.frame.width / 2,
            y: window.frame.y + window.frame.height / 2
        )
    }

    var body: some View {
        GeometryReader { geo in
            let canvas = CGRect(origin: .zero, size: geo.size)
            let _ = RenderProbe.breadcrumb("SpaceOverlayView.body")
            let (tiles, dividers) = RenderProbe.measure("SpaceOverlayView.resolve") {
                resolve(in: canvas)
            }
            let _ = RenderProbe.flushTallies("previous pass built")

            ZStack {
                BlurBackdrop()
                    .ignoresSafeArea()

                // Blur alone leaves a bright, milky field; the scrim is what
                // makes the overlaid controls legible against any desktop.
                scheme.ground.opacity(0.42)
                    .ignoresSafeArea()

                if root == nil {
                    unmappedDisplayNotice
                } else {
                    cellCanvas(tiles: tiles, dividers: dividers)
                }

                // The chrome is the one layer that always wins: a cell's own
                // controls must never draw over the layout bar.
                chrome(tiles: tiles)
                    .zIndex(10)

                if viewModel.isAppSelectorVisible {
                    modalScrim { viewModel.hideAppSelector() }
                    AppSelectorView(viewModel: viewModel)
                }

                if viewModel.isCellPickerVisible {
                    modalScrim { viewModel.hideCellPicker() }
                    CellPickerView(viewModel: viewModel, onDismiss: {})
                }
            }
        }
    }

    /// A layout describes named screens, so a display it has never seen has no
    /// tree at all. Rather than a blank surface, offer to add it.
    private var unmappedDisplayNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 34))
                .foregroundColor(.primary.opacity(0.5))

            Text(viewModel.editingLayout.map { "“\($0.name)” doesn't cover this display" }
                ?? "No layout for this display")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)

            if let name = display?.name {
                Button {
                    viewModel.addMonitorToScreenSet(name)
                } label: {
                    Text("Add \(name) to this layout")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.accentColor.opacity(0.35)))
                        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resolve(in canvas: CGRect) -> ([TileSlot], [DividerSlot]) {
        guard let root else { return ([], []) }
        var tiles: [TileSlot] = []
        var dividers: [DividerSlot] = []
        flattenTree(root, root: root, path: .root, rect: canvas, tiles: &tiles, dividers: &dividers)
        return (tiles, dividers)
    }

    private func modalScrim(_ onTap: @escaping () -> Void) -> some View {
        scheme.ground.opacity(0.4)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    // MARK: - Canvas

    /// Built in its own function with an explicit return type.
    ///
    /// Inline in the ForEach below, Swift 6 gave up type-checking the
    /// expression once this gained its fourteenth argument — the same failure
    /// the compact layout preview hit. Naming the type is what makes it
    /// tractable again.
    private func cell(for slot: TileSlot) -> CellView {
        CellView(
            slot: slot,
            windows: windows(for: slot),
            isHovered: hoveredPath == slot.path,
            isDropTarget: dropTarget == slot.path,
            runningApps: viewModel.runningApps,
            topInset: chromeOverlap(for: slot),
            onChoose: { choose($0, on: slot) },
            onChooseApp: { chooseApp($0, on: slot) },
            onChooseEmpty: { setType(slot, to: .empty) },
            onChooseStack: { setType(slot, to: .stack) },
            onTextFocusChanged: { viewModel.isSearchFieldFocused = $0 },
            sessionID: viewModel.presentationCount,
            onSplit: { split(slot, edge: $0) },
            onDelete: { deleteCell(slot) }
        )
    }

    private func cellCanvas(tiles: [TileSlot], dividers: [DividerSlot]) -> some View {
        ZStack {
            ForEach(tiles) { slot in
                // Everything interactive attaches before `.position`, and
                // `.position` comes last.
                //
                // `.position` expands to fill its parent and places the content
                // at a point inside it, so a modifier applied after it lands on
                // a canvas-sized wrapper rather than on the pane. Every pane's
                // hover region was therefore the whole canvas, and in a ZStack
                // the last one drawn sits on top and takes every hover — so
                // only the final pane ever looked hovered, and only the final
                // pane could be a drop target.
                cell(for: slot)
                .frame(width: slot.rect.width, height: slot.rect.height)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hoveredPath = slot.path }
                    else if hoveredPath == slot.path { hoveredPath = nil }
                }
                .draggable(DraggedPane(indices: slot.path.indices)) {
                    PaneDragPreview(
                        label: slot.addressLabel,
                        node: slot.node,
                        windowCount: windows(in: slot.rect).count
                    )
                }
                .dropDestination(for: DraggedPane.self) { items, _ in
                    handlePaneDrop(items, on: slot)
                } isTargeted: { targeted in
                    if targeted { dropTarget = slot.path }
                    else if dropTarget == slot.path { dropTarget = nil }
                }
                .position(x: slot.rect.midX, y: slot.rect.midY)
            }

            ForEach(dividers) { divider in
                DividerHandle(
                    divider: divider,
                    onDragStarted: { viewModel.captureDragSnapshot(forMonitor: monitorKey) },
                    onChanging: { a, b in resize(divider, a: a, b: b, live: true) },
                    onCommitted: { a, b in resize(divider, a: a, b: b, live: false) }
                )
                .frame(width: divider.rect.width, height: divider.rect.height)
                .position(x: divider.rect.midX, y: divider.rect.midY)
            }
        }
        .ignoresSafeArea()
        // A drag gesture reports translation in whatever coordinate space it is
        // given, and the default is the dragged view's own. A divider handle is
        // `.position`-ed from the layout it is resizing, so it moves as you drag
        // it — measuring the drag against the handle's own frame means measuring
        // it against something the drag is currently moving, which oscillates.
        // The dividers read their translation in this space instead, which is
        // pinned to the canvas and stays put.
        .coordinateSpace(name: Self.canvasSpace)
        .environment(\.thumbnailRevision, viewModel.thumbnailRevision)
    }

    /// Fixed reference frame for divider drags. See `.coordinateSpace` above.
    fileprivate static let canvasSpace = "windowthing.layout-canvas"

    /// How far the floating chrome reaches into a pane. Only panes touching the
    /// top of the screen are affected; everything lower gets nothing.
    private func chromeOverlap(for slot: TileSlot) -> CGFloat {
        // Only the primary screen carries the bar; elsewhere the close button
        // is the whole of the chrome, and it is a small control in the corner
        // rather than a band across the top.
        guard showsLayoutBar else { return 0 }
        let barBottom: CGFloat = showsScopeBar ? 152 : 100
        return max(0, barBottom - slot.rect.minY)
    }

    /// What a pane offers. Everything except the stack is a chooser: it shows
    /// every running window so any of them can be pinned there, including when
    /// the pane already holds a pin. The stack instead shows what's really in
    /// it, since its whole job is to catch the windows nothing else claimed.
    private func windows(for slot: TileSlot) -> [WTWindow] {
        managedWindows
    }

    /// A window belongs to the cell containing its centre point.
    ///
    /// No longer decides what a pane lists — every pane lists everything now —
    /// but the drag preview still says how many windows are physically sitting
    /// in the pane being dragged, which is a question about the screen rather
    /// than about the layout.
    private func windows(in rect: CGRect) -> [WTWindow] {
        managedWindows.filter { rect.contains(localCentre(of: $0)) }
    }

    /// Window frames are global; the overlay's coordinates are display-local.
    private func localCentre(of window: WTWindow) -> CGPoint {
        let origin = display?.frame ?? WindowFrame(x: 0, y: 0, width: 0, height: 0)
        return CGPoint(
            x: window.frame.x + window.frame.width / 2 - origin.x,
            y: window.frame.y + window.frame.height / 2 - origin.y
        )
    }



    /// Clicking a window in a chooser pane pins its app there. In the stack
    /// there's nothing to choose — the click just brings the window forward.
    private func choose(_ window: WTWindow, on slot: TileSlot) {
        // Pin this window specifically, identified three ways so the pin degrades
        // instead of breaking: the id names it exactly for as long as it exists,
        // the title recognises it again after a relaunch, and the app catches
        // everything else. `LayoutManager.windowMatchScore` ranks them in that
        // order, so a pane falls back rather than emptying out.
        let pinned = PinnedConfig(
            application: window.application,
            bundleId: window.bundleId,
            windowTitles: window.title.isEmpty ? nil : [window.title],
            windowId: window.id
        )
        let node = LayoutNode(type: .pinned, percentage: slot.node.percentage, pinned: pinned)
        replaceNode(at: slot.path, with: node, actionName: "Pin Window")
    }

    /// Choosing an app pins it without tying the pane to any one of its windows.
    private func chooseApp(_ app: RunningAppInfo, on slot: TileSlot) {
        guard slot.node.type != .stack else { return }
        let pinned = PinnedConfig(application: app.name, bundleId: app.bundleId)
        let node = LayoutNode(type: .pinned, percentage: slot.node.percentage, pinned: pinned)
        replaceNode(at: slot.path, with: node, actionName: "Pin App")
    }



    // MARK: - Chrome

    /// Only screen sets remain worth choosing here — each monitor now has its
    /// own overlay, so it never needs selecting.
    private var showsScopeBar: Bool {
        (viewModel.editingLayout?.screenSets.count ?? 0) > 1
    }

    /// The layout bar is drawn on the primary display only.
    ///
    /// The surface puts a window on every screen, and repeating the bar on each
    /// one read as per-display state — which it is not. Switching layout is
    /// global, so the same control on three screens invited the idea that each
    /// screen had its own. A secondary screen is there to show that display's
    /// panes; it gets those and the close button, nothing else.
    private var showsLayoutBar: Bool {
        monitorKey == ScreenConfig.primaryKey
    }

    /// Close is laid out independently of the bar: pinned to the corner, and on
    /// every screen, where the bar is only on one.
    private func chrome(tiles: [TileSlot]) -> some View {
        ZStack(alignment: .top) {
            if showsLayoutBar {
                VStack(spacing: 12) {
                    LayoutSwitcherBar(viewModel: viewModel)
                        .padding(.top, 24)

                    if showsScopeBar {
                        ScopeBar(viewModel: viewModel)
                    }

                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    closeButton
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .padding(.leading, 24)
        }
        .allowsHitTesting(true)
    }

    /// Its own control in the corner rather than the last item in the layout
    /// bar. In the bar it sat after the layouts and the add button, so closing
    /// the editor looked like one more thing you could do to a layout — and the
    /// bar is not on every screen, while a way out has to be.
    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.75))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                )
                .overlay(
                    Circle().strokeBorder(
                        Color.primary.opacity(closeHovering ? 0.45 : 0.12),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { closeHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: closeHovering)
        .help("Close (esc)")
        .accessibilityLabel("Close layout surface")
        .accessibilityIdentifier("surface.close")
    }

    // MARK: - Window actions



    /// Dropping one pane on another exchanges them. Only the contents move —
    /// each position keeps its own size, so the layout's proportions hold.
    private func handlePaneDrop(_ items: [DraggedPane], on target: TileSlot) -> Bool {
        dropTarget = nil
        guard let dragged = items.first, let root else { return false }

        let source = NodePath(dragged.indices)
        guard source != target.path else { return false }

        // Both paths come from the flattened tree, so both are leaves and
        // neither can contain the other — the two replacements are independent.
        guard let sourceNode = source.isRoot ? root : source.node(in: root),
              let targetNode = target.path.isRoot ? root : target.path.node(in: root)
        else { return false }

        guard let step = root.replacingNode(
                at: source.indices,
                with: targetNode.withPercentage(sourceNode.percentage ?? 100)
              ),
              let updated = step.replacingNode(
                at: target.path.indices,
                with: sourceNode.withPercentage(targetNode.percentage ?? 100)
              )
        else { return false }

        viewModel.commitEdit(updated, forMonitor: monitorKey, actionName: "Swap Panes")
        return true
    }

    // MARK: - Layout edits
    //
    // Every edit goes through `commitEdit`, which registers undo, persists the
    // config, and re-applies the layout — so the real windows follow the cells
    // as you rearrange them.

    private func replaceNode(at path: NodePath, with newNode: LayoutNode, actionName: String) {
        guard let root, let updated = root.replacingNode(at: path.indices, with: newNode) else { return }
        viewModel.commitEdit(updated, forMonitor: monitorKey, actionName: actionName)
    }

    private func setType(_ slot: TileSlot, to type: LayoutType) {
        if type == .stack {
            moveStack(to: slot)
            return
        }
        replaceNode(at: slot.path, with: slot.node.withType(type), actionName: "Change Cell")
    }

    /// A layout has exactly one stack, so making a pane the stack relocates it
    /// rather than creating a second one: the stack moves here, and this pane's
    /// contents take over the position the stack just left.
    /// Where the layout's one stack currently lives, across every monitor of
    /// the current screen set.
    private func stackLocation() -> (key: String, path: NodePath)? {
        guard let layout = viewModel.editingLayout,
              let screenSet = layout.screenSets[safe: viewModel.selectedScreenSetIndex]
        else { return nil }

        for (key, node) in screenSet.layouts {
            if let indices = node.findStackLocation() {
                return (key, NodePath(indices))
            }
        }
        return nil
    }

    private func moveStack(to slot: TileSlot) {
        guard let root, slot.node.type != .stack else { return }

        guard let existing = stackLocation() else {
            // Nothing to move — this layout has no stack yet.
            replaceNode(at: slot.path, with: slot.node.withType(.stack), actionName: "Set Stack")
            return
        }

        // The stack is on another screen: swap the two panes across monitors in
        // one edit, so the layout is never left with none or two.
        guard existing.key == monitorKey else {
            moveStackAcrossMonitors(from: existing, to: slot)
            return
        }

        let stackPath = existing.path
        guard let stackNode = stackPath.isRoot ? root : stackPath.node(in: root) else { return }

        // Both are leaves, so neither path contains the other and the two
        // replacements are independent. Percentages stay with the positions.
        guard let step = root.replacingNode(
                at: slot.path.indices,
                with: stackNode.withPercentage(slot.node.percentage ?? 100)
              ),
              let updated = step.replacingNode(
                at: stackPath.indices,
                with: slot.node.withPercentage(stackNode.percentage ?? 100)
              )
        else { return }

        viewModel.commitEdit(updated, forMonitor: monitorKey, actionName: "Move Stack")
    }

    /// Exchange this pane with the stack pane on another monitor.
    private func moveStackAcrossMonitors(
        from existing: (key: String, path: NodePath),
        to slot: TileSlot
    ) {
        guard let root,
              let otherRoot = viewModel.rootNode(forMonitor: existing.key),
              let stackNode = existing.path.isRoot
                ? otherRoot : existing.path.node(in: otherRoot)
        else { return }

        // Percentages belong to the positions, so each node adopts its new slot's.
        guard let here = root.replacingNode(
                at: slot.path.indices,
                with: stackNode.withPercentage(slot.node.percentage ?? 100)
              ),
              let there = otherRoot.replacingNode(
                at: existing.path.indices,
                with: slot.node.withPercentage(stackNode.percentage ?? 100)
              )
        else { return }

        viewModel.commitEdits(
            [monitorKey: here, existing.key: there],
            actionName: "Move Stack"
        )
    }

    private func split(_ slot: TileSlot, edge: SplitEdge) {
        let halves = [slot.node.withPercentage(50), LayoutNode.empty(percentage: 50)]
        let newNode = edge.axis == .vertical
            ? LayoutNode.columns(halves)
            : LayoutNode.rows(halves)
        replaceNode(at: slot.path, with: newNode, actionName: "Split Cell")
        viewModel.selectedNodePath = slot.path.appending(1)
    }

    private func deleteCell(_ slot: TileSlot) {
        guard let root else { return }

        // Walk up past containers that hold nothing but this pane. Splitting and
        // deleting leaves such wrappers behind, and `removingColumn`/`removingRow`
        // refuse to empty a container — so detaching the leaf alone would fail and
        // the pane would appear undeletable.
        var target = slot.path
        while let parentPath = target.parent,
              let parent = parentPath.isRoot ? root : parentPath.node(in: root),
              childCount(of: parent) == 1 {
            target = parentPath
        }

        if let parentPath = target.parent,
           let index = target.indexInParent,
           let parent = parentPath.isRoot ? root : parentPath.node(in: root),
           let trimmed = parent.type == .columns
                ? parent.removingColumn(at: index)
                : parent.removingRow(at: index),
           let updated = root.replacingNode(at: parentPath.indices, with: trimmed) {
            viewModel.commitEdit(updated, forMonitor: monitorKey, actionName: "Remove Cell")
            return
        }

        // Nothing to detach from — a lone root pane can only be cleared.
        replaceNode(at: slot.path,
                    with: .empty(percentage: slot.node.percentage ?? 100),
                    actionName: "Clear Cell")
    }

    private func childCount(of node: LayoutNode) -> Int {
        switch node.type {
        case .columns: return node.columns?.count ?? 0
        case .rows:    return node.rows?.count ?? 0
        default:       return 0
        }
    }

    private func resize(_ divider: DividerSlot, a: Double, b: Double, live: Bool) {
        guard let root else { return }
        let parent = divider.parentPath.isRoot ? root : divider.parentPath.node(in: root)
        guard let parent else { return }

        var children = parent.type == .columns ? (parent.columns ?? []) : (parent.rows ?? [])
        guard divider.index + 1 < children.count else { return }
        children[divider.index] = children[divider.index].withPercentage(a)
        children[divider.index + 1] = children[divider.index + 1].withPercentage(b)

        let newParent = parent.type == .columns ? parent.withColumns(children) : parent.withRows(children)
        guard let updated = root.replacingNode(at: divider.parentPath.indices, with: newParent) else { return }

        if live {
            viewModel.updateRootNodeLive(updated, forMonitor: monitorKey)
        } else {
            viewModel.commitDragFromSnapshot(to: updated, forMonitor: monitorKey)
        }
    }
}

// MARK: - Cell

private struct CellView: View {
    let slot: TileSlot
    let windows: [WTWindow]
    let isHovered: Bool
    let isDropTarget: Bool
    let runningApps: [RunningAppInfo]
    /// Extra headroom for panes that reach under the floating layout bar.
    let topInset: CGFloat
    let onChoose: (WTWindow) -> Void
    let onChooseApp: (RunningAppInfo) -> Void
    let onChooseEmpty: () -> Void
    let onChooseStack: () -> Void
    let onTextFocusChanged: (Bool) -> Void
    let sessionID: Int
    let onSplit: (SplitEdge) -> Void
    let onDelete: () -> Void

    /// The four ways to split, one on each edge.
    ///
    /// The pane bar that used to carry two of these is gone: a permanent strip
    /// of chrome in every pane, for two buttons and a number. On the edges the
    /// button's position says which side the new pane lands on, which the two
    /// axis buttons never could.
    /// Which split button the pointer is on, if any. Drives both the button's
    /// own emphasis and the preview drawn across the pane.
    @State private var hoveredSplit: SplitEdge?

    private var splitButtons: some View {
        ZStack {
            // Pushed clear of the layout bar, which is opaque and floats over
            // the top of the canvas. `topInset` is however far this pane
            // reaches under it, and zero for every pane that does not.
            splitButton(.top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, topInset)
            splitButton(.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            splitButton(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            splitButton(.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .padding(6)
        // Only while the pointer is in the pane. Four buttons on every pane at
        // all times would be more chrome than the bar they replace.
        .opacity(isHovered ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        // The preview follows the pointer between buttons, so it has to fade
        // on the edge changing as well as on hover starting and stopping.
        .animation(.easeOut(duration: 0.12), value: hoveredSplit)
    }

    private func splitButton(_ edge: SplitEdge) -> some View {
        let armed = hoveredSplit == edge
        return Button { onSplit(edge) } label: {
            Image(systemName: edge.systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(armed ? Color.accentColor : .primary.opacity(0.8))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.95)))
                .overlay(
                    Circle().strokeBorder(
                        armed ? Color.accentColor : Color.primary.opacity(0.2),
                        lineWidth: armed ? 2 : 1
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help(edge.action)
        .accessibilityLabel(paneLabel("\(edge.action), \(edge.origin)"))
        .onHover { hoveredSplit = $0 ? edge : nil }
    }

    /// Where the divider will land, drawn on the pane while a split button is
    /// under the pointer.
    ///
    /// Four buttons around a pane say where they are but not what they do to
    /// it, and two of them draw the same divider as the other two — showing the
    /// result is what makes that legible without having to try it.
    private func splitPreview(_ edge: SplitEdge) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let vertical = edge.axis == .vertical

            ZStack {
                // The half that becomes the new pane. It is always the second
                // one — right, or below — so the tint says which half you keep
                // as much as which you gain.
                Rectangle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: vertical ? w / 2 : w,
                           height: vertical ? h : h / 2)
                    .position(x: vertical ? w * 0.75 : w / 2,
                              y: vertical ? h / 2 : h * 0.75)

                Rectangle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: vertical ? 2 : w,
                           height: vertical ? h : 2)
                    .position(x: w / 2, y: h / 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// Removing the pane, in its own corner.
    ///
    /// The stack cannot go — a layout needs somewhere for unpinned windows to
    /// land — so the control says why rather than simply vanishing.
    private var deleteButton: some View {
        let isStack = slot.node.type == .stack
        let stackLockHelp = "The stack can't be removed — every layout needs one"
        return Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(isStack ? 0.3 : 0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.95)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isStack)
        .help(isStack ? stackLockHelp : "Remove this cell")
        .accessibilityLabel(paneLabel(isStack ? stackLockHelp : "Remove this cell"))
        .opacity(isHovered ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    /// Names an action for the pane it belongs to.
    ///
    /// The pane's number is no longer drawn anywhere, but every pane still
    /// carries the same set of controls — so without this both VoiceOver and
    /// anything driving the interface see four identical "New pane above"
    /// buttons and cannot tell which is which.
    private func paneLabel(_ action: String) -> String {
        guard let addressLabel = slot.addressLabel else { return action }
        return "\(action) — pane \(addressLabel)"
    }

    private var borderOpacity: Double {
        if isDropTarget { return 0.95 }
        if isHovered { return 0.6 }
        return 0.28
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.primary.opacity(isDropTarget ? 0.18 : 0.05))

            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    Color.primary.opacity(borderOpacity),
                    lineWidth: isDropTarget ? 3 : 1.5
                )
                .allowsHitTesting(false)

            // Even inset all round so the preview reads as the pane itself.
            // Top panes inset past the layout bar, which is opaque and sits
            // over them.
            content
                .padding(EdgeInsets(top: 30 + topInset, leading: 30, bottom: 30, trailing: 30))

            if let hoveredSplit {
                splitPreview(hoveredSplit)
            }

            splitButtons

            // Top right, pushed clear of the layout bar the same way the top
            // split button is. It sat in this corner once before and was hard
            // to reach on any pane touching the top of the screen — but moving
            // it to the bottom was treating the symptom; `topInset` is however
            // far this pane reaches under the bar, and zero for the panes that
            // do not.
            deleteButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
                .padding(.top, topInset)
        }
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
    }

    /// The same list for every pane, whatever it currently holds.
    ///
    /// The stack used to show its frontmost window and a count instead of a
    /// list, which made it the one pane you could not change from its own
    /// contents — its role lived in the pane bar, and with that gone it would
    /// have been a one-way door. Its own view is the price of having a single
    /// place where what a pane holds is decided.
    private var content: some View {
        PaneChooser(
            windows: windows,
            apps: runningApps,
            pinned: slot.node.pinned,
            isEmpty: slot.node.type == .empty,
            isStack: slot.node.type == .stack,
            addressLabel: slot.addressLabel,
            onChooseApp: onChooseApp,
            onChooseWindow: onChoose,
            onChooseEmpty: onChooseEmpty,
            onChooseStack: onChooseStack,
            onTextFocusChanged: onTextFocusChanged,
            sessionID: sessionID
        )
    }
}

/// Grouping and filtering for the chooser.
///
/// Lifted out of `PaneChooser` when the search field moved into the pane bar.
/// The field and the list it filters now live in different views — the bar and
/// the pane's content — and both need the same answer about what matches, so
/// neither can own it.
private enum ChooserMatch {
    struct Group: Identifiable {
        let app: RunningAppInfo
        let windows: [WTWindow]
        var id: String { app.bundleId ?? app.name }
    }

    /// One box per running app — including apps with nothing open, so a pane
    /// can still be pinned to an app that isn't showing a window right now.
    /// Apps with windows sort first, since those are what you're usually after.
    static func groups(apps: [RunningAppInfo], windows: [WTWindow]) -> [Group] {
        apps
            .map { app in Group(app: app, windows: windows.filter { belongs($0, to: app) }) }
            .sorted { lhs, rhs in
                if lhs.windows.isEmpty != rhs.windows.isEmpty { return !lhs.windows.isEmpty }
                return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
            }
    }

    /// An app matches by name — keeping all its windows — or by any of its
    /// window titles, in which case only the matching windows are shown.
    static func filtered(_ groups: [Group], query: String) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return groups }

        return groups.compactMap { group in
            if group.app.name.lowercased().contains(needle) { return group }
            let hits = group.windows.filter { $0.title.lowercased().contains(needle) }
            return hits.isEmpty ? nil : Group(app: group.app, windows: hits)
        }
    }

    private static func belongs(_ window: WTWindow, to app: RunningAppInfo) -> Bool {
        if let bundleId = app.bundleId, let windowBundleId = window.bundleId {
            return windowBundleId == bundleId
        }
        return window.application.localizedCaseInsensitiveCompare(app.name) == .orderedSame
    }
}

// MARK: - Divider handle

/// Drag a boundary to repartition its two neighbours. The change is applied live
/// to the tree but only committed (and pushed to real windows) on mouse-up.
private struct DividerHandle: View {
    let divider: DividerSlot
    let onDragStarted: () -> Void
    let onChanging: (Double, Double) -> Void
    let onCommitted: (Double, Double) -> Void

    @State private var dragging = false
    @State private var hovering = false
    @State private var startA: Double = 0
    @State private var startB: Double = 0
    @State private var startSum: Double = 100
    @State private var lastA: Double = 0
    @State private var lastB: Double = 0

    private var isVertical: Bool { divider.axis == .vertical }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay(
                Capsule()
                    .fill(Color.primary.opacity(dragging ? 0.95 : hovering ? 0.6 : 0.0))
                    .frame(
                        width: isVertical ? 4 : 46,
                        height: isVertical ? 46 : 4
                    )
            )
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside {
                    (isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(SpaceOverlayView.canvasSpace))
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            (isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                            startA = divider.aPct
                            startB = divider.bPct
                            startSum = divider.siblingsPctSum
                            lastA = startA
                            lastB = startB
                            onDragStarted()
                        }
                        let travel = isVertical ? value.translation.width : value.translation.height
                        let resolved = DividerResize.resolve(
                            travel: travel,
                            containerLength: divider.containerLength,
                            startA: startA,
                            startB: startB,
                            siblingsPctSum: startSum
                        )
                        lastA = resolved.a
                        lastB = resolved.b
                        onChanging(lastA, lastB)
                    }
                    .onEnded { _ in
                        dragging = false
                        NSCursor.pop()
                        onCommitted(lastA, lastB)
                    }
            )
    }
}

// MARK: - Window tiles

/// What follows the cursor while a pane is being dragged. Deliberately abstract:
/// a pane is a slot in the layout, not the windows that happen to be in it.
private struct PaneDragPreview: View {
    @Environment(\.colorScheme) private var scheme

    let label: String?
    let node: LayoutNode
    let windowCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if let label {
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.18)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                if windowCount > 0 {
                    Text(windowCount == 1 ? "1 window" : "\(windowCount) windows")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(scheme.ground.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
    }

    private var title: String {
        switch node.type {
        case .pinned: return node.pinned?.application ?? node.pinned?.bundleId ?? "Pinned"
        case .stack:  return "Everything else"
        default:      return "Empty pane"
        }
    }
}

/// Everything a pane can hold, grouped by app. Each app is one selectable box
/// containing its windows, so choosing "Safari" is a single click rather than a
/// hunt through a flat list of look-alike screenshots. Apps with many windows
/// wrap onto more rows inside their own box.
private struct PaneChooser: View {
    let windows: [WTWindow]
    let apps: [RunningAppInfo]
    let pinned: PinnedConfig?
    /// The pane holds nothing on purpose — the ghost box is its current choice.
    let isEmpty: Bool
    /// This pane is where unpinned windows land.
    let isStack: Bool
    /// Names the two role boxes for their pane. Every pane draws the same list,
    /// so without this both VoiceOver and anything driving the interface see
    /// several identical "Stack" boxes and cannot tell which is which — the
    /// same reason the pane controls carry it.
    let addressLabel: String?
    let onChooseApp: (RunningAppInfo) -> Void
    let onChooseWindow: (WTWindow) -> Void
    let onChooseEmpty: () -> Void
    let onChooseStack: () -> Void
    /// Lets the window stand down from treating keystrokes as commands.
    let onTextFocusChanged: (Bool) -> Void
    /// Changes on each showing; the query is cleared when it does.
    let sessionID: Int

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let spacing: CGFloat = 12
    /// Padding inside an app box, both sides.
    private let boxInset: CGFloat = 24
    /// Gap between window tiles inside a box.
    private let tileGap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let _ = RenderProbe.breadcrumb("PaneChooser.body")
            let metrics = RenderProbe.measure("PaneChooser.metrics") {
                self.metrics(for: geo.size.width)
            }
            let _ = RenderProbe.tally("PaneChooser")

            // The field is outside the scroll view, so it holds still while the
            // list moves under it. Inside, it scrolled away with the results it
            // was filtering, and every keystroke that changed the result count
            // shifted it up or down the pane.
            //
            // It needs no inset of its own for the layout bar: the whole
            // chooser is already padded past it by `topInset`, so the top of
            // this stack is the top of the usable pane.
            VStack(spacing: spacing) {
                searchField

                ScrollView(showsIndicators: false) {
                // Lazy: a chooser lists every running app, but only a few rows
                // are ever on screen. A plain VStack builds all of them —
                // measured at 44 app groups and 51 window tiles for two panes,
                // most of them scrolled out of sight.
                LazyVStack(spacing: spacing) {
                    // Boxes are as wide as their contents need, so they flow and
                    // wrap rather than sitting in fixed columns. The two roles
                    // pack alongside the apps and lead the list.
                    ForEach(Array(rows(metrics: metrics).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(row) { entry in
                                box(for: entry, metrics: metrics)
                                    .frame(width: width(of: entry, metrics: metrics))
                                    // Every box takes the height of the tallest
                                    // in its row. A role holds no windows, so
                                    // left to itself it comes out the height of
                                    // its two lines of text and sits noticeably
                                    // short beside an app showing thumbnails.
                                    .frame(maxHeight: .infinity)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                }
                .mask(bottomFade)
            }
            // Top-aligned, not centred. The list used to be floored at the
            // pane's height and centred within it, which meant it slid up and
            // down as filtering changed how many rows there were — the results
            // moved while you were typing at them.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            // The window is retained between showings, so this state would
            // otherwise carry a stale query over from last time.
            .onChange(of: sessionID) { _ in query = "" }
        }
    }

    /// Softens the bottom edge of the scrolling list.
    ///
    /// A pane clips its content at its own edge, so a list longer than the pane
    /// ended mid-row with a hard horizontal cut that read as the list finishing
    /// rather than continuing. The fade says there is more below.
    ///
    /// A fixed height rather than a fraction of the pane: on a short pane a
    /// proportional fade would swallow most of the last row, and on a tall one
    /// it would be too gradual to notice. The nested reader is what makes that
    /// possible — the gradient's stops are fractions, so turning points into
    /// fractions needs the height it is actually being drawn at.
    ///
    /// Always applied, and invisible when it has nothing to do: a list that fits
    /// leaves empty space at the bottom of the scroll view, and fading
    /// transparency changes nothing.
    private var bottomFade: some View {
        GeometryReader { fade in
            let height = max(fade.size.height, 1)
            let start = max(0, 1 - Self.fadeHeight / height)
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: start),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private static let fadeHeight: CGFloat = 28

    /// Above the list it filters, and scrolling with it.
    ///
    /// It spent a while in the pane bar, which kept it in view but cost every
    /// pane a permanent strip of chrome. With the bar gone it comes back here.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.5))

            TextField("Search apps and windows", text: $query)
                .accessibilityLabel("Search apps and windows")
                .accessibilityIdentifier("chooser.search")
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .focused($searchFocused)
                .onSubmit { chooseFirstMatch() }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .overlay(
            Capsule().strokeBorder(
                searchFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.15),
                lineWidth: searchFocused ? 2 : 1
            )
        )
        .onChange(of: searchFocused) { focused in onTextFocusChanged(focused) }
        .onDisappear { onTextFocusChanged(false) }
    }

    /// Return picks the obvious result: the single matching window if the query
    /// narrowed to one, otherwise the first app still standing.
    private func chooseFirstMatch() {
        let matches = filteredGroups
        guard let first = matches.first else { return }
        if matches.count == 1, first.windows.count == 1 {
            onChooseWindow(first.windows[0])
        } else {
            onChooseApp(first.app)
        }
    }

    // MARK: - Entries

    /// Everything the list can offer, in the order it is offered.
    ///
    /// The roles are entries like any other rather than a separate strip above
    /// the apps: choosing what a pane holds is one decision, and splitting the
    /// choices into two differently-shaped lists made "Stack" look like a mode
    /// switch rather than one of the things a pane can be.
    enum Entry: Identifiable {
        case stack
        case empty
        case app(ChooserMatch.Group)

        var id: String {
            switch self {
            case .stack:          return "role.stack"
            case .empty:          return "role.empty"
            case .app(let group): return "app.\(group.id)"
            }
        }
    }

    /// Roles first, then the pane's current pin, then everything else.
    ///
    /// What the pane holds right now is the entry you are most likely to be
    /// looking for — to see what it is, or to change it — so it does not sit
    /// wherever the alphabet happens to put it.
    private var entries: [Entry] {
        let groups = filteredGroups
        let current = groups.filter { matchesPin($0.app) }
        let rest = groups.filter { !matchesPin($0.app) }
        return [.stack, .empty] + (current + rest).map(Entry.app)
    }

    @ViewBuilder
    private func box(for entry: Entry, metrics: Metrics) -> some View {
        switch entry {
        case .stack:
            RoleChoiceBox(
                systemName: "square.stack.3d.up.fill",
                title: "Stack",
                detail: "everything else lands here",
                isCurrent: isStack,
                axLabel: roleLabel("Stack"),
                action: onChooseStack
            )
        case .empty:
            RoleChoiceBox(
                systemName: "square.dashed",
                title: "Empty",
                detail: "leave this pane unassigned",
                isCurrent: isEmpty,
                axLabel: roleLabel("Empty"),
                action: onChooseEmpty
            )
        case .app(let group):
            AppWindowGroup(
                app: group.app,
                windows: group.windows,
                isCurrent: matchesPin(group.app),
                tileWidth: metrics.tile,
                tileGap: tileGap,
                tilesPerRow: tilesPerRow(for: group, metrics: metrics),
                pinned: matchesPin(group.app) ? pinned : nil,
                onChooseApp: { onChooseApp(group.app) },
                onChooseWindow: onChooseWindow
            )
        }
    }

    /// A role box holds no windows, so it takes the width of a one-tile box —
    /// the same width an app with nothing open gets.
    private func width(of entry: Entry, metrics: Metrics) -> CGFloat {
        switch entry {
        case .stack, .empty:
            return boxWidth(perRow: 1, metrics: metrics)
        case .app(let group):
            return boxWidth(perRow: tilesPerRow(for: group, metrics: metrics), metrics: metrics)
        }
    }

    // MARK: - Sizing

    private struct Metrics {
        let tile: CGFloat
        /// Most tiles that fit on one row of a box at this pane width.
        let maxPerRow: Int
        let available: CGFloat
    }

    /// Tiles shrink so that three always fit across, however narrow the pane —
    /// that's the floor a row breaks at.
    private func metrics(for width: CGFloat) -> Metrics {
        let preferred: CGFloat = 140
        let widest = max(48, (width - boxInset - 2 * tileGap) / 3)
        let tile = min(preferred, widest)
        let maxPerRow = max(3, Int((width - boxInset + tileGap) / (tile + tileGap)))
        return Metrics(tile: tile, maxPerRow: maxPerRow, available: width)
    }

    /// A box is as wide as its windows need: one tile per window up to what fits,
    /// then it wraps onto another row rather than growing further.
    private func tilesPerRow(for group: AppGroup, metrics: Metrics) -> Int {
        max(1, min(max(group.windows.count, 1), metrics.maxPerRow))
    }

    private func boxWidth(perRow: Int, metrics: Metrics) -> CGFloat {
        boxInset + CGFloat(perRow) * metrics.tile + CGFloat(perRow - 1) * tileGap
    }

    /// Greedy left-to-right packing: a box joins the current row if it fits,
    /// otherwise it starts the next one.
    private func rows(metrics: Metrics) -> [[Entry]] {
        var rows: [[Entry]] = []
        var current: [Entry] = []
        var used: CGFloat = 0

        for entry in entries {
            let width = width(of: entry, metrics: metrics)
            let needed = current.isEmpty ? width : used + spacing + width
            if !current.isEmpty, needed > metrics.available {
                rows.append(current)
                current = []
                used = 0
            }
            used = current.isEmpty ? width : used + spacing + width
            current.append(entry)
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    // MARK: - Search

    private func roleLabel(_ role: String) -> String {
        guard let addressLabel else { return role }
        return "\(role) — pane \(addressLabel)"
    }

    // MARK: - Grouping

    private typealias AppGroup = ChooserMatch.Group

    private var filteredGroups: [AppGroup] {
        ChooserMatch.filtered(
            ChooserMatch.groups(apps: apps, windows: windows),
            query: query
        )
    }

    /// Mirrors `LayoutManager.windowMatches` for the app-level fields the
    /// chooser writes, so the highlight agrees with what will be placed.
    private func matchesPin(_ app: RunningAppInfo) -> Bool {
        guard let pinned else { return false }
        if let bundleId = pinned.bundleId { return app.bundleId == bundleId }
        if let application = pinned.application {
            return app.name.localizedCaseInsensitiveCompare(application) == .orderedSame
        }
        return false
    }
}

/// One app's box: a header naming it, and its windows wrapped below. The box
/// itself is the selection target; the tiles inside are a way to pick which of
/// the app's windows should be the one on top.
private struct AppWindowGroup: View {
    let app: RunningAppInfo
    let windows: [WTWindow]
    let isCurrent: Bool
    let tileWidth: CGFloat
    let tileGap: CGFloat
    let tilesPerRow: Int
    /// The pane's pin, so the box can mark the window it names.
    let pinned: PinnedConfig?
    let onChooseApp: () -> Void
    let onChooseWindow: (WTWindow) -> Void

    /// Which of the two targets the pointer is over. The tiles sit on top of the
    /// box, so without this there's nothing to say whether a click will pin the
    /// app or one of its windows.
    @State private var hoveringBox = false
    @State private var hoveredWindow: CGWindowID?

    private var boxHighlighted: Bool { hoveringBox && hoveredWindow == nil }

    var body: some View {
        let _ = RenderProbe.tally("AppWindowGroup")
        let _ = RenderProbe.breadcrumb("AppWindowGroup.body")
        return RenderProbe.measure("AppWindowGroup") { VStack(alignment: .leading, spacing: 10) {
            header

            if windows.isEmpty {
                Text("No open windows")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.4))
            } else {
                LazyVGrid(
                    // Fixed rather than adaptive: the row count is decided by the
                    // box's width up front, so tiles shrink to fit rather than
                    // reflowing to fewer per line.
                    columns: Array(
                        repeating: GridItem(.fixed(tileWidth), spacing: tileGap),
                        count: tilesPerRow
                    ),
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(windows, id: \.id) { window in
                        // No app label on the tile: the box header already names
                        // it, and no accent either — the box carries selection.
                        WindowTile(
                            window: window,
                            showsAppLabel: false,
                            isCurrent: isPinnedWindow(window),
                            isHovered: hoveredWindow == window.id
                        )
                        .onHover { inside in
                            if inside { hoveredWindow = window.id }
                            else if hoveredWindow == window.id { hoveredWindow = nil }
                        }
                        .onTapGesture { onChooseWindow(window) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isCurrent ? Color.accentColor.opacity(0.22)
                        : boxHighlighted ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.05)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isCurrent ? Color.accentColor
                        : boxHighlighted ? Color.accentColor.opacity(0.7)
                        : Color.primary.opacity(0.15),
                    lineWidth: isCurrent || boxHighlighted ? 3 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hoveringBox = $0 }
        .onTapGesture(perform: onChooseApp)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All windows of \(app.name)")
        .accessibilityAddTraits(.isButton)
        .animation(.easeOut(duration: 0.12), value: isCurrent)
        .animation(.easeOut(duration: 0.12), value: boxHighlighted)
        } }

    /// Marked only when the pin names this window, so an app-level pin
    /// highlights the box alone and doesn't imply a window was chosen.
    private func isPinnedWindow(_ window: WTWindow) -> Bool {
        guard let titles = pinned?.windowTitles, !titles.isEmpty else { return false }
        return titles.contains { window.title.contains($0) }
    }

    /// The header is the dependable app target — the tiles cover most of the
    /// box, so without this "click the app" often lands on a window instead.
    private var header: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 20, height: 20)
            Text(app.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            if windows.count > 1 {
                Text("\(windows.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            // Counts as the box, not a window.
            if inside { hoveredWindow = nil }
        }
        .onTapGesture(perform: onChooseApp)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = appIcon {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.primary.opacity(0.4))
        }
    }

    /// Cached: this is read from a view body, once per app box per pane, so
    /// resolving it here meant a Launch Services lookup and a disk read of the
    /// bundle's icon on every pass of the render loop.
    private var appIcon: NSImage? {
        AppIconCache.shared.icon(bundleId: app.bundleId, appName: app.name)
    }
}

/// The "leave it empty" option, shaped like an app box so it reads as a peer.
/// One non-app choice in a pane's list: the stack, or empty.
///
/// Wears the app box's chrome exactly — same padding, corner, fill, border and
/// hover response — because it is the same kind of thing: one of the options for
/// what this pane holds. Dressing the roles differently made them read as a
/// setting that happened to be nearby rather than as entries in the list.
///
/// Still a real Button underneath, where the app box uses a tap gesture. These
/// carry the pane's role and the interface tests press them, and a tap gesture
/// is not something `AXUIElementPerformAction` can drive.
private struct RoleChoiceBox: View {
    let systemName: String
    let title: String
    let detail: String
    let isCurrent: Bool
    let axLabel: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemName)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .frame(width: 20, height: 20)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                // Sits where an app box puts "No open windows", so the two are
                // the same height when neither has anything to show.
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.4))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isCurrent ? Color.accentColor.opacity(0.22)
                            : hovering ? Color.accentColor.opacity(0.12)
                            : Color.primary.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isCurrent ? Color.accentColor
                            : hovering ? Color.accentColor.opacity(0.7)
                            : Color.primary.opacity(0.15),
                        lineWidth: isCurrent || hovering ? 3 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(axLabel)
        .animation(.easeOut(duration: 0.12), value: isCurrent)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct WindowTile: View {
    @Environment(\.colorScheme) private var scheme

    let window: WTWindow
    @Environment(\.thumbnailRevision) private var thumbnailRevision
    /// Fill the space offered instead of holding a fixed 16:10 card. Used when
    /// the tile stands for the whole pane, so it takes the pane's proportions.
    var fills = false
    /// Off inside an app group, where the box header already names the app.
    var showsAppLabel = true
    /// This is the window its pane will place.
    var isCurrent = false
    /// The pointer is over this tile, so a click means this window — not its app.
    var isHovered = false

    var body: some View {
        // Referencing the revision is what re-reads the cache as captures land.
        let _ = thumbnailRevision
        let _ = RenderProbe.tally("WindowTile")
        let _ = RenderProbe.breadcrumb("WindowTile.body")

        VStack(alignment: .leading, spacing: 6) {
            if showsAppLabel { appLabel }

            card
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isCurrent ? Color.accentColor
                                : isHovered ? Color.accentColor.opacity(0.75)
                                : Color.primary.opacity(0.3),
                            lineWidth: isCurrent || isHovered ? 3 : 1
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(isHovered && !isCurrent ? 0.18 : 0))
                        .allowsHitTesting(false)
                )
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
        // Named so a particular window can be picked out. Untitled windows fall
        // back to their app, which is all a person has to go on too.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            window.title.isEmpty
                ? "Window of \(window.application)"
                : "Window \(window.title) of \(window.application)"
        )
        // Only a tile drawing a window large needs the native-size capture, and
        // only while it is on screen. Tied to the tile's own lifetime rather
        // than to the app label, which a filling tile may not show at all.
        .onAppear {
            guard fills else { return }
            WindowThumbnailCache.shared.requestFullResolution(for: window.id)
        }
        .onDisappear {
            guard fills else { return }
            WindowThumbnailCache.shared.releaseFullResolution(for: window.id)
        }
    }

    /// Names the app above its preview — screenshots of a blank document or a
    /// dark editor look much alike, and the window title below the preview says
    /// which window, not which app.
    private var appLabel: some View {
        HStack(spacing: 6) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(window.application)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var thumbnail: NSImage? {
        // A pane-filling preview is drawn far larger than the capped thumbnail,
        // where the downscaling would read as blur. Those windows are captured
        // at native size as well; fall back to the thumbnail until the next
        // capture lands, so the tile is never empty while waiting.
        if fills, let full = WindowThumbnailCache.shared.fullImage(for: window.id) {
            return full
        }
        return WindowThumbnailCache.shared.nsImage(for: window.id)
    }

    @ViewBuilder
    private var card: some View {
        if fills {
            cardBody.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            cardBody.aspectRatio(16.0 / 10.0, contentMode: .fit)
        }
    }

    private var cardBody: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .fill(scheme.ground.opacity(0.3))

            if let thumbnail {
                // Clipped and non-sizing: a .fill image would otherwise push the
                // card's layout out to the image's own dimensions.
                Color.clear.overlay(
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
            } else if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(28)
            }

            // Title sits on the tile itself — no separate label row, so the
            // tile stays a single clean rectangle at any size. Stays white on a
            // dark gradient in both appearances: it's over a screenshot, whose
            // content the surface's own palette says nothing about.
            Text(window.title.isEmpty ? window.application : window.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0), .black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var appIcon: NSImage? {
        AppIconCache.shared.icon(pid: window.pid)
    }
}

// MARK: - Layout switcher

/// Floating layout picker. Deliberately chrome-less — it hovers over the cells
/// rather than living in a sidebar or title bar. Everything the old editor's
/// sidebar did (rename, set key, duplicate, delete) lives in each pill's
/// context menu.
private struct LayoutSwitcherBar: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(viewModel.layouts.enumerated()), id: \.element.id) { index, layout in
                LayoutPill(
                    viewModel: viewModel,
                    layout: layout,
                    index: index,
                    isActive: layout.id == viewModel.editingLayout?.id
                )
            }

            Button {
                viewModel.addLayout()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("New layout")
            .accessibilityLabel("New layout")
            .accessibilityIdentifier("layout.add")

        }
        .padding(8)
        // Opaque, not a tint: the bar reads as a fixed object floating over the
        // canvas rather than another translucent layer in the stack.
        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 22, y: 8)
    }
}

/// Cursor feedback for a hover region.
///
/// `push()`/`pop()` is the usual pairing, but a layout chip can be deleted
/// while the pointer is still over it, and then the pop never happens — the
/// cursor stays changed for the rest of the session. Popping on disappear too
/// keeps the stack balanced.
private struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != inside else { return }
                inside = hovering
                if hovering { cursor.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if inside {
                    NSCursor.pop()
                    inside = false
                }
            }
    }
}

private extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursor(cursor: cursor))
    }
}

private struct LayoutPill: View {
    @ObservedObject var viewModel: OverlayViewModel
    let layout: WTLayout
    let index: Int
    let isActive: Bool

    @State private var deleteHovering = false
    @State private var nameHovering = false
    @State private var pillHovering = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    /// Mirrors the dialog's state onto the view model so the window stands down
    /// while it is up. Routed through a Binding rather than set in the button
    /// action because the dialog can also be dismissed by clicking away, and the
    /// flag has to come back down however that happens.
    private var confirmingDeleteBinding: Binding<Bool> {
        Binding(
            get: { confirmingDelete },
            set: { presented in
                confirmingDelete = presented
                viewModel.isConfirmationPresented = presented
            }
        )
    }

    private var isRenaming: Bool { viewModel.renamingLayoutId == layout.id }

    var body: some View {
        pill
            // Every operation is reachable here as well as from its own control.
            .contextMenu {
                Button("Rename") { beginRename() }
                Menu("Menu Key") { menuKeyItems }
                Button("Duplicate") { viewModel.duplicateLayout(layout) }
                Divider()
                Button("Delete", role: .destructive) { confirmingDeleteBinding.wrappedValue = true }
                    .disabled(viewModel.layouts.count <= 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Layout \(layout.name)")
            .accessibilityIdentifier("layout.pill.\(layout.name)")
            // Renaming is a double-click, and duplicating is in a context menu.
            // Neither is reachable without a mouse, so both are offered as
            // actions as well — which is also the only way anything can drive
            // them from outside.
            .accessibilityAction(named: "Rename") { beginRename() }
            .accessibilityAction(named: "Duplicate") { viewModel.duplicateLayout(layout) }
            // Deleting writes the config straight away and there is no undo for
            // it, unlike edits to a layout's panes.
            .confirmationDialog(
                "Delete “\(layout.name)”?",
                isPresented: confirmingDeleteBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Layout", role: .destructive) {
                    viewModel.deleteLayout(layout)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This layout will be removed from your configuration. This cannot be undone.")
            }
    }

    /// The whole capsule is the hit area — padding and all — not just the text.
    /// Single click applies the layout, double click renames it; declaring the
    /// two-tap gesture first is what lets SwiftUI give it precedence. The key
    /// chip and the trash sit inside and take their own clicks first.
    @ViewBuilder
    private var pill: some View {
        if isRenaming {
            pillBody
        } else {
            pillBody
                .onTapGesture(count: 2) { beginRename() }
                .onTapGesture { viewModel.selectLayout(at: index) }
        }
    }

    private var pillBody: some View {
        HStack(spacing: 8) {
            // Preview, then the shortcut, then the name — the same order the
            // menubar uses, so the two read alike.
            layoutPreview

            keyChip

            if isRenaming {
                TextField("Name", text: $viewModel.renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 110)
                    .focused($nameFocused)
                    .onSubmit { viewModel.commitRename() }
                    .onExitCommand { viewModel.cancelRename() }
                    .onAppear { nameFocused = true }
                    // Unlabelled, this field was invisible to VoiceOver and to
                    // anything driving the interface — a text box with no name.
                    .accessibilityLabel("Layout name")
                    .accessibilityIdentifier("layout.nameField")
            } else {
                Text(layout.name.isEmpty ? "Untitled" : layout.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    // Renaming is a double-click with nothing to suggest it.
                    // The tint is drawn as a background with negative insets so
                    // revealing it cannot change the chip's width.
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(nameHovering ? 0.14 : 0))
                            .padding(EdgeInsets(top: -2, leading: -5, bottom: -2, trailing: -5))
                    )
                    .onHover { nameHovering = $0 }
                    .hoverCursor(.iBeam)
                    .help("Double-click to rename")
            }

            deleteButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.primary.opacity(capsuleFill)))
        .overlay(
            Capsule().strokeBorder(
                Color.primary.opacity(capsuleBorder),
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
        // The whole capsule is the click target for selecting this layout, so
        // the whole capsule is what lights up. Kept clearly below the selected
        // chip's own weight, or hovering would read as having already switched.
        .onHover { pillHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: pillHovering)
    }

    /// Selected outweighs hovered: a hovered chip should look reachable, not
    /// look chosen.
    private var capsuleFill: Double {
        if isRenaming || isActive { return 0.22 }
        return pillHovering ? 0.16 : 0.08
    }

    private var capsuleBorder: Double {
        if isActive { return 0.5 }
        return pillHovering ? 0.22 : 0.0
    }

    /// A thumbnail of the layout's shape — literally the graphic the menubar
    /// draws beside each layout, so the two agree.
    ///
    /// The SwiftUI previews used elsewhere (MultiMonitorPreviewView) are built
    /// for thumbnails several times this size: the stack's fanned cards have
    /// floor sizes that stop scaling down, so at chip size every layout renders
    /// as the same orange blob. This renderer is drawn for 16pt and stays
    /// legible.
    ///
    /// Hidden from accessibility on purpose. It carries no information the
    /// chip's own label doesn't already give, and every element added here
    /// shows up in the interface tests' view of the surface.
    private var layoutPreview: some View {
        Image(nsImage: NSImage.layoutIcon(
            for: layout,
            size: NSSize(width: Self.previewSize.width, height: Self.previewSize.height)
        ))
        .renderingMode(.template)
        .foregroundStyle(.primary.opacity(0.75))
        .accessibilityHidden(true)
    }

    /// Sized to sit inside the chip without setting its height: the name is
    /// 14pt, so anything taller than this makes the capsule grow.
    private static let previewSize = CGSize(width: 21, height: 13)

    /// Clicking the chip picks this layout's menu bar shortcut. When none is
    /// set it falls back to showing the positional ⌘1–⌘9, which always works
    /// inside this surface regardless of what's assigned here.
    private var keyChip: some View {
        Menu {
            menuKeyItems
        } label: {
            keycap
        }
        .menuStyle(.borderlessButton)
        // Always shown. Nothing else marks the keycap as something you can
        // open, and revealing it only on hover still left it undiscoverable
        // until you happened to point at it.
        .menuIndicator(.visible)
        .fixedSize()
        .hoverCursor(.pointingHand)
        .help("Menu bar shortcut for this layout")
    }

    /// A physical keycap. Three layers do the work: a dark base peeking out
    /// below for thickness, a top-lit gradient face, and a bright rim.
    private var keycap: some View {
        let assigned = layout.quickKey?.isEmpty == false
        return Text(keyChipLabel)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.primary.opacity(assigned ? 1 : 0.7))
            .shadow(color: .black.opacity(0.6), radius: 0, y: 1)
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 22)
            .background(
                ZStack {
                    // The key's side wall, visible under the front face.
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.black.opacity(0.6))
                        .offset(y: 2)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: assigned
                                    ? [Color.primary.opacity(0.38), Color.primary.opacity(0.17)]
                                    : [Color.primary.opacity(0.2), Color.primary.opacity(0.07)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(assigned ? 0.6 : 0.4),
                                    Color.primary.opacity(0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            // Leaves room for the base layer's 2pt offset.
            .padding(.bottom, 2)
    }

    /// Shared by the keycap's dropdown and the pill's context menu.
    @ViewBuilder
    private var menuKeyItems: some View {
        Button {
            setQuickKey(nil)
        } label: {
            Label("None", systemImage: layout.quickKey == nil ? "checkmark" : "")
        }

        Divider()

        ForEach(quickKeyChoices, id: \.self) { choice in
            Button {
                setQuickKey(choice)
            } label: {
                Label("⌘\(choice.uppercased())",
                      systemImage: layout.quickKey == choice ? "checkmark" : "")
            }
        }
    }

    private var keyChipLabel: String {
        if let quickKey = layout.quickKey, !quickKey.isEmpty {
            return "⌘\(quickKey.uppercased())"
        }
        return index < 9 ? "⌘\(index + 1)" : "⌘–"
    }

    private var quickKeyChoices: [String] {
        (1...9).map(String.init) + "abcdefghijklmnopqrstuvwxyz".map(String.init)
    }

    private var deleteButton: some View {
        Button {
            confirmingDeleteBinding.wrappedValue = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(deleteHovering ? 1 : 0.4))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(deleteHovering ? 0.18 : 0.0)))
        }
        .buttonStyle(.plain)
        .onHover { deleteHovering = $0 }
        .disabled(viewModel.layouts.count <= 1)
        .opacity(viewModel.layouts.count <= 1 ? 0.25 : 1)
        .help("Delete this layout")
        // Named, not just "button". VoiceOver announced every control in this
        // surface identically, and nothing could address one from outside.
        .accessibilityLabel("Delete layout \(layout.name)")
        .accessibilityIdentifier("layout.delete.\(layout.name)")
    }

    private func beginRename() {
        viewModel.beginRename(layout)
    }

    private func setQuickKey(_ key: String?) {
        var updated = layout
        updated.quickKey = key
        viewModel.updateLayoutMeta(updated)
    }
}

// MARK: - Scope bar

/// Screen set and monitor selection. Only shown for layouts that actually have
/// more than one of either — most layouts never see it.
private struct ScopeBar: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        HStack(spacing: 8) {
            if let sets = viewModel.editingLayout?.screenSets, sets.count > 1 {
                ForEach(Array(sets.enumerated()), id: \.offset) { index, _ in
                    chip(
                        title: "Set \(index + 1)",
                        active: viewModel.selectedScreenSetIndex == index,
                        enabled: true
                    ) { viewModel.selectScreenSet(index) }
                }

            }
            // No monitor chips: every screen draws its own overlay now, so
            // there's nothing left to switch between here.
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Matches the layout bar directly above it — they read as one cluster.
        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }

    private func chip(title: String, active: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(.primary.opacity(enabled ? (active ? 1 : 0.7) : 0.35))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(active ? 0.2 : 0.0)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

