import Foundation

// MARK: - Value Types

/// A leaf cell in the active layout with its global address and screen geometry.
public struct IndexedCell: Equatable, Sendable {
    public let address: CellAddress
    /// Pixel bounds of this cell on its display.
    public let frame: WindowFrame
    /// Which monitor this cell lives on.
    public let displayName: String

    public init(address: CellAddress, frame: WindowFrame, displayName: String) {
        self.address = address
        self.frame = frame
        self.displayName = displayName
    }
}

/// Describes where a new region can be appended to the layout tree.
public struct GhostCellPosition: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case trailingColumn   // append a column to the right
        case trailingRow      // append a row below
    }

    public let displayName: String
    public let direction: Direction
    /// Approximate pixel bounds for rendering the ghost tile.
    public let estimatedFrame: WindowFrame
    /// True when adding this cell would violate the minimum cell size (15%).
    public let isDisabled: Bool

    public init(displayName: String, direction: Direction, estimatedFrame: WindowFrame, isDisabled: Bool) {
        self.displayName = displayName
        self.direction = direction
        self.estimatedFrame = estimatedFrame
        self.isDisabled = isDisabled
    }
}

// MARK: - CellIndexer

/// Pure, stateless utility for enumerating leaf cells in a layout across displays.
///
/// Cell ordering: displays sorted ascending by x-origin; within each display,
/// depth-first traversal of the matched LayoutNode tree (left-to-right for columns,
/// top-to-bottom for rows). Indices are globally sequential: 1, 2, 3 … 35, a, b … z.
public enum CellIndexer {

    // MARK: - Public API

    /// Enumerate all leaf cells in the layout for the current display configuration.
    /// Returns one `IndexedCell` per leaf node, in global index order.
    public static func indexCells(layout: Layout, displays: [Display]) -> [IndexedCell] {
        let screenSet = layout.screens.resolved(for: displays)
        let orderedDisplays = displays.sorted { $0.frame.x < $1.frame.x }
        var cells: [IndexedCell] = []
        for display in orderedDisplays {
            let key = screenSet.layouts.keys.first { $0 == display.name } ?? ScreenConfig.primaryKey
            guard let node = screenSet.layouts[key] ?? screenSet.layouts[ScreenConfig.primaryKey] else {
                continue
            }
            let displayCells = leafFrames(node: node, displayFrame: display.frame)
            for frame in displayCells {
                let index = cells.count + 1
                cells.append(IndexedCell(
                    address: CellAddress.from(index: index) ?? .numeric(index),
                    frame: frame,
                    displayName: display.name
                ))
            }
        }
        return cells
    }

    /// Return ghost cell positions available for layout extension.
    public static func ghostPositions(layout: Layout, displays: [Display]) -> [GhostCellPosition] {
        let screenSet = layout.screens.resolved(for: displays)
        let orderedDisplays = displays.sorted { $0.frame.x < $1.frame.x }
        var ghosts: [GhostCellPosition] = []
        let minPct = 15.0

        for display in orderedDisplays {
            let key = screenSet.layouts.keys.first { $0 == display.name } ?? ScreenConfig.primaryKey
            guard let node = screenSet.layouts[key] ?? screenSet.layouts[ScreenConfig.primaryKey] else { continue }

            // Trailing column ghost
            let colDisabled = !LayoutModification.canAppendColumn(to: node, minPercentage: minPct)
            let colFrame = trailingColumnFrame(node: node, displayFrame: display.frame)
            ghosts.append(GhostCellPosition(
                displayName: display.name,
                direction: .trailingColumn,
                estimatedFrame: colFrame,
                isDisabled: colDisabled
            ))

            // Trailing row ghost
            let rowDisabled = !LayoutModification.canAppendRow(to: node, minPercentage: minPct)
            let rowFrame = trailingRowFrame(node: node, displayFrame: display.frame)
            ghosts.append(GhostCellPosition(
                displayName: display.name,
                direction: .trailingRow,
                estimatedFrame: rowFrame,
                isDisabled: rowDisabled
            ))
        }
        return ghosts
    }

