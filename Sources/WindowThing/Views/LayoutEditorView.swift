import SwiftUI
import AppKit
import WindowThingCore
import WindowThingViewModel

// MARK: - Toolbar Pill Group (Safari-style bordered capsule container)

/// Wraps child content in a Safari-style pill with a subtle border.
struct ToolbarPill<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

/// A single item inside a ToolbarPill. Borderless at rest, highlight on hover.
struct ToolbarPillButton<Label: View>: View {
    let action: () -> Void
    let active: Bool
    @ViewBuilder let label: () -> Label
    @State private var isHovering = false

    init(active: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.active = active
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 13))
                .foregroundStyle(active ? Color.accentColor : .primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? Color.accentColor.opacity(0.12)
                              : isHovering ? Color.primary.opacity(0.08)
                              : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A menu inside a ToolbarPill.
struct ToolbarPillMenu<MenuContent: View, Label: View>: View {
    let active: Bool
    @ViewBuilder let menuContent: () -> MenuContent
    @ViewBuilder let label: () -> Label
    @State private var isHovering = false

    var body: some View {
        Menu {
            menuContent()
        } label: {
            label()
                .font(.system(size: 13))
                .foregroundStyle(active ? Color.accentColor : .primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? Color.accentColor.opacity(0.12)
                              : isHovering ? Color.primary.opacity(0.08)
                              : Color.clear)
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onHover { isHovering = $0 }
    }
}

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
                thumbnailRevision: viewModel.thumbnailRevision,
                displayAspectRatio: displayAspectRatio,
                onSelect: { viewModel.selectedNodePath = $0 },
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
    let selectedPath: NodePath
    let runningApps: [RunningAppInfo]
    let runningWindows: [WTWindow]
    let thumbnailRevision: Int
    let displayAspectRatio: CGFloat
    let onSelect: (NodePath) -> Void
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
                    path: .root,
                    selectedPath: selectedPath,
                    containerSize: canvasSize,
                    runningApps: runningApps,
                    runningWindows: runningWindows,
                    thumbnailRevision: thumbnailRevision,
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

// MARK: - Layout Tile View

struct LayoutTileView: View {
    let node: LayoutNode
    /// The full tree root, threaded down so leaf tiles can compute their cell index.
    let rootNode: LayoutNode
    let path: NodePath
    let selectedPath: NodePath
    let containerSize: CGSize
    let runningApps: [RunningAppInfo]
    let runningWindows: [WTWindow]
    let thumbnailRevision: Int
    let onSelect: (NodePath) -> Void
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
                    path: path.appending(i),
                    selectedPath: selectedPath,
                    containerSize: CGSize(width: widths[i], height: containerSize.height),
                    runningApps: runningApps,
                    runningWindows: runningWindows,
                    thumbnailRevision: thumbnailRevision,
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
                    path: path.appending(i),
                    selectedPath: selectedPath,
                    containerSize: CGSize(width: containerSize.width, height: heights[i]),
                    runningApps: runningApps,
                    runningWindows: runningWindows,
                    thumbnailRevision: thumbnailRevision,
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

    private var isSelected: Bool { path == selectedPath }

    private var leafTile: some View {
        Button {
            onSelect(path)
        } label: {
            ZStack {
                tileBackground
                tileContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .dropDestination(for: RunningAppInfo.self) { items, _ in
            guard let app = items.first else { return false }
            let pinned = PinnedConfig(application: app.name, bundleId: app.bundleId)
            onRootChanged(LayoutNode(type: .pinned, percentage: node.percentage, pinned: pinned))
            onSelect(path)
            return true
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
        let _ = thumbnailRevision
        let stackThumbnails = stackWindowThumbnails
        let maxCards = min(stackThumbnails.count, 3)
        let inset: CGFloat = 12.0  // space for offset cards behind

        return ZStack {
            if stackThumbnails.isEmpty {
                // Fallback: stylized placeholder cards
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
            } else {
                // Back-to-front: last item drawn on top (frontmost window)
                ForEach(0..<maxCards, id: \.self) { i in
                    let reverseIdx = maxCards - 1 - i
                    let offset = CGFloat(reverseIdx) * inset
                    Image(nsImage: stackThumbnails[i])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: containerSize.width - inset * CGFloat(maxCards - 1),
                            height: containerSize.height - inset * CGFloat(maxCards - 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(white: 0.3), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 2, y: 2)
                        .offset(x: -offset, y: -offset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Get thumbnails for windows that belong in this stack (not pinned elsewhere).
    /// Windows are already in z-order (frontmost first) from CGWindowListCopyWindowInfo.
    private var stackWindowThumbnails: [NSImage] {
        let cache = WindowThumbnailCache.shared
        let pinnedApps = collectPinnedApps(in: rootNode)
        var thumbnails: [NSImage] = []
        for window in runningWindows {
            // Skip our own window
            if window.application == "WindowThing" { continue }
            // Skip windows whose app is pinned in another tile
            let isPinned = pinnedApps.contains { app in
                if let bundleId = app.bundleId, window.bundleId == bundleId { return true }
                if let name = app.application,
                   window.application.localizedCaseInsensitiveCompare(name) == .orderedSame { return true }
                return false
            }
            if isPinned { continue }
            if let img = cache.nsImage(for: window.id) {
                thumbnails.append(img)
            }
            if thumbnails.count >= 3 { break }
        }
        return thumbnails
    }

    /// Collect all PinnedConfigs from the layout tree (excluding stack nodes).
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

    private var pinnedContent: some View {
        let _ = thumbnailRevision // force SwiftUI dependency on cache updates
        let thumbnail = pinnedThumbnail
        let appIcon = pinnedAppIcon

        return ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(0.6)
            }

            VStack(spacing: 3) {
                if thumbnail == nil, let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else if thumbnail == nil {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
                let label = node.pinned?.application ?? node.pinned?.bundleId ?? ""
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: thumbnail != nil ? .medium : .regular))
                        .foregroundStyle(thumbnail != nil ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .shadow(color: thumbnail != nil ? .black.opacity(0.5) : .clear, radius: 2)
                }
            }
            .padding(6)
        }
    }

    /// Find a thumbnail for this pinned node by matching windows.
    private var pinnedThumbnail: NSImage? {
        guard let pinned = node.pinned else { return nil }
        let cache = WindowThumbnailCache.shared
        // Find the first matching window
        for window in runningWindows {
            if let bundleId = pinned.bundleId, window.bundleId == bundleId {
                if let img = cache.nsImage(for: window.id) { return img }
            } else if let app = pinned.application,
                      window.application.localizedCaseInsensitiveCompare(app) == .orderedSame {
                if let img = cache.nsImage(for: window.id) { return img }
            }
        }
        return nil
    }

    /// Get the app icon for this pinned node.
    private var pinnedAppIcon: NSImage? {
        guard let bundleId = node.pinned?.bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            // Try by name
            if let appName = node.pinned?.application {
                let apps = NSWorkspace.shared.runningApplications
                if let app = apps.first(where: { $0.localizedName == appName }) {
                    return app.icon
                }
            }
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
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

// MARK: - Tile Context Toolbar

/// Contextual toolbar above the canvas showing controls for the selected tile.
struct TileContextToolbar: View {
    let selectedPath: NodePath
    let rootNode: LayoutNode?
    let runningApps: [RunningAppInfo]
    let runningWindows: [WTWindow]
    let onNodeChanged: (LayoutNode) -> Void
    let onDeselect: () -> Void

    private var selectedNode: LayoutNode? {
        guard let root = rootNode else { return nil }
        // If no explicit selection but root is a leaf, treat root as selected
        if selectedPath.isRoot {
            switch root.type {
            case .columns, .rows: return nil
            default: return root
            }
        }
        return selectedPath.node(in: root)
    }

    private var isLeaf: Bool {
        guard let root = rootNode else { return false }
        if selectedPath.isRoot {
            switch root.type {
            case .columns, .rows: return false
            default: return true
            }
        }
        return selectedPath.isLeaf(in: root)
    }

    private var hasSelection: Bool {
        selectedNode != nil && isLeaf
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left: delete
            if let node = selectedNode, isLeaf, !selectedPath.isRoot, node.type != .stack {
                ToolbarPill {
                    ToolbarPillButton(action: deleteSelectedNode) {
                        Image(systemName: "trash")
                    }
                }
                .help("Delete pane")
            }

            Spacer(minLength: 0)

            // Center: pane type + app picker
            if let node = selectedNode, isLeaf {
                centerControls(node)
            } else {
                Text("Click a pane to edit")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Right: split
            ToolbarPill {
                ToolbarPillButton(action: { splitSelected(axis: .vertical) }) {
                    Image(systemName: "rectangle.split.2x1")
                }
                ToolbarPillButton(action: { splitSelected(axis: .horizontal) }) {
                    Image(systemName: "rectangle.split.1x2")
                }
            }
            .disabled(!hasSelection)
            .opacity(hasSelection ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Center Controls

    @ViewBuilder
    private func centerControls(_ node: LayoutNode) -> some View {
        if node.type == .stack {
            ToolbarPill {
                Label("Stack", systemImage: "square.stack.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
            }
        } else {
            ToolbarPill {
                ToolbarPillButton(active: node.type == .empty, action: {
                    replaceSelectedNode(node.withType(.empty))
                }) {
                    Image(systemName: "square")
                }

                appMenu(node)
            }

            if node.type == .pinned {
                let windows = windowsForApp(node)
                if windows.count > 1 {
                    windowPicker(node, windows: windows)
                }
            }
        }
    }

    // MARK: - App Menu

    private func appMenu(_ node: LayoutNode) -> some View {
        let active = node.type == .pinned
        let appName = active ? (node.pinned?.application ?? "App") : "Pin App"
        return ToolbarPillMenu(active: active) {
            ForEach(runningApps) { app in
                Button(app.name) {
                    let pinned = PinnedConfig(application: app.name, bundleId: app.bundleId)
                    replaceSelectedNode(LayoutNode(type: .pinned, percentage: node.percentage, pinned: pinned))
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "pin.fill")
                Text(appName)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Window Picker

    private func windowsForApp(_ node: LayoutNode) -> [WTWindow] {
        guard let pinned = node.pinned else { return [] }
        return runningWindows.filter {
            $0.bundleId == pinned.bundleId || $0.application == pinned.application
        }
    }

    private func windowPicker(_ node: LayoutNode, windows: [WTWindow]) -> some View {
        let titles = Set(node.pinned?.windowTitles ?? [])
        let label = titles.isEmpty ? "All Windows" : titles.count == 1 ? titles.first! : "\(titles.count) Windows"

        return ToolbarPill {
            ToolbarPillMenu(active: false) {
                Button {
                    updateWindowTitles(node, titles: [])
                } label: {
                    Label("All Windows", systemImage: titles.isEmpty ? "checkmark" : "")
                }
                Divider()
                ForEach(windows) { w in
                    let display = w.title.isEmpty ? "Untitled" : w.title
                    let checked = titles.contains(w.title)
                    Button {
                        var updated = titles
                        if checked { updated.remove(w.title) } else { updated.insert(w.title) }
                        updateWindowTitles(node, titles: Array(updated))
                    } label: {
                        Label(display, systemImage: checked ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "macwindow")
                    Text(label)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Actions

    private func replaceSelectedNode(_ newNode: LayoutNode) {
        guard let root = rootNode,
              let updated = root.replacingNode(at: selectedPath.indices, with: newNode) else { return }
        onNodeChanged(updated)
    }

    private func deleteSelectedNode() {
        guard let node = selectedNode else { return }
        replaceSelectedNode(LayoutNode.empty(percentage: node.percentage ?? 100))
        onDeselect()
    }

    private func splitSelected(axis: SplitAxis) {
        guard let node = selectedNode else { return }
        let newNode: LayoutNode
        switch axis {
        case .vertical:
            newNode = LayoutNode.columns([node.withPercentage(50), .empty(percentage: 50)])
        case .horizontal:
            newNode = LayoutNode.rows([node.withPercentage(50), .empty(percentage: 50)])
        }
        replaceSelectedNode(newNode)
    }

    private func updateWindowTitles(_ node: LayoutNode, titles: [String]) {
        guard let pinned = node.pinned else { return }
        let updated = PinnedConfig(
            application: pinned.application,
            bundleId: pinned.bundleId,
            windowTitles: titles.isEmpty ? nil : titles
        )
        replaceSelectedNode(LayoutNode(type: .pinned, percentage: node.percentage, pinned: updated))
    }
}

// MARK: - Split Axis

enum SplitAxis {
    case vertical, horizontal
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
    LayoutCanvasView(
        rootNode: root,
        selectedPath: NodePath([0]),
        runningApps: [RunningAppInfo(name: "Xcode", bundleId: "com.apple.dt.Xcode")],
        runningWindows: [],
        thumbnailRevision: 0,
        displayAspectRatio: 16.0 / 10.0,
        onSelect: { _ in },
        onRootChanged: { _ in },
        onDragStarted: {},
        onLiveRootChange: { _ in }
    )
    .frame(width: 500, height: 300)
}

#endif
