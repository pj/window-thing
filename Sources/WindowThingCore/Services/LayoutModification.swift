import Foundation

// MARK: - LayoutModification Namespace

/// Namespace for pure layout-tree transformation helpers.
public enum LayoutModification {}

// MARK: - Layout Location

/// Represents a path to a specific node in a layout tree
/// Example: [0, 1] = first column, second row
public struct LayoutLocation: Equatable, Sendable {
    public let path: [Int]
    public let monitor: String

    public init(monitor: String, path: [Int]) {
        self.monitor = monitor
        self.path = path
    }

    public static func root(monitor: String) -> LayoutLocation {
        LayoutLocation(monitor: monitor, path: [])
    }
}

// MARK: - Node Path

/// A typed path into a layout tree, carrying its index chain and resolved context.
public struct NodePath: Equatable, Hashable, Sendable {
    /// The sequence of child indices from the root to this node.
    public let indices: [Int]

    public init(_ indices: [Int] = []) {
        self.indices = indices
    }

    /// The root path (empty indices).
    public static let root = NodePath()

    public var isRoot: Bool { indices.isEmpty }

    /// Number of levels deep (0 = root).
    public var depth: Int { indices.count }

    /// The path to this node's parent, or nil if this is root.
    public var parent: NodePath? {
        guard !indices.isEmpty else { return nil }
        return NodePath(Array(indices.dropLast()))
    }

    /// The index of this node within its parent's children.
    public var indexInParent: Int? {
        indices.last
    }

    /// Create a child path by appending an index.
    public func appending(_ index: Int) -> NodePath {
        NodePath(indices + [index])
    }

    /// Resolve the node at this path in the given root.
    public func node(in root: LayoutNode) -> LayoutNode? {
        root.nodeAt(path: indices)
    }

    /// Resolve the parent node at this path in the given root.
    public func parentNode(in root: LayoutNode) -> LayoutNode? {
        parent?.node(in: root)
    }

    /// Whether this node is a leaf (not columns/rows) in the given root.
    public func isLeaf(in root: LayoutNode) -> Bool {
        guard let n = node(in: root) else { return false }
        switch n.type {
        case .columns, .rows: return false
        default: return true
        }
    }

    /// The type of the parent container (.columns, .rows, or nil for root).
    public func parentContainerType(in root: LayoutNode) -> LayoutType? {
        parentNode(in: root)?.type
    }

    /// Number of siblings (including self) in the parent container.
    public func siblingCount(in root: LayoutNode) -> Int? {
        guard let p = parentNode(in: root) else { return nil }
        switch p.type {
        case .columns: return p.columns?.count
        case .rows: return p.rows?.count
        default: return nil
        }
    }

    /// Whether this is the only child (can't be deleted without removing parent).
    public func isOnlyChild(in root: LayoutNode) -> Bool {
        (siblingCount(in: root) ?? 0) <= 1
    }
}

// MARK: - Layout Tree Navigation and Modification

extension LayoutNode {

    /// Navigate to a node at the given path
    /// Returns nil if path is invalid
    public func nodeAt(path: [Int]) -> LayoutNode? {
        if path.isEmpty {
            return self
        }

        let index = path[0]
        let remainingPath = Array(path.dropFirst())

        switch type {
        case .columns:
            guard let columns = columns, index < columns.count else { return nil }
            return columns[index].nodeAt(path: remainingPath)

        case .rows:
            guard let rows = rows, index < rows.count else { return nil }
            return rows[index].nodeAt(path: remainingPath)

        case .floatZoomed:
            guard let baseLayout = layout?.value else { return nil }
            return baseLayout.nodeAt(path: remainingPath)

        default:
            // Leaf nodes (empty, pinned, stack) don't have children
            return remainingPath.isEmpty ? self : nil
        }
    }