    /// Convert a 1-based sequential index to a CellAddress.
    public static func address(forIndex index: Int) -> CellAddress? {
        CellAddress.from(index: index)
    }

    // MARK: - Sub-Cell Indexing

    /// A leaf cell within a parent cell's sublayout.
    public struct SubIndexedCell: Equatable, Sendable {
        public let address: SubCellAddress
        /// Pixel bounds of this sub-cell (absolute screen coordinates).
        public let frame: WindowFrame
        public let parentAddress: CellAddress

        public init(address: SubCellAddress, frame: WindowFrame, parentAddress: CellAddress) {
            self.address = address
            self.frame = frame
            self.parentAddress = parentAddress
        }
    }

    /// Unified lookup structure for both top-level cells and sub-cells.
    public struct CellMap: Sendable {
        public let cells: [IndexedCell]
        public let subCells: [SubIndexedCell]

        public init(cells: [IndexedCell], subCells: [SubIndexedCell]) {
            self.cells = cells
            self.subCells = subCells
        }

        /// Look up a top-level cell by address.
        public func cell(at address: CellAddress) -> IndexedCell? {
            cells.first { $0.address == address }
        }

        /// Look up a sub-cell by address.
        public func subCell(at address: SubCellAddress) -> SubIndexedCell? {
            subCells.first { $0.address == address }
        }

        /// Whether a parent cell has sub-cells.
        public func hasSubCells(at address: CellAddress) -> Bool {
            subCells.contains { $0.parentAddress == address }
        }
    }

    /// Enumerate sub-cells within a parent cell that has a sublayout.
    public static func indexSubCells(
        parentAddress: CellAddress,
        sublayout: LayoutNode,
        parentFrame: WindowFrame
    ) -> [SubIndexedCell] {
        let frames = leafFrames(node: sublayout, displayFrame: parentFrame)
        return frames.enumerated().map { i, frame in
            SubIndexedCell(
                address: SubCellAddress(parent: parentAddress, subIndex: i + 1),
                frame: frame,
                parentAddress: parentAddress
            )
        }
    }

    /// Index all cells including sub-cells for pinned nodes that have sublayouts.
    public static func indexAllCells(layout: Layout, displays: [Display]) -> CellMap {
        let cells = indexCells(layout: layout, displays: displays)
        var subCells: [SubIndexedCell] = []

        let screenSet = layout.screens.resolved(for: displays)

        // For each cell, check if its corresponding node has a sublayout
        let orderedDisplays = displays.sorted { $0.frame.x < $1.frame.x }
        var cellIndex = 0
        for display in orderedDisplays {
            let key = screenSet.layouts.keys.first { $0 == display.name } ?? ScreenConfig.primaryKey
            guard let node = screenSet.layouts[key] ?? screenSet.layouts[ScreenConfig.primaryKey] else {
                continue
            }
            let leafNodes = leafNodesWithFrames(node: node, displayFrame: display.frame)
            for (leafNode, frame) in leafNodes {
                guard cellIndex < cells.count else { break }
                let parentAddress = cells[cellIndex].address
                if leafNode.type == .pinned,
                   let sublayoutConfig = leafNode.pinned?.sublayout {
                    let subs = indexSubCells(
                        parentAddress: parentAddress,
                        sublayout: sublayoutConfig.layoutNode,
                        parentFrame: frame
                    )
                    subCells.append(contentsOf: subs)
                }
                cellIndex += 1
            }
        }

        return CellMap(cells: cells, subCells: subCells)
    }

    // MARK: - Internal helpers

