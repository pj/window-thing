import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WindowThingCore
import WindowThingViewModel

// MARK: - RunningAppInfo Transferable (UI only)

extension RunningAppInfo: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .runningApp)
    }
}

extension UTType {
    static let runningApp = UTType(exportedAs: "com.windowthing.running-app")
}

// MARK: - OverlayWindow

class OverlayWindow: NSWindow {
    let viewModel: OverlayViewModel

    init() {
        viewModel = OverlayViewModel()

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let windowWidth: CGFloat = 1000
        let windowHeight: CGFloat = 680
        let windowRect = NSRect(
            x: visibleFrame.midX - windowWidth / 2,
            y: visibleFrame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )

        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = ""
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.minSize = NSSize(width: 640, height: 400)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hc = NSHostingController(rootView: OverlayView(viewModel: viewModel))
        hc.sizingOptions = []
        hc.preferredContentSize = NSSize(width: windowWidth, height: windowHeight)
        self.contentViewController = hc
        // Re-apply frame after contentViewController may have resized the window
        self.setFrame(windowRect, display: false)
    }

    func showOverlay() {
        viewModel.refresh()
        // Re-center on the current main screen each time
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: vf.midX - frame.width / 2,
            y: vf.midY - frame.height / 2
        ))
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideOverlay() {
        self.orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        // Close when the user clicks away
        hideOverlay()
    }

    /// Show the overlay and immediately open the cell picker for the frontmost window.
    func showCellPickerForFocusedWindow() {
        if !isVisible { showOverlay() }
        let wm = WindowManager.shared
        if let app = wm.getFocusedApplication(),
           let window = app.focusedWindow ?? wm.getWindows().first(where: { $0.pid == app.id || $0.bundleId == app.bundleId }) {
            viewModel.showCellPicker(for: window)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var undoManager: UndoManager? { viewModel.undoManager }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { hideOverlay(); return }
        super.keyDown(with: event)
    }
}