    /// Replace a node at the given path with a new node
    /// Returns the modified tree, or nil if path is invalid
    public func replacingNode(at path: [Int], with newNode: LayoutNode) -> LayoutNode? {
        if path.isEmpty {
            return newNode
        }

        let index = path[0]
        let remainingPath = Array(path.dropFirst())

        switch type {
        case .columns:
            guard let columns = columns, index < columns.count else { return nil }
            var newColumns = columns
            guard let replacedChild = columns[index].replacingNode(at: remainingPath, with: newNode) else {
                return nil
            }
            newColumns[index] = replacedChild
            return LayoutNode(
                type: .columns,
                percentage: percentage,
                columns: newColumns
            )

        case .rows:
            guard let rows = rows, index < rows.count else { return nil }
            var newRows = rows
            guard let replacedChild = rows[index].replacingNode(at: remainingPath, with: newNode) else {
                return nil
            }
            newRows[index] = replacedChild
            return LayoutNode(
                type: .rows,
                percentage: percentage,
                rows: newRows
            )

        case .floatZoomed:
            guard let baseLayout = layout?.value else { return nil }
            guard let replacedLayout = baseLayout.replacingNode(at: remainingPath, with: newNode) else {
                return nil
            }
            return LayoutNode(
                type: .floatZoomed,
                percentage: percentage,
                layout: replacedLayout,
                floats: floats,
                zoomed: zoomed
            )

        default:
            return nil
        }
    }

    // MARK: - Leaf Index

    /// Count the total number of leaf nodes in this subtree.
    public var leafCount: Int {
        switch type {
        case .columns:
            return (columns ?? []).reduce(0) { $0 + $1.leafCount }
        case .rows:
            return (rows ?? []).reduce(0) { $0 + $1.leafCount }
        default:
            return 1
        }
    }

    /// Return the 1-based leaf index for the leaf at `path`, using depth-first ordering.
    /// Returns nil if the path doesn't point to a leaf.
    public func leafIndex(at path: NodePath) -> Int? {
        leafIndexHelper(indices: path.indices[...], offset: 0)
    }

    private func leafIndexHelper(indices: ArraySlice<Int>, offset: Int) -> Int? {
        if indices.isEmpty {
            // We're at the target node; it must be a leaf
            switch type {
            case .columns, .rows: return nil
            default: return offset + 1  // 1-based
            }
        }
        guard let childIdx = indices.first else { return nil }
        let children: [LayoutNode]
        switch type {
        case .columns: children = columns ?? []
        case .rows: children = rows ?? []
        default: return nil  // path goes deeper but this is a leaf
        }
        guard childIdx < children.count else { return nil }
        // Count leaves in all preceding siblings
        var precedingLeaves = 0
        for i in 0..<childIdx {
            precedingLeaves += children[i].leafCount
        }
        return children[childIdx].leafIndexHelper(
            indices: indices.dropFirst(),
            offset: offset + precedingLeaves
        )
    }

    // MARK: - Convenience Mutation Helpers (used by the layout editor)

    /// Return a copy of this node with a new percentage
    public func withPercentage(_ pct: Double) -> LayoutNode {
        LayoutNode(
            type: type, percentage: pct, pinned: pinned,
            columns: columns, rows: rows, windows: windows,
            stackRemaining: stackRemaining, layout: layout?.value,
            floats: floats, zoomed: zoomed
        )
    }

    /// Return a copy as a `.columns` node with the given children, preserving percentage
    public func withColumns(_ cols: [LayoutNode]) -> LayoutNode {
        LayoutNode(type: .columns, percentage: percentage, columns: cols)
    }

    /// Return a copy as a `.rows` node with the given children, preserving percentage
    public func withRows(_ rs: [LayoutNode]) -> LayoutNode {
        LayoutNode(type: .rows, percentage: percentage, rows: rs)
    }

    /// Return a copy converted to a different type, preserving percentage.
    /// Structural children (columns/rows) and type-specific data are cleared except
    /// for `pinned` (kept when converting to `.pinned`) and `stackRemaining`
    /// (kept when converting to `.stack`).
    public func withType(_ newType: LayoutType) -> LayoutNode {
        LayoutNode(
            type: newType,
            percentage: percentage,
            pinned: newType == .pinned ? pinned : nil,
            stackRemaining: newType == .stack ? stackRemaining : nil
        )
    }

    /// Insert a new column at the specified index
    public func insertingColumn(_ newNode: LayoutNode, at index: Int) -> LayoutNode? {
        guard type == .columns, let columns = columns else { return nil }
        guard index >= 0 && index <= columns.count else { return nil }

        var newColumns = columns
        newColumns.insert(newNode, at: index)

        return LayoutNode(
            type: .columns,
            percentage: percentage,
            columns: newColumns
        )
    }