    /// Recursively enumerate leaf frames for a node within a display frame.
    internal static func leafFrames(node: LayoutNode, displayFrame: WindowFrame) -> [WindowFrame] {
        switch node.type {
        case .columns:
            guard let cols = node.columns, !cols.isEmpty else {
                return [displayFrame]
            }
            let total = cols.reduce(0.0) { $0 + ($1.percentage ?? (100.0 / Double(cols.count))) }
            var x = displayFrame.x
            var frames: [WindowFrame] = []
            for col in cols {
                let pct = col.percentage ?? (100.0 / Double(cols.count))
                let w = displayFrame.width * (pct / total)
                let childFrame = WindowFrame(x: x, y: displayFrame.y, width: w, height: displayFrame.height)
                frames.append(contentsOf: leafFrames(node: col, displayFrame: childFrame))
                x += w
            }
            return frames

        case .rows:
            guard let rows = node.rows, !rows.isEmpty else {
                return [displayFrame]
            }
            let total = rows.reduce(0.0) { $0 + ($1.percentage ?? (100.0 / Double(rows.count))) }
            var y = displayFrame.y
            var frames: [WindowFrame] = []
            for row in rows {
                let pct = row.percentage ?? (100.0 / Double(rows.count))
                let h = displayFrame.height * (pct / total)
                let childFrame = WindowFrame(x: displayFrame.x, y: y, width: displayFrame.width, height: h)
                frames.append(contentsOf: leafFrames(node: row, displayFrame: childFrame))
                y += h
            }
            return frames

        default:
            // leaf node (stack, pinned, empty, floatZoomed)
            return [displayFrame]
        }
    }

    /// Recursively enumerate leaf nodes paired with their frames.
    private static func leafNodesWithFrames(node: LayoutNode, displayFrame: WindowFrame) -> [(LayoutNode, WindowFrame)] {
        switch node.type {
        case .columns:
            guard let cols = node.columns, !cols.isEmpty else {
                return [(node, displayFrame)]
            }
            let total = cols.reduce(0.0) { $0 + ($1.percentage ?? (100.0 / Double(cols.count))) }
            var x = displayFrame.x
            var result: [(LayoutNode, WindowFrame)] = []
            for col in cols {
                let pct = col.percentage ?? (100.0 / Double(cols.count))
                let w = displayFrame.width * (pct / total)
                let childFrame = WindowFrame(x: x, y: displayFrame.y, width: w, height: displayFrame.height)
                result.append(contentsOf: leafNodesWithFrames(node: col, displayFrame: childFrame))
                x += w
            }
            return result

        case .rows:
            guard let rows = node.rows, !rows.isEmpty else {
                return [(node, displayFrame)]
            }
            let total = rows.reduce(0.0) { $0 + ($1.percentage ?? (100.0 / Double(rows.count))) }
            var y = displayFrame.y
            var result: [(LayoutNode, WindowFrame)] = []
            for row in rows {
                let pct = row.percentage ?? (100.0 / Double(rows.count))
                let h = displayFrame.height * (pct / total)
                let childFrame = WindowFrame(x: displayFrame.x, y: y, width: displayFrame.width, height: h)
                result.append(contentsOf: leafNodesWithFrames(node: row, displayFrame: childFrame))
                y += h
            }
            return result

        default:
            return [(node, displayFrame)]
        }
    }

    /// Estimate the bounding frame for a new trailing column.
    private static func trailingColumnFrame(node: LayoutNode, displayFrame: WindowFrame) -> WindowFrame {
        let ghostWidth = max(displayFrame.width * 0.15, 60)
        return WindowFrame(
            x: displayFrame.x + displayFrame.width - ghostWidth,
            y: displayFrame.y,
            width: ghostWidth,
            height: displayFrame.height
        )
    }

    /// Estimate the bounding frame for a new trailing row.
    private static func trailingRowFrame(node: LayoutNode, displayFrame: WindowFrame) -> WindowFrame {
        let ghostHeight = max(displayFrame.height * 0.15, 60)
        return WindowFrame(
            x: displayFrame.x,
            y: displayFrame.y + displayFrame.height - ghostHeight,
            width: displayFrame.width,
            height: ghostHeight
        )
    }
}
