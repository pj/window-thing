import SwiftUI
import WindowThingCore
import WindowThingViewModel

// MARK: - Compact Tile View

/// Non-interactive mini renderer of a LayoutNode tree for use in compact previews
/// (the quick-move sheet, menu bar icons). The editable renderer lives in
/// `SpaceOverlayWindow.swift`.
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
            ForEach(0..<3, id: \.self) { index in
                stackCard(index: index)
            }
        }
    }

    /// One card of the stack's fanned-out look.
    ///
    /// Split out of the ZStack above, with every measurement given an explicit
    /// type. As a single chained expression the type-checker has to solve the
    /// corner radius, opacity, frame and offset arithmetic together, and Swift
    /// 6.3 gives up on it ("unable to type-check this expression in reasonable
    /// time"). 6.1 happened to manage it, so this only surfaced on a toolchain
    /// bump rather than when it was written.
    private func stackCard(index: Int) -> some View {
        let inset: CGFloat = CGFloat(2 - index) * max(1.5, size.width * 0.06)
        let radius: CGFloat = max(1, size.width * 0.04)
        let fill: Double = 0.1 + Double(index) * 0.06
        let cardWidth: CGFloat = max(4, size.width * 0.72 - inset)
        let cardHeight: CGFloat = max(3, size.height * 0.62 - inset * 0.6)

        return RoundedRectangle(cornerRadius: radius)
            .fill(Color.orange.opacity(fill))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
            )
            .frame(width: cardWidth, height: cardHeight)
            .offset(x: inset * 0.6, y: -inset * 0.4)
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

#Preview("Compact Stack Tile") {
    CompactTileView(node: .stackAll(), size: CGSize(width: 108, height: 46))
        .padding()
        .background(.regularMaterial)
}
#endif