    /// Insert a new row at the specified index
    public func insertingRow(_ newNode: LayoutNode, at index: Int) -> LayoutNode? {
        guard type == .rows, let rows = rows else { return nil }
        guard index >= 0 && index <= rows.count else { return nil }

        var newRows = rows
        newRows.insert(newNode, at: index)

        return LayoutNode(
            type: .rows,
            percentage: percentage,
            rows: newRows
        )
    }

    /// Remove a column at the specified index
    public func removingColumn(at index: Int) -> LayoutNode? {
        guard type == .columns, let columns = columns else { return nil }
        guard index >= 0 && index < columns.count else { return nil }
        guard columns.count > 1 else { return nil }  // Don't allow removing the last column

        var newColumns = columns
        let removedColumn = newColumns.remove(at: index)

        // Check if we removed the stack
        let hadStack = removedColumn.findStackLocation() != nil

        var result = LayoutNode(
            type: .columns,
            percentage: percentage,
            columns: newColumns
        )

        // If we removed the stack, ensure there's still one
        if hadStack && result.findStackLocation() == nil {
            // Convert the first empty cell to a stack, or ensure stack exists
            if let firstEmptyIndex = newColumns.firstIndex(where: { $0.type == .empty }) {
                var updatedColumns = newColumns
                updatedColumns[firstEmptyIndex] = LayoutNode(
                    type: .stack,
                    percentage: updatedColumns[firstEmptyIndex].percentage
                )
                result = LayoutNode(
                    type: .columns,
                    percentage: percentage,
                    columns: updatedColumns
                )
            } else {
                // No empty cells, ensure stack exists by wrapping or converting
                result = result.ensuringStack()
            }
        }

        return result
    }

    /// Remove a row at the specified index
    public func removingRow(at index: Int) -> LayoutNode? {
        guard type == .rows, let rows = rows else { return nil }
        guard index >= 0 && index < rows.count else { return nil }
        guard rows.count > 1 else { return nil }  // Don't allow removing the last row

        var newRows = rows
        let removedRow = newRows.remove(at: index)

        // Check if we removed the stack
        let hadStack = removedRow.findStackLocation() != nil

        var result = LayoutNode(
            type: .rows,
            percentage: percentage,
            rows: newRows
        )

        // If we removed the stack, ensure there's still one
        if hadStack && result.findStackLocation() == nil {
            // Convert the first empty cell to a stack, or ensure stack exists
            if let firstEmptyIndex = newRows.firstIndex(where: { $0.type == .empty }) {
                var updatedRows = newRows
                updatedRows[firstEmptyIndex] = LayoutNode(
                    type: .stack,
                    percentage: updatedRows[firstEmptyIndex].percentage
                )
                result = LayoutNode(
                    type: .rows,
                    percentage: percentage,
                    rows: updatedRows
                )
            } else {
                // No empty cells, ensure stack exists by wrapping or converting
                result = result.ensuringStack()
            }
        }

        return result
    }

    /// Find the location of the stack node in the tree
    public func findStackLocation(currentPath: [Int] = []) -> [Int]? {
        switch type {
        case .stack:
            return currentPath

        case .columns:
            guard let columns = columns else { return nil }
            for (index, column) in columns.enumerated() {
                if let stackPath = column.findStackLocation(currentPath: currentPath + [index]) {
                    return stackPath
                }
            }
            return nil

        case .rows:
            guard let rows = rows else { return nil }
            for (index, row) in rows.enumerated() {
                if let stackPath = row.findStackLocation(currentPath: currentPath + [index]) {
                    return stackPath
                }
            }
            return nil

        case .floatZoomed:
            guard let baseLayout = layout?.value else { return nil }
            return baseLayout.findStackLocation(currentPath: currentPath)

        default:
            return nil
        }
    }

    /// Ensure layout has a stack node, adding one if necessary
    public func ensuringStack() -> LayoutNode {
        if findStackLocation() != nil {
            return self
        }

        // No stack found - convert the entire layout to columns with original + stack
        return LayoutNode.columns([
            self,
            LayoutNode(type: .stack, percentage: 30)
        ])
    }
}

// MARK: - Layout Modification Result

public struct LayoutModificationResult {
    public let layout: Layout
    public let changed: Bool