// MARK: - OverlayView

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var selectedId: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedId) {
                ForEach(viewModel.layouts, id: \.id) { layout in
                    LayoutSidebarRow(layout: layout, viewModel: viewModel)
                        .tag(layout.id)
                }

                // "New Layout" button row — like Apple Books' "+ New Collection"
                Button {
                    viewModel.addLayout()
                } label: {
                    Label("New Layout", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: selectedId) { newId in
                guard let newId else { return }
                guard let layout = viewModel.layouts.first(where: { $0.id == newId }) else { return }
                viewModel.startEditing(layout)
                viewModel.applyCurrentLayout()
            }
            .onChange(of: viewModel.editingLayout?.id) { newId in
                if selectedId != newId { selectedId = newId }
            }
            .onAppear { selectedId = viewModel.editingLayout?.id }
        } detail: {
            if viewModel.layouts.isEmpty {
                noLayoutsView
            } else {
                LayoutEditorPanel(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .overlay {
            if viewModel.isCellPickerVisible {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.hideCellPicker() }
                CellPickerView(viewModel: viewModel, onDismiss: {})
            }
        }
    }

    // MARK: - No Layouts Placeholder

    private var noLayoutsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No layouts configured")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Layout Sidebar Row

// List manages selection state and highlight rendering.
// Use only adaptive semantic colors so labels go white on the blue selected row.
struct LayoutSidebarRow: View {
    let layout: WTLayout
    @ObservedObject var viewModel: OverlayViewModel
    @FocusState private var nameFieldFocused: Bool
    @State private var editingName: String = ""

    @FocusState private var hotkeyFieldFocused: Bool
    @State private var editingHotkey: String = ""
    @State private var shakeOffset: CGFloat = 0

    private var isRenaming: Bool {
        viewModel.renamingLayoutId == layout.id
    }

    private var isRecordingHotkey: Bool {
        viewModel.recordingHotkeyLayoutId == layout.id
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .separatorColor).opacity(0.6))
                if let screenSet = layout.screenSets.first {
                    MultiMonitorPreviewView(
                        screenConfig: screenSet,
                        graphicSize: CGSize(width: 56, height: 36)
                    )
                }
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            }
            .frame(width: 60, height: 40)

            // Name — inline TextField when renaming, Text otherwise
            if isRenaming {
                TextField("Layout Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($nameFieldFocused)
                    .onSubmit { commitRename() }
                    .onChange(of: nameFieldFocused) { focused in
                        if !focused { commitRename() }
                    }
                    .onAppear {
                        editingName = layout.name
                        // Delay focus to next run loop so the field is mounted
                        DispatchQueue.main.async { nameFieldFocused = true }
                    }
            } else {
                Text(layout.name.isEmpty ? "Untitled" : layout.name)
                    .font(.system(size: 13))
                    .foregroundStyle(layout.name.isEmpty
                        ? Color(.secondaryLabelColor)
                        : Color(.labelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            // Hotkey — inline TextField when recording, static badge otherwise
            if isRecordingHotkey {
                TextField("", text: $editingHotkey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 32)
                    .focused($hotkeyFieldFocused)
                    .onChange(of: editingHotkey) { newValue in
                        // Force uppercase, take last character typed
                        let cleaned = newValue.uppercased()
                        let char = cleaned.count > 1 ? String(cleaned.suffix(1)) : cleaned
                        // Check conflict immediately
                        let key = char.trimmingCharacters(in: .whitespaces).lowercased()
                        if !key.isEmpty,
                           viewModel.layouts.contains(where: { $0.id != layout.id && $0.quickKey == key }) {
                            NSSound.beep()
                            editingHotkey = layout.quickKey?.uppercased() ?? ""
                            triggerShake()
                            return
                        }
                        if editingHotkey != char { editingHotkey = char }
                    }
                    .onSubmit { commitHotkey() }
                    .onChange(of: hotkeyFieldFocused) { focused in
                        if !focused { commitHotkey() }
                    }
                    .onAppear {
                        editingHotkey = layout.quickKey?.uppercased() ?? ""
                        DispatchQueue.main.async { hotkeyFieldFocused = true }
                    }
                    .offset(x: shakeOffset)
                    .onExitCommand { viewModel.cancelRecordingHotkey() }
            } else if !isRenaming {
                if let key = layout.quickKey {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.quaternaryLabelColor))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(.separatorColor), lineWidth: 0.5))
                        Text(key.uppercased())
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(.secondaryLabelColor))
                    }
                    .frame(width: 26, height: 22)
                }
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Rename") {
                editingName = layout.name
                viewModel.renamingLayoutId = layout.id
            }
            Button(layout.quickKey != nil ? "Change Hotkey" : "Set Hotkey") {
                viewModel.startRecordingHotkey(for: layout.id)
            }
            if layout.quickKey != nil {
                Button("Clear Hotkey") {
                    var updated = layout
                    updated.quickKey = nil
                    viewModel.updateLayoutMeta(updated)
                }
            }
            Divider()
            Button("Duplicate") {
                viewModel.duplicateLayout(layout)
            }
            Divider()
            Button("Delete", role: .destructive) {
                viewModel.deleteLayout(layout)
            }
            .disabled(viewModel.layouts.count <= 1)
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        let finalName = editingName.trimmingCharacters(in: .whitespaces)
        var updated = layout
        updated.name = finalName.isEmpty ? "Untitled" : finalName
        viewModel.updateLayoutMeta(updated)
        viewModel.renamingLayoutId = nil
    }

    private func commitHotkey() {
        guard isRecordingHotkey else { return }
        let key = editingHotkey.trimmingCharacters(in: .whitespaces).lowercased()
        var updated = layout
        updated.quickKey = key.isEmpty ? nil : String(key.prefix(1))
        viewModel.updateLayoutMeta(updated)
        viewModel.recordingHotkeyLayoutId = nil
    }

    private func triggerShake() {
        withAnimation(.default) { shakeOffset = 6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = 4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = 0 }
        }
    }
}


// MARK: - Compact Tile View

/// Non-interactive mini renderer of a LayoutNode tree for use in compact previews.
struct CompactTileView: View {
    let node: LayoutNode
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            renderContent()
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func renderContent() -> some View {
        switch node.type {
        case .columns:
            if let cols = node.columns, !cols.isEmpty {
                columnsContent(cols)
            } else { leafContent }
        case .rows:
            if let rs = node.rows, !rs.isEmpty {
                rowsContent(rs)
            } else { leafContent }
        default:
            leafContent
        }
    }

