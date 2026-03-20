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
    private let viewModel: OverlayViewModel

    init() {
        viewModel = OverlayViewModel()

        let screenBounds = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowWidth: CGFloat = 960
        let windowHeight: CGFloat = 640
        let windowRect = NSRect(
            x: (screenBounds.width - windowWidth) / 2 + screenBounds.origin.x,
            y: (screenBounds.height - windowHeight) / 2 + screenBounds.origin.y,
            width: windowWidth,
            height: windowHeight
        )

        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "WindowThing"
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hv = NSHostingView(rootView: OverlayView(viewModel: viewModel) { [weak self] in
            self?.hideOverlay()
        })
        hv.frame = NSRect(origin: .zero, size: windowRect.size)
        self.contentView = hv
    }

    func showOverlay() {
        viewModel.refresh()
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideOverlay() {
        self.orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var undoManager: UndoManager? { viewModel.undoManager }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            hideOverlay()
            return
        }
        if let characters = event.charactersIgnoringModifiers {
            if LayoutManager.shared.applyLayoutByQuickKey(characters) {
                hideOverlay()
                return
            }
        }
        super.keyDown(with: event)
    }
}

// MARK: - OverlayView

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            layoutCarousel
            Divider()
            if viewModel.layouts.isEmpty {
                noLayoutsView
            } else {
                LayoutEditorPanel(viewModel: viewModel, onDismiss: onDismiss)
            }
        }
    }

    // MARK: - Carousel

    private var layoutCarousel: some View {
        HStack(spacing: 0) {
            Button(action: { viewModel.carouselPageBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(viewModel.carouselCanGoBack ? 1 : 0)
            .disabled(!viewModel.carouselCanGoBack)
            .frame(width: 28)

            HStack(spacing: 8) {
                let start = viewModel.carouselOffset
                let end = min(start + viewModel.carouselPageSize, viewModel.layouts.count)
                ForEach(start..<end, id: \.self) { i in
                    LayoutPickerCard(
                        layout: viewModel.layouts[i],
                        isSelected: viewModel.editingLayout?.id == viewModel.layouts[i].id,
                        onSelect: { viewModel.selectLayout(at: i) }
                    )
                }
                if (end - start) < viewModel.carouselPageSize {
                    ForEach(0..<(viewModel.carouselPageSize - (end - start)), id: \.self) { _ in
                        Spacer().frame(width: 118)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: { viewModel.carouselPageForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(viewModel.carouselCanGoForward ? 1 : 0)
            .disabled(!viewModel.carouselCanGoForward)
            .frame(width: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(height: 96)
        .background(.thinMaterial)
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

// MARK: - Layout Picker Card

struct LayoutPickerCard: View {
    let layout: WTLayout
    let isSelected: Bool
    let onSelect: () -> Void

    private let cardWidth: CGFloat = 118
    private let graphicHeight: CGFloat = 54

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                // Graphic preview
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected
                              ? Color.accentColor.opacity(0.08)
                              : Color.secondary.opacity(0.05))
                    if let screenSet = layout.screenSets.first {
                        MultiMonitorPreviewView(
                            screenConfig: screenSet,
                            graphicSize: CGSize(width: cardWidth - 10, height: graphicHeight - 6)
                        )
                    }
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.2),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                }
                .frame(width: cardWidth, height: graphicHeight)

                // Hotkey cap on LEFT, name on right
                HStack(spacing: 5) {
                    if let key = layout.quickKey {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                                .shadow(color: .secondary.opacity(0.35), radius: 0, x: 0, y: 1.5)
                            Text(key.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 18, height: 15)
                    }
                    Text(layout.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(width: cardWidth)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
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
    OverlayView(viewModel: .preview(), onDismiss: {})
        .frame(width: 960, height: 640)
}

#Preview("Layout Picker Card") {
    HStack(spacing: 12) {
        LayoutPickerCard(
            layout: WTLayout(name: "Coding", quickKey: "c", screenSets: [
                ScreenConfig(layouts: [ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Xcode", percentage: 60),
                    .empty(percentage: 40)
                ])])
            ]),
            isSelected: true,
            onSelect: {}
        )
        LayoutPickerCard(
            layout: WTLayout(name: "Focus", quickKey: nil, screenSets: [
                ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
            ]),
            isSelected: false,
            onSelect: {}
        )
    }
    .padding()
    .background(.regularMaterial)
}

#Preview("Compact Stack Tile") {
    CompactTileView(node: .stackAll(), size: CGSize(width: 108, height: 46))
        .padding()
        .background(.regularMaterial)
}
#endif