    public init(layout: Layout, changed: Bool) {
        self.layout = layout
        self.changed = changed
    }
}

// MARK: - Layout Manager Extensions for Dynamic Modification

extension LayoutManager {

    // MARK: - Moving Applications and Windows

    /// Move an application or specific window from one location to another
    /// If windowTitle is nil, moves all windows of the application
    /// Returns true if the layout was modified
    @discardableResult
    public func moveTo(
        monitor: String,
        applicationName: String,
        windowTitle: String?,
        to toLocation: [Int]
    ) -> Bool {
        guard let layout = currentLayout else { return false }

        let result = layout.movingApplication(
            monitor: monitor,
            applicationName: applicationName,
            windowTitle: windowTitle,
            to: toLocation
        )

        if result.changed {
            currentLayout = result.layout
            applyLayout(result.layout)
        }

        return result.changed
    }

    /// Move application/window from one location to another (full specification)
    @discardableResult
    public func moveTo(
        from fromLocation: LayoutLocation,
        to toLocation: LayoutLocation,
        applicationName: String,
        windowTitle: String?
    ) -> Bool {
        guard let layout = currentLayout else { return false }

        let result = layout.movingApplication(
            from: fromLocation,
            to: toLocation,
            applicationName: applicationName,
            windowTitle: windowTitle
        )

        if result.changed {
            currentLayout = result.layout
            applyLayout(result.layout)
        }

        return result.changed
    }

    /// Remove a pinned window from a location (moves it back to stack)
    @discardableResult
    public func removeFrom(monitor: String, location: [Int]) -> Bool {
        guard let layout = currentLayout else { return false }

        let result = layout.removingPinnedAt(monitor: monitor, location: location)

        if result.changed {
            currentLayout = result.layout
            applyLayout(result.layout)
        }

        return result.changed
    }

    // MARK: - Layout Structure Modification

    /// Insert a new column at the specified location
    @discardableResult
    public func insertColumn(
        monitor: String,
        at location: [Int],
        index: Int,
        node: LayoutNode
    ) -> Bool {
        guard let layout = currentLayout else { return false }

        let result = layout.insertingColumn(
            monitor: monitor,
            at: location,
            index: index,
            node: node
        )

        if result.changed {
            currentLayout = result.layout
            applyLayout(result.layout)
        }

        return result.changed
    }

    /// Insert a new row at the specified location
    @discardableResult
    public func insertRow(
        monitor: String,
        at location: [Int],
        index: Int,
        node: LayoutNode
    ) -> Bool {
        guard let layout = currentLayout else { return false }

        let result = layout.insertingRow(
            monitor: monitor,
            at: location,
            index: index,
            node: node
        )

        if result.changed {
            currentLayout = result.layout
            applyLayout(result.layout)
        }

        return result.changed
    }

    /// Remove a column at the specified location
    @discardableResult
    public func removeColumn(monitor: String, at location: [Int], index: Int) -> Bool {
        guard let layout = currentLayout else { return false }

        let result = layout.removingColumn(monitor: monitor, at: location, index: index)

        if result.changed {
            currentLayout = result.layout
            applyLayout(result.layout)
        }

        return result.changed
    }

    /// Remove a row at the specified location
    @discardableResult
    public func removeRow(monitor: String, at location: [Int], index: Int) -> Bool {
        guard let layout = currentLayout else { return false }

        let result = layout.removingRow(monitor: monitor, at: location, index: index)

        if result.changed {
            currentLayout = result.layout
            applyLayout(result.layout)
        }

        return result.changed
    }
}

// MARK: - Layout Extensions for Modification

extension Layout {

    /// Move an application from its current location to a new location
    func movingApplication(
        monitor: String,
        applicationName: String,
        windowTitle: String?,
        to toPath: [Int]
    ) -> LayoutModificationResult {
        let screenSet = screens

        guard var monitorLayout = screenSet.layouts[monitor] else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        // Ensure stack exists
        monitorLayout = monitorLayout.ensuringStack()

        // Try to remove the application from its current location
        // If not removed (it's in the stack), just use the original layout
        let (layoutAfterRemoval, wasRemoved) = monitorLayout.removingApplication(
            applicationName: applicationName,
            windowTitle: windowTitle
        )

        let baseLayout = wasRemoved ? layoutAfterRemoval : monitorLayout

        // Add the application to the new location
        guard let layoutAfterMove = baseLayout.addingApplication(
            at: toPath,
            applicationName: applicationName,
            windowTitle: windowTitle
        ) else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        // Update screen set
        var newLayouts = screenSet.layouts
        newLayouts[monitor] = layoutAfterMove
        let newScreenSet = ScreenConfig(layouts: newLayouts)

        let newLayout = Layout(
            name: name,
            quickKey: quickKey,
            screens: newScreenSet
        )

        return LayoutModificationResult(layout: newLayout, changed: true)
    }