    @ViewBuilder
    private func columnsContent(_ cols: [LayoutNode]) -> some View {
        let items = layoutItems(cols, isColumns: true)
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                CompactTileView(node: item.node, size: item.size)
                    .frame(width: item.size.width, height: item.size.height)
                    .offset(x: item.pos, y: 0)
            }
        }
    }

    @ViewBuilder
    private func rowsContent(_ rs: [LayoutNode]) -> some View {
        let items = layoutItems(rs, isColumns: false)
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                CompactTileView(node: item.node, size: item.size)
                    .frame(width: item.size.width, height: item.size.height)
                    .offset(x: 0, y: item.pos)
            }
        }
    }

    private struct TileItem {
        let node: LayoutNode
        let size: CGSize
        let pos: CGFloat
    }

    private func layoutItems(_ children: [LayoutNode], isColumns: Bool) -> [TileItem] {
        let defaultP = 100.0 / Double(max(children.count, 1))
        let total = max(children.reduce(0.0) { $0 + ($1.percentage ?? defaultP) }, 1.0)
        var pos: CGFloat = 0
        return children.map { child in
            let frac = CGFloat((child.percentage ?? defaultP) / total)
            if isColumns {
                let w = size.width * frac
                let item = TileItem(node: child, size: CGSize(width: w, height: size.height), pos: pos)
                pos += w
                return item
            } else {
                let h = size.height * frac
                let item = TileItem(node: child, size: CGSize(width: size.width, height: h), pos: pos)
                pos += h
                return item
            }
        }
    }

    private var leafContent: some View {
        ZStack {
            leafBackground
            if size.width > 18 && size.height > 12 {
                Text(leafLabel)
                    .font(.system(size: max(6, min(9, size.width / 5))))
                    .foregroundStyle(leafLabelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var leafLabel: String {
        switch node.type {
        case .pinned:
            return node.pinned?.application
                ?? node.pinned?.bundleId?.components(separatedBy: ".").last
                ?? ""
        case .stack:
            return ""
        default:
            return ""
        }
    }

    private var leafLabelColor: Color {
        node.type == .pinned ? Color.accentColor : Color.clear
    }

    @ViewBuilder
    private var leafBackground: some View {
        switch node.type {
        case .pinned:
            Rectangle().fill(Color.accentColor.opacity(0.22))
        case .stack:
            compactStackBackground
        default:
            Rectangle().fill(Color.secondary.opacity(0.06))
        }
    }

    private var compactStackBackground: some View {
        ZStack {
            Rectangle().fill(Color.orange.opacity(0.04))
            ForEach(0..<3, id: \.self) { i in
                let o = CGFloat(2 - i) * max(1.5, size.width * 0.06)
                RoundedRectangle(cornerRadius: max(1, size.width * 0.04))
                    .fill(Color.orange.opacity(0.1 + Double(i) * 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: max(1, size.width * 0.04))
                            .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                    )
                    .frame(
                        width: max(4, size.width * 0.72 - o),
                        height: max(3, size.height * 0.62 - o * 0.6)
                    )
                    .offset(x: o * 0.6, y: -o * 0.4)
            }
        }
    }
}

// MARK: - Multi-Monitor Preview

struct MultiMonitorPreviewView: View {
    let screenConfig: ScreenConfig
    let graphicSize: CGSize

    var body: some View {
        let monitors = orderedMonitors
        let gap: CGFloat = monitors.count > 1 ? 2 : 0
        let totalGap = gap * CGFloat(max(monitors.count - 1, 0))
        let monW = (graphicSize.width - totalGap) / CGFloat(max(monitors.count, 1))

        HStack(spacing: gap) {
            ForEach(Array(monitors.enumerated()), id: \.offset) { _, pair in
                CompactTileView(
                    node: pair.node,
                    size: CGSize(width: monW, height: graphicSize.height)
                )
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
            }
        }
        .frame(width: graphicSize.width, height: graphicSize.height)
    }

    private var orderedMonitors: [(key: String, node: LayoutNode)] {
        var result: [(key: String, node: LayoutNode)] = []
        if let primary = screenConfig.layouts[ScreenConfig.primaryKey] {
            result.append((key: ScreenConfig.primaryKey, node: primary))
        }
        let others = screenConfig.layouts
            .filter { $0.key != ScreenConfig.primaryKey }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, node: $0.value) }
        result.append(contentsOf: others)
        return result
    }
}

// MARK: - Previews

#if DEBUG
extension OverlayViewModel {
    static func preview(rootNode: LayoutNode? = nil) -> OverlayViewModel {
        let vm = OverlayViewModel()
        let previewRoot = rootNode ?? LayoutNode.columns([
            .pinned(app: "Xcode", percentage: 60),
            .rows([
                .pinned(app: "Terminal", percentage: 50),
                .stackAll(percentage: 50)
            ])
        ])
        let layout = WTLayout(
            name: "Coding",
            quickKey: "c",
            screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: previewRoot])]
        )
        let secondary = WTLayout(
            name: "Focus",
            quickKey: "f",
            screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])]
        )
        let thirds = WTLayout(
            name: "Thirds",
            quickKey: "3",
            screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .columns([
                .empty(percentage: 33),
                .empty(percentage: 34),
                .empty(percentage: 33)
            ])])]
        )
        vm.layouts = [layout, secondary, thirds]
        vm.editingLayout = layout
        vm.selectedScreenSetIndex = 0
        vm.refreshEditingRootNode()
        vm.runningApps = [
            RunningAppInfo(name: "Safari", bundleId: "com.apple.Safari"),
            RunningAppInfo(name: "Terminal", bundleId: "com.apple.Terminal"),
            RunningAppInfo(name: "Xcode", bundleId: "com.apple.dt.Xcode"),
            RunningAppInfo(name: "Slack", bundleId: "com.tinyspeck.slackmacgap"),
        ]
        return vm
    }
}

#Preview("Full Overlay") {
    OverlayView(viewModel: .preview())
        .frame(width: 960, height: 640)
}

#Preview("Compact Stack Tile") {
    CompactTileView(node: .stackAll(), size: CGSize(width: 108, height: 46))
        .padding()
        .background(.regularMaterial)
}
#endif
