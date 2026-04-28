import SwiftUI
import AppKit
import WindowThingCore
import WindowThingViewModel

// MARK: - LayoutType Helpers

extension LayoutType {
    var displayName: String {
        switch self {
        case .empty: return "Empty"
        case .pinned: return "Pinned"
        case .stack: return "Stack"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .floatZoomed: return "Float"
        }
    }

    var systemImageName: String {
        switch self {
        case .empty: return "square"
        case .pinned: return "pin.fill"
        case .stack: return "square.stack.fill"
        case .columns: return "rectangle.split.2x1"
        case .rows: return "rectangle.split.1x2"
        case .floatZoomed: return "macwindow.and.cursorarrow"
        }
    }
}

// MARK: - Layout Editor Panel

struct LayoutEditorPanel: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let layout = viewModel.editingLayout, layout.screenSets.count > 1 {
                ScreenSetTabBar(viewModel: viewModel)
                    .frame(height: 32)
                Divider()
            }
            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Aspect ratio of the display this layout targets (width / height).
    private var displayAspectRatio: CGFloat {
        // Use the primary display, or fall back to a typical 16:10 ratio
        let primary = viewModel.displays.first(where: { $0.isMain }) ?? viewModel.displays.first
        guard let d = primary, d.frame.height > 0 else { return 16.0 / 10.0 }
        return d.frame.width / d.frame.height
    }

    @ViewBuilder
    private var canvasArea: some View {
        if let rootNode = viewModel.editingRootNode {
            LayoutCanvasView(
                rootNode: rootNode,
                selectedPath: viewModel.selectedNodePath,
                runningApps: viewModel.runningApps,
                runningWindows: viewModel.runningWindows,
                displayAspectRatio: displayAspectRatio,
                onSelect: { path in viewModel.selectedNodePath = path },
                onRootChanged: { newRoot in viewModel.commitEdit(newRoot) },
                onDragStarted: { viewModel.captureDragSnapshot() },
                onLiveRootChange: { newRoot in viewModel.updateRootNodeLive(newRoot) }
            )
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                VStack(spacing: 8) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No layout configured")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Layout Canvas View

struct LayoutCanvasView: View {
    let rootNode: LayoutNode
    let selectedPath: [Int]
    let runningApps: [RunningAppInfo]
    let runningWindows: [WTWindow]
    let displayAspectRatio: CGFloat
    let onSelect: ([Int]) -> Void
    let onRootChanged: (LayoutNode) -> Void
    let onDragStarted: () -> Void
    let onLiveRootChange: (LayoutNode) -> Void

    private let bezelWidth: CGFloat = 10
    private let bezelRadius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let availW = geo.size.width - 56
            let availH = geo.size.height - 48
            let canvasSize = fittedSize(aspect: displayAspectRatio, within: CGSize(width: availW, height: availH))
            let bezelW = canvasSize.width + bezelWidth * 2
            let bezelH = canvasSize.height + bezelWidth * 2

            ZStack {
                // Outer border
                RoundedRectangle(cornerRadius: bezelRadius + 1)
                    .stroke(
                        LinearGradient(
                            colors: [Color(white: 0.35), Color(white: 0.18)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .frame(width: bezelW + 2, height: bezelH + 2)

                // Bezel fill
                RoundedRectangle(cornerRadius: bezelRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.15)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: bezelW, height: bezelH)

                // Screen area
                LayoutTileView(
                    node: rootNode,
                    rootNode: rootNode,
                    path: [],
                    selectedPath: selectedPath,
                    containerSize: canvasSize,
                    runningApps: runningApps,
                    runningWindows: runningWindows,
                    onSelect: onSelect,
                    onRootChanged: onRootChanged,
                    onDragStarted: onDragStarted,
                    onLiveRootChange: onLiveRootChange
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.5), lineWidth: 0.5)
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Fit a rectangle with the given aspect ratio inside the available space.
    private func fittedSize(aspect: CGFloat, within available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0, aspect > 0 else {
            return available
        }
        let availableAspect = available.width / available.height
        if aspect > availableAspect {
            // Width-constrained
            return CGSize(width: available.width, height: available.width / aspect)
        } else {
            // Height-constrained
            return CGSize(width: available.height * aspect, height: available.height)
        }
    }
}

// MARK: - Cell Index Helpers

/// Count the number of leaf nodes that appear before `targetPath` in a depth-first traversal.
private func leafCountBefore(_ targetPath: [Int], in node: LayoutNode) -> Int {
    var count = 0
    func visit(_ n: LayoutNode, _ currentPath: [Int]) -> Bool {
        switch n.type {
        case .columns:
            for (i, col) in (n.columns ?? []).enumerated() {
                if visit(col, currentPath + [i]) { return true }
            }
        case .rows:
            for (i, row) in (n.rows ?? []).enumerated() {
                if visit(row, currentPath + [i]) { return true }
            }
        default:
            if currentPath == targetPath { return true }
            count += 1
        }
        return false
    }
    _ = visit(node, [])
    return count
}

// MARK: - Layout Tile View

struct LayoutTileView: View {
    let node: LayoutNode
    /// The full tree root, threaded down so leaf tiles can compute their cell index.
    let rootNode: LayoutNode
    let path: [Int]
    let selectedPath: [Int]
    let containerSize: CGSize
    let runningApps: [RunningAppInfo]
    let runningWindows: [WTWindow]
    let onSelect: ([Int]) -> Void
    let onRootChanged: (LayoutNode) -> Void
    let onDragStarted: () -> Void
    let onLiveRootChange: (LayoutNode) -> Void

    var body: some View {
        switch node.type {
        case .columns:
            if let cols = node.columns, !cols.isEmpty {
                columnsLayout(cols)
            } else {
                leafTile
            }
        case .rows:
            if let rs = node.rows, !rs.isEmpty {
                rowsLayout(rs)
            } else {
                leafTile
            }
        default:
            leafTile
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private func columnsLayout(_ cols: [LayoutNode]) -> some View {
        let widths = childSizes(children: cols, totalLength: containerSize.width)
        HStack(spacing: 0) {
            ForEach(Array(cols.enumerated()), id: \.offset) { i, col in
                LayoutTileView(
                    node: col,
                    rootNode: rootNode,
                    path: path + [i],
                    selectedPath: selectedPath,
                    containerSize: CGSize(width: widths[i], height: containerSize.height),
                    runningApps: runningApps,
                    runningWindows: runningWindows,
                    onSelect: onSelect,
                    onRootChanged: { newChild in
                        var newCols = cols
                        newCols[i] = newChild
                        onRootChanged(node.withColumns(newCols))
                    },
                    onDragStarted: onDragStarted,
                    onLiveRootChange: { newChild in
                        var newCols = cols
                        newCols[i] = newChild
                        onLiveRootChange(node.withColumns(newCols))
                    }
                )
                .frame(width: widths[i], height: containerSize.height)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .overlay {
            // Drag handles overlaid at column boundaries
            let offsets = columnHandleOffsets(widths: widths)
            ForEach(Array(offsets.enumerated()), id: \.offset) { i, xPos in
                let defaultP = 100.0 / Double(cols.count)
                ColumnDragHandle(
                    leftPct: cols[i].percentage ?? defaultP,
                    rightPct: cols[i + 1].percentage ?? defaultP,
                    containerWidth: containerSize.width,
                    onDragStarted: onDragStarted,
                    onChanging: { lPct, rPct in
                        var newCols = cols
                        newCols[i] = newCols[i].withPercentage(lPct)
                        newCols[i + 1] = newCols[i + 1].withPercentage(rPct)
                        onLiveRootChange(node.withColumns(newCols))
                    },
                    onCommitted: { lPct, rPct in
                        var newCols = cols
                        newCols[i] = newCols[i].withPercentage(lPct)
                        newCols[i + 1] = newCols[i + 1].withPercentage(rPct)
                        onRootChanged(node.withColumns(newCols))
                    }
                )
                .frame(width: 12, height: containerSize.height)
                .position(x: xPos, y: containerSize.height / 2)
            }
        }
    }

    private func columnHandleOffsets(widths: [CGFloat]) -> [CGFloat] {
        var offsets: [CGFloat] = []
        var accum: CGFloat = 0
        for i in 0..<(widths.count - 1) {
            accum += widths[i]
            offsets.append(accum)
        }
        return offsets
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowsLayout(_ rs: [LayoutNode]) -> some View {
        let heights = childSizes(children: rs, totalLength: containerSize.height)
        VStack(spacing: 0) {
            ForEach(Array(rs.enumerated()), id: \.offset) { i, row in
                LayoutTileView(
                    node: row,
                    rootNode: rootNode,
                    path: path + [i],
                    selectedPath: selectedPath,
                    containerSize: CGSize(width: containerSize.width, height: heights[i]),
                    runningApps: runningApps,
                    runningWindows: runningWindows,
                    onSelect: onSelect,
                    onRootChanged: { newChild in
                        var newRows = rs
                        newRows[i] = newChild
                        onRootChanged(node.withRows(newRows))
                    },
                    onDragStarted: onDragStarted,
                    onLiveRootChange: { newChild in
                        var newRows = rs
                        newRows[i] = newChild
                        onLiveRootChange(node.withRows(newRows))
                    }
                )
                .frame(width: containerSize.width, height: heights[i])
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .overlay {
            // Drag handles overlaid at row boundaries
            let offsets = rowHandleOffsets(heights: heights)
            ForEach(Array(offsets.enumerated()), id: \.offset) { i, yPos in
                let defaultP = 100.0 / Double(rs.count)
                RowDragHandle(
                    topPct: rs[i].percentage ?? defaultP,
                    bottomPct: rs[i + 1].percentage ?? defaultP,
                    containerHeight: containerSize.height,
                    onDragStarted: onDragStarted,
                    onChanging: { tPct, bPct in
                        var newRows = rs
                        newRows[i] = newRows[i].withPercentage(tPct)
                        newRows[i + 1] = newRows[i + 1].withPercentage(bPct)
                        onLiveRootChange(node.withRows(newRows))
                    },
                    onCommitted: { tPct, bPct in
                        var newRows = rs
                        newRows[i] = newRows[i].withPercentage(tPct)
                        newRows[i + 1] = newRows[i + 1].withPercentage(bPct)
                        onRootChanged(node.withRows(newRows))
                    }
                )
                .frame(width: containerSize.width, height: 12)
                .position(x: containerSize.width / 2, y: yPos)
            }
        }
    }

    private func rowHandleOffsets(heights: [CGFloat]) -> [CGFloat] {
        var offsets: [CGFloat] = []
        var accum: CGFloat = 0
        for i in 0..<(heights.count - 1) {
            accum += heights[i]
            offsets.append(accum)
        }
        return offsets
    }

    // MARK: - Leaf Tile

    @State private var tileHovering = false
    @State private var splitAxis: SplitAxis? = nil
    /// Normalized position (0–1) along the split axis, snapped to 5% increments.
    @State private var splitPosition: CGFloat = 0.5

    private var leafTile: some View {
        ZStack {
            tileBackground
            VStack(spacing: 0) {
                if tileHovering {
                    // Controls appear on hover
                    TileInlineControls(
                        node: node,
                        isRoot: path.isEmpty,
                        runningApps: runningApps,
                        runningWindows: runningWindows,
                        onDelete: {
                            onRootChanged(LayoutNode.empty(percentage: node.percentage ?? 100))
                            onSelect([])
                        },
                        onNodeChanged: { newNode in onRootChanged(newNode) }
                    )
                    Divider()
                }
                tileContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Split line overlay
            if tileHovering, let axis = splitAxis {
                SplitLineOverlay(axis: axis, position: splitPosition)
                    .onTapGesture { performSplit(axis: axis) }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                tileHovering = true
                let normalizedX = location.x / max(containerSize.width, 1)
                let normalizedY = location.y / max(containerSize.height, 1)

                // Determine split axis based on mouse proximity to center lines
                let aspectRatio = containerSize.width / max(containerSize.height, 1)
                let distFromVerticalCenter = abs(normalizedX - 0.5)
                let distFromHorizontalCenter = abs(normalizedY - 0.5)
                let biasedVertDist = distFromVerticalCenter / max(aspectRatio, 0.5)
                let biasedHorizDist = distFromHorizontalCenter * max(aspectRatio, 0.5)
                let axis: SplitAxis = biasedVertDist < biasedHorizDist ? .vertical : .horizontal
                splitAxis = axis

                // Snap position to 5% increments, clamped to 10–90%
                let raw = axis == .vertical ? normalizedX : normalizedY
                let snapped = (raw * 20).rounded() / 20  // 5% steps
                splitPosition = min(max(snapped, 0.1), 0.9)
            case .ended:
                tileHovering = false
                splitAxis = nil
            }
        }
        // Clip prevents controls from overflowing into adjacent tiles
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .dropDestination(for: RunningAppInfo.self) { items, _ in
            guard let app = items.first else { return false }
            let pinned = PinnedConfig(application: app.name, bundleId: app.bundleId)
            onRootChanged(LayoutNode(type: .pinned, percentage: node.percentage, pinned: pinned))
            onSelect(path)
            return true
        }
    }

    private func performSplit(axis: SplitAxis) {
        let leftPct = Double(splitPosition * 100)
        let rightPct = 100.0 - leftPct
        switch axis {
        case .vertical:
            onRootChanged(LayoutNode.columns([node.withPercentage(leftPct), .empty(percentage: rightPct)]))
            onSelect(path + [1])
        case .horizontal:
            onRootChanged(LayoutNode.rows([node.withPercentage(leftPct), .empty(percentage: rightPct)]))
            onSelect(path + [1])
        }
    }

    @ViewBuilder
    private var tileBackground: some View {
        switch node.type {
        case .pinned:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
        case .stack:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1))
        default:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                )
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        switch node.type {
        case .stack:
            stackVisual
        case .pinned:
            pinnedContent
        default:
            emptyContent
        }
    }

    private var stackVisual: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let o = CGFloat(2 - i) * 4.0
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.15 + Double(i) * 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                    .frame(width: 36, height: 24)
                    .offset(x: o * 0.7, y: -o)
            }
        }
    }

    private var pinnedContent: some View {
        VStack(spacing: 3) {
            Image(systemName: "pin.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
            let label = node.pinned?.application ?? node.pinned?.bundleId ?? ""
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let pct = node.percentage {
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(6)
    }

    private var emptyContent: some View {
        VStack(spacing: 3) {
            if let pct = node.percentage {
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            Text("Drop app here")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(6)
    }

    // MARK: - Size Helpers

    /// Returns the pixel sizes for each child along the split axis.
    private func childSizes(children: [LayoutNode], totalLength: CGFloat) -> [CGFloat] {
        let defaultP = children.isEmpty ? 100.0 : 100.0 / Double(children.count)
        let total = children.reduce(0.0) { $0 + ($1.percentage ?? defaultP) }
        return children.map { child in
            CGFloat((child.percentage ?? defaultP) / total) * totalLength
        }
    }
}

// MARK: - Tile Inline Controls

/// Controls that sit inside the selected leaf tile, offset from the top.
struct TileInlineControls: View {
    let node: LayoutNode
    let isRoot: Bool
    let runningApps: [RunningAppInfo]
    let runningWindows: [WTWindow]
    let onDelete: () -> Void
    let onNodeChanged: (LayoutNode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Stack nodes can't be deleted
            if !isRoot && node.type != .stack {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
            }

            if node.type == .stack {
                // Stack just shows a label — can't be changed or deleted
                Label("Stack", systemImage: "square.stack.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
            } else {
                // Segmented control for empty/pinned nodes
                HStack(spacing: 0) {
                    segmentButton(
                        label: "Empty", icon: "square",
                        active: node.type == .empty
                    ) { onNodeChanged(node.withType(.empty)) }

                    Divider().frame(height: 14)

                    // Application segment — dropdown to pick app directly
                    appDropdown
                }
                .fixedSize()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))

                // Window picker — separate control, only when an app is pinned and has multiple windows
                if node.type == .pinned, windowsForCurrentApp.count > 1 {
                    windowPicker
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: - Segment button (toggle style)

    private func segmentButton(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(active ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Application dropdown segment

    private var appDropdown: some View {
        let active = node.type == .pinned
        let appName = node.pinned?.application ?? "Application"
        return Menu {
            ForEach(runningApps) { app in
                Button(app.name) { pinApp(app) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "pin.fill").font(.system(size: 9))
                Text(active ? appName : "Application")
                    .font(.system(size: 10, weight: active ? .semibold : .regular))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(active ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Window picker (multi-select)

    private var windowsForCurrentApp: [WTWindow] {
        guard let pinned = node.pinned else { return [] }
        return runningWindows.filter {
            $0.bundleId == pinned.bundleId || $0.application == pinned.application
        }
    }

    private var selectedTitles: Set<String> {
        Set(node.pinned?.windowTitles ?? [])
    }

    private var windowPicker: some View {
        let windows = windowsForCurrentApp
        let titles = selectedTitles
        let label = titles.isEmpty ? "All Windows" : titles.count == 1 ? titles.first! : "\(titles.count) Windows"

        return Menu {
            // "All Windows" option — clears selection
            Button {
                updateWindowTitles([])
            } label: {
                Label("All Windows", systemImage: titles.isEmpty ? "checkmark" : "")
            }
            Divider()
            ForEach(windows) { w in
                let display = w.title.isEmpty ? "Untitled" : w.title
                let checked = titles.contains(w.title)
                Button {
                    toggleWindow(w.title)
                } label: {
                    Label(display, systemImage: checked ? "checkmark" : "")
                }
            }
        } label: {
            Label(label, systemImage: "macwindow")
                .font(.system(size: 11))
        }
        .fixedSize()
    }

    // MARK: - Helpers

    private func pinApp(_ app: RunningAppInfo) {
        let pinned = PinnedConfig(application: app.name, bundleId: app.bundleId)
        onNodeChanged(LayoutNode(type: .pinned, percentage: node.percentage, pinned: pinned))
    }

    private func toggleWindow(_ title: String) {
        guard let pinned = node.pinned else { return }
        var titles = Set(pinned.windowTitles ?? [])
        if titles.contains(title) {
            titles.remove(title)
        } else {
            titles.insert(title)
        }
        updateWindowTitles(Array(titles))
    }

    private func updateWindowTitles(_ titles: [String]) {
        guard let pinned = node.pinned else { return }
        let updated = PinnedConfig(
            application: pinned.application,
            bundleId: pinned.bundleId,
            windowTitles: titles.isEmpty ? nil : titles
        )
        onNodeChanged(LayoutNode(type: .pinned, percentage: node.percentage, pinned: updated))
    }
}

// MARK: - Split Axis

enum SplitAxis {
    case vertical, horizontal
}

// MARK: - Split Line Overlay

/// Shows a dashed line with a scissor icon indicating where a tile will be split.
struct SplitLineOverlay: View {
    let axis: SplitAxis
    /// Normalized position (0–1) along the split axis.
    let position: CGFloat

    var body: some View {
        GeometryReader { geo in
            let pos = axis == .vertical
                ? CGPoint(x: geo.size.width * position, y: geo.size.height / 2)
                : CGPoint(x: geo.size.width / 2, y: geo.size.height * position)

            ZStack {
                // Dashed split line
                if axis == .vertical {
                    Path { p in
                        let x = geo.size.width * position
                        p.move(to: CGPoint(x: x, y: 8))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height - 8))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                } else {
                    Path { p in
                        let y = geo.size.height * position
                        p.move(to: CGPoint(x: 8, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width - 8, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                }

                // Scissor icon at the split position
                Image(systemName: "scissors")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .rotationEffect(axis == .vertical ? .degrees(90) : .degrees(0))
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .position(pos)
            }
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
    }
}

// MARK: - Column Drag Handle

struct ColumnDragHandle: View {
    let leftPct: Double
    let rightPct: Double
    let containerWidth: CGFloat
    let onDragStarted: () -> Void
    let onChanging: (Double, Double) -> Void
    let onCommitted: (Double, Double) -> Void

    @State private var dragging = false
    @State private var hovering = false
    @State private var startLeft: Double = 0
    @State private var startRight: Double = 0
    @State private var lastLeft: Double = 0
    @State private var lastRight: Double = 0

    var body: some View {
        Rectangle()
            .fill(dragging ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(dragging ? Color.accentColor : Color.secondary.opacity(hovering ? 0.4 : 0.18))
                    .frame(width: 2)
            )
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { val in
                        if !dragging {
                            dragging = true
                            NSCursor.resizeLeftRight.push()
                            startLeft = leftPct
                            startRight = rightPct
                            lastLeft = leftPct
                            lastRight = rightPct
                            onDragStarted()
                        }
                        let total = startLeft + startRight
                        let deltaPct = Double(val.translation.width / containerWidth) * total
                        let newLeft = min(max(5, startLeft + deltaPct), total - 5)
                        let newRight = total - newLeft
                        lastLeft = newLeft
                        lastRight = newRight
                        onChanging(newLeft, newRight)
                    }
                    .onEnded { _ in
                        dragging = false
                        NSCursor.pop()
                        onCommitted(lastLeft, lastRight)
                    }
            )
    }
}

// MARK: - Row Drag Handle

struct RowDragHandle: View {
    let topPct: Double
    let bottomPct: Double
    let containerHeight: CGFloat
    let onDragStarted: () -> Void
    let onChanging: (Double, Double) -> Void
    let onCommitted: (Double, Double) -> Void

    @State private var dragging = false
    @State private var hovering = false
    @State private var startTop: Double = 0
    @State private var startBottom: Double = 0
    @State private var lastTop: Double = 0
    @State private var lastBottom: Double = 0

    var body: some View {
        Rectangle()
            .fill(dragging ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(dragging ? Color.accentColor : Color.secondary.opacity(hovering ? 0.4 : 0.18))
                    .frame(height: 2)
            )
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { val in
                        if !dragging {
                            dragging = true
                            NSCursor.resizeUpDown.push()
                            startTop = topPct
                            startBottom = bottomPct
                            lastTop = topPct
                            lastBottom = bottomPct
                            onDragStarted()
                        }
                        let total = startTop + startBottom
                        let deltaPct = Double(val.translation.height / containerHeight) * total
                        let newTop = min(max(5, startTop + deltaPct), total - 5)
                        let newBottom = total - newTop
                        lastTop = newTop
                        lastBottom = newBottom
                        onChanging(newTop, newBottom)
                    }
                    .onEnded { _ in
                        dragging = false
                        NSCursor.pop()
                        onCommitted(lastTop, lastBottom)
                    }
            )
    }
}

// MARK: - Screen Set Tab Bar

/// Tab bar showing one tab per screen set, with add/remove controls.
struct ScreenSetTabBar: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array((viewModel.editingLayout?.screenSets ?? []).enumerated()), id: \.offset) { i, _ in
                        let selected = viewModel.selectedScreenSetIndex == i
                        Button("Screen Set \(i + 1)") {
                            viewModel.selectScreenSet(i)
                        }
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            // Remove current screen set (only if >1 exist)
            if (viewModel.editingLayout?.screenSets.count ?? 0) > 1 {
                Button {
                    viewModel.removeScreenSet(at: viewModel.selectedScreenSetIndex)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Remove this screen set")
            }

            // Add screen set
            Button {
                viewModel.addScreenSet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.trailing, 8)
            .help("Add screen set")
        }
        .background(.thinMaterial)
    }
}

// MARK: - Editor Top Bar

// MARK: - Previews

#if DEBUG
#Preview("Full Overlay") {
    OverlayView(viewModel: .preview())
        .frame(width: 960, height: 640)
}

#Preview("Layout Editor Panel") {
    LayoutEditorPanel(viewModel: .preview())
        .frame(width: 720, height: 480)
}

#Preview("Layout Canvas — Three columns") {
    let root = LayoutNode.columns([
        .pinned(app: "Xcode", percentage: 50),
        .empty(percentage: 25),
        .stackAll(percentage: 25)
    ])
    return LayoutCanvasView(
        rootNode: root,
        selectedPath: [0],
        runningApps: [RunningAppInfo(name: "Xcode", bundleId: "com.apple.dt.Xcode")],
        runningWindows: [],
        displayAspectRatio: 16.0 / 10.0,
        onSelect: { _ in },
        onRootChanged: { _ in },
        onDragStarted: {},
        onLiveRootChange: { _ in }
    )
    .frame(width: 500, height: 300)
}

#Preview("Tile Inline Controls — Pinned") {
    TileInlineControls(
        node: .pinned(app: "Safari", percentage: 60),
        isRoot: false,
        runningApps: [
            RunningAppInfo(name: "Safari", bundleId: "com.apple.Safari"),
            RunningAppInfo(name: "Xcode", bundleId: "com.apple.dt.Xcode"),
        ],
        runningWindows: [],
        onDelete: {},
        onNodeChanged: { _ in }
    )
    .padding()
    .background(.regularMaterial)
}

#Preview("Tile Inline Controls — Empty (root)") {
    TileInlineControls(
        node: .empty(percentage: 100),
        isRoot: true,
        runningApps: [],
        runningWindows: [],
        onDelete: {},
        onNodeChanged: { _ in }
    )
    .padding()
    .background(.regularMaterial)
}

#endif