    /// Move application from one location to another (with full location specs)
    func movingApplication(
        from: LayoutLocation,
        to: LayoutLocation,
        applicationName: String,
        windowTitle: String?
    ) -> LayoutModificationResult {
        // For now, require same monitor
        guard from.monitor == to.monitor else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        return movingApplication(
            monitor: from.monitor,
            applicationName: applicationName,
            windowTitle: windowTitle,
            to: to.path
        )
    }

    /// Remove a pinned window from a location
    func removingPinnedAt(monitor: String, location: [Int]) -> LayoutModificationResult {
        let screenSet = screens

        guard let monitorLayout = screenSet.layouts[monitor] else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        // Replace the node at location with empty
        guard let newLayout = monitorLayout.replacingNode(at: location, with: .empty()) else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        var newLayouts = screenSet.layouts
        newLayouts[monitor] = newLayout
        let newScreenSet = ScreenConfig(layouts: newLayouts)

        let updatedLayout = Layout(
            name: name,
            quickKey: quickKey,
            screens: newScreenSet
        )

        return LayoutModificationResult(layout: updatedLayout, changed: true)
    }

    /// Insert a column
    func insertingColumn(
        monitor: String,
        at location: [Int],
        index: Int,
        node: LayoutNode
    ) -> LayoutModificationResult {
        let screenSet = screens

        guard let monitorLayout = screenSet.layouts[monitor] else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        guard let parentNode = monitorLayout.nodeAt(path: location),
              let newParent = parentNode.insertingColumn(node, at: index),
              let newLayout = monitorLayout.replacingNode(at: location, with: newParent) else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        var newLayouts = screenSet.layouts
        newLayouts[monitor] = newLayout
        let newScreenSet = ScreenConfig(layouts: newLayouts)

        let updatedLayout = Layout(
            name: name,
            quickKey: quickKey,
            screens: newScreenSet
        )

        return LayoutModificationResult(layout: updatedLayout, changed: true)
    }

    /// Insert a row
    func insertingRow(
        monitor: String,
        at location: [Int],
        index: Int,
        node: LayoutNode
    ) -> LayoutModificationResult {
        let screenSet = screens

        guard let monitorLayout = screenSet.layouts[monitor] else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        guard let parentNode = monitorLayout.nodeAt(path: location),
              let newParent = parentNode.insertingRow(node, at: index),
              let newLayout = monitorLayout.replacingNode(at: location, with: newParent) else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        var newLayouts = screenSet.layouts
        newLayouts[monitor] = newLayout
        let newScreenSet = ScreenConfig(layouts: newLayouts)

        let updatedLayout = Layout(
            name: name,
            quickKey: quickKey,
            screens: newScreenSet
        )

        return LayoutModificationResult(layout: updatedLayout, changed: true)
    }

    /// Remove a column
    func removingColumn(
        monitor: String,
        at location: [Int],
        index: Int
    ) -> LayoutModificationResult {
        let screenSet = screens

        guard let monitorLayout = screenSet.layouts[monitor] else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        guard let parentNode = monitorLayout.nodeAt(path: location),
              let newParent = parentNode.removingColumn(at: index),
              let newLayout = monitorLayout.replacingNode(at: location, with: newParent) else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        var newLayouts = screenSet.layouts
        newLayouts[monitor] = newLayout
        let newScreenSet = ScreenConfig(layouts: newLayouts)

        let updatedLayout = Layout(
            name: name,
            quickKey: quickKey,
            screens: newScreenSet
        )

        return LayoutModificationResult(layout: updatedLayout, changed: true)
    }

