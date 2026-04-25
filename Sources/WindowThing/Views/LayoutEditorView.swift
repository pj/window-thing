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
        }
    }

    @ViewBuilder
    private var canvasArea: some View {
        if let rootNode = viewModel.editingRootNode {
            LayoutCanvasView(
                rootNode: rootNode,
                selectedPath: viewModel.selectedNodePath,
                runningApps: viewModel.runningApps,
                runningWindows: viewModel.runningWindows,
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
    let onSelect: ([Int]) -> Void
    let onRootChanged: (LayoutNode) -> Void
    let onDragStarted: () -> Void
    let onLiveRootChange: (LayoutNode) -> Void

    var body: some View {
        GeometryReader { geo in
            LayoutTileView(
                node: rootNode,
                rootNode: rootNode,
                path: [],
                selectedPath: selectedPath,
                containerSize: geo.size,
                runningApps: runningApps,
                runningWindows: runningWindows,
                onSelect: onSelect,
                onRootChanged: onRootChanged,
                onDragStarted: onDragStarted,
                onLiveRootChange: onLiveRootChange
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
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
        let frames = childFrames(children: cols, size: containerSize, isColumns: true)
        ZStack(alignment: .topLeading) {
            ForEach(Array(frames.enumerated()), id: \.offset) { i, item in
                LayoutTileView(
                    node: item.node,
                    rootNode: rootNode,
                    path: path + [i],
                    selectedPath: selectedPath,
                    containerSize: item.frame.size,
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
                .frame(width: item.frame.width, height: item.frame.height)
                .offset(x: item.frame.minX, y: item.frame.minY)

                if i < frames.count - 1 {
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
                        },
                        onInsert: {
                            let leftPct = cols[i].percentage ?? (100.0 / Double(cols.count))
                            let half = max(5, leftPct / 2)
                            var newCols = cols
                            newCols[i] = newCols[i].withPercentage(half)
                            newCols.insert(LayoutNode.empty(percentage: half), at: i + 1)
                            onRootChanged(node.withColumns(newCols))
                            onSelect(path + [i + 1])
                        }
                    )
                    .frame(width: 16, height: containerSize.height)
                    .offset(x: item.frame.maxX - 8, y: 0)
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .overlay(alignment: .leading) {
            EdgeInsertHandle {
                let firstPct = cols[0].percentage ?? (100.0 / Double(cols.count))
                let half = max(5, firstPct / 2)
                var newCols = cols
                newCols[0] = newCols[0].withPercentage(firstPct - half)
                newCols.insert(LayoutNode.empty(percentage: half), at: 0)
                onRootChanged(node.withColumns(newCols))
                onSelect(path + [0])
            }
            .frame(width: 16, height: containerSize.height)
        }
        .overlay(alignment: .trailing) {
            EdgeInsertHandle {
                let lastIdx = cols.count - 1
                let lastPct = cols[lastIdx].percentage ?? (100.0 / Double(cols.count))
                let half = max(5, lastPct / 2)
                var newCols = cols
                newCols[lastIdx] = newCols[lastIdx].withPercentage(lastPct - half)
                newCols.append(LayoutNode.empty(percentage: half))
                onRootChanged(node.withColumns(newCols))
                onSelect(path + [newCols.count - 1])
            }
            .frame(width: 16, height: containerSize.height)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowsLayout(_ rs: [LayoutNode]) -> some View {
        let frames = childFrames(children: rs, size: containerSize, isColumns: false)
        ZStack(alignment: .topLeading) {
            ForEach(Array(frames.enumerated()), id: \.offset) { i, item in
                LayoutTileView(
                    node: item.node,
                    rootNode: rootNode,
                    path: path + [i],
                    selectedPath: selectedPath,
                    containerSize: item.frame.size,
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
                .frame(width: item.frame.width, height: item.frame.height)
                .offset(x: item.frame.minX, y: item.frame.minY)

                if i < frames.count - 1 {
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
                        },
                        onInsert: {
                            let topPct = rs[i].percentage ?? (100.0 / Double(rs.count))
                            let half = max(5, topPct / 2)
                            var newRows = rs
                            newRows[i] = newRows[i].withPercentage(half)
                            newRows.insert(LayoutNode.empty(percentage: half), at: i + 1)
                            onRootChanged(node.withRows(newRows))
                            onSelect(path + [i + 1])
                        }
                    )
                    .frame(width: containerSize.width, height: 16)
                    .offset(x: 0, y: item.frame.maxY - 8)
                }
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .overlay(alignment: .top) {
            EdgeInsertHandle {
                let firstPct = rs[0].percentage ?? (100.0 / Double(rs.count))
                let half = max(5, firstPct / 2)
                var newRows = rs
                newRows[0] = newRows[0].withPercentage(firstPct - half)
                newRows.insert(LayoutNode.empty(percentage: half), at: 0)
                onRootChanged(node.withRows(newRows))
                onSelect(path + [0])
            }
            .frame(width: containerSize.width, height: 16)
        }
        .overlay(alignment: .bottom) {
            EdgeInsertHandle {
                let lastIdx = rs.count - 1
                let lastPct = rs[lastIdx].percentage ?? (100.0 / Double(rs.count))
                let half = max(5, lastPct / 2)
                var newRows = rs
                newRows[lastIdx] = newRows[lastIdx].withPercentage(lastPct - half)
                newRows.append(LayoutNode.empty(percentage: half))
                onRootChanged(node.withRows(newRows))
                onSelect(path + [newRows.count - 1])
            }
            .frame(width: containerSize.width, height: 16)
        }
    }

    // MARK: - Leaf Tile

    @State private var tileHovering = false

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
        }
        .onHover { tileHovering = $0 }
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
        // Root-level leaf: 4 edge handles to split into columns or rows
        .overlay(alignment: .leading) {
            if path.isEmpty {
                EdgeInsertHandle {
                    onRootChanged(LayoutNode.columns([.empty(percentage: 50), node.withPercentage(50)]))
                    onSelect([0])
                }
                .frame(width: 16, height: containerSize.height)
            }
        }
        .overlay(alignment: .trailing) {
            if path.isEmpty {
                EdgeInsertHandle {
                    onRootChanged(LayoutNode.columns([node.withPercentage(50), .empty(percentage: 50)]))
                    onSelect([1])
                }
                .frame(width: 16, height: containerSize.height)
            }
        }
        .overlay(alignment: .top) {
            if path.isEmpty {
                EdgeInsertHandle {
                    onRootChanged(LayoutNode.rows([.empty(percentage: 50), node.withPercentage(50)]))
                    onSelect([0])
                }
                .frame(width: containerSize.width, height: 16)
            }
        }
        .overlay(alignment: .bottom) {
            if path.isEmpty {
                EdgeInsertHandle {
                    onRootChanged(LayoutNode.rows([node.withPercentage(50), .empty(percentage: 50)]))
                    onSelect([1])
                }
                .frame(width: containerSize.width, height: 16)
            }
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
        let leafIdx = leafCountBefore(path, in: rootNode)
        let cellAddress = CellAddress.from(index: leafIdx + 1)
        ZStack(alignment: .bottomTrailing) {
            switch node.type {
            case .stack:
                stackVisual
            case .pinned:
                pinnedContent
            default:
                emptyContent
            }
            // Cell index badge
            if let addr = cellAddress {
                Text(addr.stringValue)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
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

    // MARK: - Frame Helpers

    private func childFrames(children: [LayoutNode], size: CGSize, isColumns: Bool) -> [(node: LayoutNode, frame: CGRect)] {
        let defaultP = children.isEmpty ? 100.0 : 100.0 / Double(children.count)
        let total = children.reduce(0.0) { $0 + ($1.percentage ?? defaultP) }
        var offset: CGFloat = 0
        return children.map { child in
            let fraction = CGFloat((child.percentage ?? defaultP) / total)
            if isColumns {
                let w = size.width * fraction
                let frame = CGRect(x: offset, y: 0, width: w, height: size.height)
                offset += w
                return (child, frame)
            } else {
                let h = size.height * fraction
                let frame = CGRect(x: 0, y: offset, width: size.width, height: h)
                offset += h
                return (child, frame)
            }
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
            if !isRoot {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
            }

            // Custom segmented control: Empty and Stack are toggles; Application is a dropdown.
            HStack(spacing: 0) {
                segmentButton(
                    label: "Empty", icon: "square",
                    active: node.type == .empty
                ) { onNodeChanged(node.withType(.empty)) }

                Divider().frame(height: 14)

                segmentButton(
                    label: "Stack", icon: "square.stack.fill",
                    active: node.type == .stack
                ) { onNodeChanged(node.withType(.stack)) }

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

// MARK: - Edge Insert Handle

/// A thin strip at the edge of a columns/rows layout that reveals a + button on hover.
struct EdgeInsertHandle: View {
    let onInsert: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(hovering ? Color.accentColor.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
            Button(action: onInsert) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 16)
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
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
    let onInsert: () -> Void

    @State private var dragging = false
    @State private var hovering = false
    @State private var startLeft: Double = 0
    @State private var startRight: Double = 0
    @State private var lastLeft: Double = 0
    @State private var lastRight: Double = 0

    var body: some View {
        ZStack {
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
                            onCommitted(lastLeft, lastRight)
                        }
                )

            if !dragging {
                Button(action: onInsert) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 16, height: 16)
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
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
    let onInsert: () -> Void

    @State private var dragging = false
    @State private var hovering = false
    @State private var startTop: Double = 0
    @State private var startBottom: Double = 0
    @State private var lastTop: Double = 0
    @State private var lastBottom: Double = 0

    var body: some View {
        ZStack {
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
                            onCommitted(lastTop, lastBottom)
                        }
                )

            if !dragging {
                Button(action: onInsert) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 16, height: 16)
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
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