    /// Remove a row
    func removingRow(
        monitor: String,
        at location: [Int],
        index: Int
    ) -> LayoutModificationResult {
        let screenSet = screens

        guard let monitorLayout = screenSet.layouts[monitor] else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        guard let parentNode = monitorLayout.nodeAt(path: location),
              let newParent = parentNode.removingRow(at: index),
              let newLayout = monitorLayout.replacingNode(at: location, with: newParent) else {
            return LayoutModificationResult(layout: self, changed: false)
        }

        var newLayouts = screenSet.layouts
        newLayouts[monitor] = newLayout
        let newScreenSet = ScreenConfig(layouts: newLayouts)

        let updatedLayout = Layout(
            name: name,
            quickKey: quickKey,
            screens: newScreenSet
        )

        return LayoutModificationResult(layout: updatedLayout, changed: true)
    }
}

// MARK: - Helper Methods for Application Removal and Addition

extension LayoutNode {

    /// Remove an application from the tree, converting pinned nodes to empty
    /// Returns (modified tree, was removed)
    func removingApplication(
        applicationName: String,
        windowTitle: String?
    ) -> (LayoutNode, Bool) {
        switch type {
        case .pinned:
            guard let pinned = pinned else { return (self, false) }

            // Check if this pinned node matches
            let appMatches = pinned.application == applicationName
            let titleMatches = windowTitle == nil || pinned.windowTitles == nil || pinned.windowTitles?.contains(windowTitle!) == true

            if appMatches && titleMatches {
                // Convert to empty
                return (.empty(percentage: percentage ?? 100), true)
            }
            return (self, false)

        case .columns:
            guard let columns = columns else { return (self, false) }
            var newColumns: [LayoutNode] = []
            var wasRemoved = false

            for column in columns {
                let (newColumn, removed) = column.removingApplication(
                    applicationName: applicationName,
                    windowTitle: windowTitle
                )
                newColumns.append(newColumn)
                wasRemoved = wasRemoved || removed
            }

            if wasRemoved {
                return (LayoutNode(type: .columns, percentage: percentage, columns: newColumns), true)
            }
            return (self, false)

        case .rows:
            guard let rows = rows else { return (self, false) }
            var newRows: [LayoutNode] = []
            var wasRemoved = false

            for row in rows {
                let (newRow, removed) = row.removingApplication(
                    applicationName: applicationName,
                    windowTitle: windowTitle
                )
                newRows.append(newRow)
                wasRemoved = wasRemoved || removed
            }

            if wasRemoved {
                return (LayoutNode(type: .rows, percentage: percentage, rows: newRows), true)
            }
            return (self, false)

        case .floatZoomed:
            guard let baseLayout = layout?.value else { return (self, false) }
            let (newLayout, removed) = baseLayout.removingApplication(
                applicationName: applicationName,
                windowTitle: windowTitle
            )

            if removed {
                return (LayoutNode(
                    type: .floatZoomed,
                    percentage: percentage,
                    layout: newLayout,
                    floats: floats,
                    zoomed: zoomed
                ), true)
            }
            return (self, false)

        default:
            return (self, false)
        }
    }

    /// Add an application at the specified path
    /// Converts empty nodes to pinned, replaces existing pinned
    func addingApplication(
        at path: [Int],
        applicationName: String,
        windowTitle: String?
    ) -> LayoutNode? {
        if path.isEmpty {
            // Convert this node to pinned
            return .pinned(
                app: applicationName,
                bundleId: nil,
                windowTitles: windowTitle.map { [$0] },
                percentage: percentage ?? 100
            )
        }

        let index = path[0]
        let remainingPath = Array(path.dropFirst())

        switch type {
        case .columns:
            guard let columns = columns, index < columns.count else { return nil }
            var newColumns = columns
            guard let newChild = columns[index].addingApplication(
                at: remainingPath,
                applicationName: applicationName,
                windowTitle: windowTitle
            ) else {
                return nil
            }
            newColumns[index] = newChild
            return LayoutNode(type: .columns, percentage: percentage, columns: newColumns)

        case .rows:
            guard let rows = rows, index < rows.count else { return nil }
            var newRows = rows
            guard let newChild = rows[index].addingApplication(
                at: remainingPath,
                applicationName: applicationName,
                windowTitle: windowTitle
            ) else {
                return nil
            }
            newRows[index] = newChild
            return LayoutNode(type: .rows, percentage: percentage, rows: newRows)

        case .floatZoomed:
            guard let baseLayout = layout?.value else { return nil }
            guard let newLayout = baseLayout.addingApplication(
                at: remainingPath,
                applicationName: applicationName,
                windowTitle: windowTitle
            ) else {
                return nil
            }
            return LayoutNode(
                type: .floatZoomed,
                percentage: percentage,
                layout: newLayout,
                floats: floats,
                zoomed: zoomed
            )

        default:
            return nil
        }
    }
}

// MARK: - Ghost Cell Helpers

extension LayoutModification {

    /// Append a new trailing column to `node`.
    /// - If node is `.columns`: appends `newNode` as the last column.
    /// - If node is a leaf: wraps both in `.columns([node, newNode])`.
    /// The existing columns are redistributed to equal percentages; `newNode` gets `newPercentage`.
    public static func appendTrailingColumn(
        to node: LayoutNode,
        newNode: LayoutNode = .stackAll()
    ) -> LayoutNode {
        switch node.type {
        case .columns:
            let existing = node.columns ?? []
            let count = Double(existing.count + 1)
            let equalPct = 100.0 / count
            var rebalanced = existing.map { col in
                LayoutNode(
                    type: col.type,
                    percentage: equalPct,
                    pinned: col.pinned,
                    columns: col.columns,
                    rows: col.rows,
                    windows: col.windows,
                    stackRemaining: col.stackRemaining,
                    layout: col.layout?.value,
                    floats: col.floats,
                    zoomed: col.zoomed
                )
            }
            rebalanced.append(LayoutNode(
                type: newNode.type,
                percentage: equalPct,
                pinned: newNode.pinned,
                columns: newNode.columns,
                rows: newNode.rows,
                windows: newNode.windows,
                stackRemaining: newNode.stackRemaining,
                layout: newNode.layout?.value,
                floats: newNode.floats,
                zoomed: newNode.zoomed
            ))
            return LayoutNode(type: .columns, percentage: node.percentage, columns: rebalanced)

        default:
            // Leaf or rows node: wrap in a 2-column layout
            let pct = 50.0
            let left = LayoutNode(
                type: node.type,
                percentage: pct,
                pinned: node.pinned,
                columns: node.columns,
                rows: node.rows,
                windows: node.windows,
                stackRemaining: node.stackRemaining,
                layout: node.layout?.value,
                floats: node.floats,
                zoomed: node.zoomed
            )
            let right = LayoutNode(
                type: newNode.type,
                percentage: pct,
                pinned: newNode.pinned,
                columns: newNode.columns,
                rows: newNode.rows,
                windows: newNode.windows,
                stackRemaining: newNode.stackRemaining,
                layout: newNode.layout?.value,
                floats: newNode.floats,
                zoomed: newNode.zoomed
            )
            return LayoutNode(type: .columns, percentage: node.percentage, columns: [left, right])
        }
    }

    /// Append a new trailing row to `node`.
    /// - If node is `.rows`: appends `newNode` as the last row.
    /// - If node is a leaf: wraps both in `.rows([node, newNode])`.
    public static func appendTrailingRow(
        to node: LayoutNode,
        newNode: LayoutNode = .stackAll()
    ) -> LayoutNode {
        switch node.type {
        case .rows:
            let existing = node.rows ?? []
            let count = Double(existing.count + 1)
            let equalPct = 100.0 / count
            var rebalanced = existing.map { row in
                LayoutNode(
                    type: row.type,
                    percentage: equalPct,
                    pinned: row.pinned,
                    columns: row.columns,
                    rows: row.rows,
                    windows: row.windows,
                    stackRemaining: row.stackRemaining,
                    layout: row.layout?.value,
                    floats: row.floats,
                    zoomed: row.zoomed
                )
            }
            rebalanced.append(LayoutNode(
                type: newNode.type,
                percentage: equalPct,
                pinned: newNode.pinned,
                columns: newNode.columns,
                rows: newNode.rows,
                windows: newNode.windows,
                stackRemaining: newNode.stackRemaining,
                layout: newNode.layout?.value,
                floats: newNode.floats,
                zoomed: newNode.zoomed
            ))
            return LayoutNode(type: .rows, percentage: node.percentage, rows: rebalanced)

        default:
            // Leaf or columns node: wrap in a 2-row layout
            let pct = 50.0
            let top = LayoutNode(
                type: node.type,
                percentage: pct,
                pinned: node.pinned,
                columns: node.columns,
                rows: node.rows,
                windows: node.windows,
                stackRemaining: node.stackRemaining,
                layout: node.layout?.value,
                floats: node.floats,
                zoomed: node.zoomed
            )
            let bottom = LayoutNode(
                type: newNode.type,
                percentage: pct,
                pinned: newNode.pinned,
                columns: newNode.columns,
                rows: newNode.rows,
                windows: newNode.windows,
                stackRemaining: newNode.stackRemaining,
                layout: newNode.layout?.value,
                floats: newNode.floats,
                zoomed: newNode.zoomed
            )
            return LayoutNode(type: .rows, percentage: node.percentage, rows: [top, bottom])
        }
    }

    /// Returns `true` if a new trailing column can be added without any resulting column
    /// falling below `minPercentage` of the display width.
    public static func canAppendColumn(to node: LayoutNode, minPercentage: Double = 15.0) -> Bool {
        let newCount: Int
        switch node.type {
        case .columns:
            newCount = (node.columns?.count ?? 0) + 1
        default:
            newCount = 2
        }
        return (100.0 / Double(newCount)) >= minPercentage
    }

    /// Returns `true` if a new trailing row can be added without any resulting row
    /// falling below `minPercentage` of the display height.
    public static func canAppendRow(to node: LayoutNode, minPercentage: Double = 15.0) -> Bool {
        let newCount: Int
        switch node.type {
        case .rows:
            newCount = (node.rows?.count ?? 0) + 1
        default:
            newCount = 2
        }
        return (100.0 / Double(newCount)) >= minPercentage
    }
}

// MARK: - Normalisation

public extension LayoutNode {
    /// Collapses structure that has no effect on what the layout draws.
    ///
    /// Editing leaves debris. Splitting a pane wraps it in a container; deleting
    /// its sibling can leave that container holding a single child, and repeated
    /// rounds nest those containers inside each other. The result renders
    /// identically — a container with one child fills its own rect, so the child
    /// occupies exactly the space the container did — but the tree carries
    /// layers that do nothing, and code walking it has to cope with them. The
    /// menubar's icon renderer did not, and drew such layouts as an empty
    /// screen.
    ///
    /// Two rules, applied depth first:
    ///
    /// - a container holding one child becomes that child, which inherits the
    ///   container's percentage — the child now sits where the container sat,
    ///   so it must claim the same share of the parent;
    /// - a container holding nothing becomes an empty pane, keeping its share.
    ///
    /// Both preserve geometry exactly, which is the point: this tidies the tree
    /// without moving a single divider.
    ///
    /// Deliberately *not* done here: flattening a container into a parent of the
    /// same axis. `columns[a, columns[b, c]]` could become `columns[a, b, c]`
    /// with the percentages scaled, and would still draw the same — but it is
    /// not the same layout to edit. Dragging the divider between `b` and `c`
    /// currently resizes them within their own container and leaves `a` alone;
    /// flattened, every divider resizes against every sibling. That is a change
    /// to behaviour, not a tidy-up.
    func normalized() -> LayoutNode {
        switch type {
        case .columns:
            return normalizedContainer(children: columns ?? [], rebuild: withColumns)
        case .rows:
            return normalizedContainer(children: rows ?? [], rebuild: withRows)
        case .pinned, .stack, .empty, .floatZoomed:
            return self
        }
    }

    private func normalizedContainer(
        children: [LayoutNode],
        rebuild: ([LayoutNode]) -> LayoutNode
    ) -> LayoutNode {
        let tidied = children.map { $0.normalized() }

        guard let only = tidied.first else {
            return .empty(percentage: percentage ?? 100)
        }
        if tidied.count == 1 {
            return only.withPercentage(percentage ?? only.percentage ?? 100)
        }
        return rebuild(tidied)
    }
}

public extension ScreenConfig {
    func normalized() -> ScreenConfig {
        var copy = self
        copy.layouts = layouts.mapValues { $0.normalized() }
        return copy
    }
}

public extension Layout {
    func normalized() -> Layout {
        var copy = self
        copy.screens = screens.normalized()
        return copy
    }
}
