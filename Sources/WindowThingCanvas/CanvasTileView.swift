import SwiftUI

/// Recursive tile renderer. Dispatches to columns layout, rows layout, or leaf tile
/// depending on the node kind.
struct CanvasTileView<Content: Hashable & Sendable>: View {
    let node: CanvasNode<Content>
    let path: [Int]
    let containerSize: CGSize
    let onRootChanged: (CanvasNode<Content>) -> Void
    /// nil for the root tile (nothing to delete it into).
    let onDelete: (() -> Void)?
    let tileLabel: (Content) -> String
    let style: CanvasStyle

    private let tileGap: CGFloat = 4

    var body: some View {
        switch node.kind {
        case .columns(let cols) where !cols.isEmpty:
            columnsLayout(cols)
        case .rows(let rs) where !rs.isEmpty:
            rowsLayout(rs)
        default:
            leafTile
        }
    }

    // MARK: - Columns
    // Tiles use HStack for proper SwiftUI layout propagation.
    // Drag handles are ZStack-overlaid — small (16pt wide) and clipped.

    @ViewBuilder
    private func columnsLayout(_ cols: [CanvasNode<Content>]) -> some View {
        let total = max(cols.reduce(0.0) { $0 + $1.percentage }, 1.0)
        let totalGaps = tileGap * CGFloat(cols.count - 1)
        let available = containerSize.width - totalGaps
        let pxPerPct = available / CGFloat(total)
        let frames = childFrames(cols, size: containerSize, isColumns: true)

        ZStack(alignment: .topLeading) {
            HStack(spacing: tileGap) {
                ForEach(Array(frames.enumerated()), id: \.offset) { i, item in
                    CanvasTileView(
                        node: item.node,
                        path: path + [i],
                        containerSize: item.frame.size,
                        onRootChanged: { newChild in
                            var updated = cols
                            updated[i] = newChild
                            onRootChanged(node.withColumns(updated))
                        },
                        onDelete: {
                            var updated = cols
                            let deletedPct = updated.remove(at: i).percentage
                            let perSibling = deletedPct / Double(updated.count)
                            updated = updated.map { $0.withPercentage($0.percentage + perSibling) }
                            if updated.count == 1 {
                                onRootChanged(updated[0].withPercentage(node.percentage))
                            } else {
                                onRootChanged(node.withColumns(updated))
                            }
                        },
                        tileLabel: tileLabel,
                        style: style
                    )
                    .frame(width: item.frame.width, height: item.frame.height)
                }
            }

            ForEach(0..<(frames.count - 1), id: \.self) { i in
                let boundaryX = frames[i].frame.maxX + tileGap / 2
                ColumnDragHandle(
                    leftPct: cols[i].percentage,
                    rightPct: cols[i + 1].percentage,
                    pxPerPct: pxPerPct,
                    onChanging: { lp, rp in
                        var updated = cols
                        updated[i] = updated[i].withPercentage(lp)
                        updated[i + 1] = updated[i + 1].withPercentage(rp)
                        onRootChanged(node.withColumns(updated))
                    },
                    onCommitted: { lp, rp in
                        var updated = cols
                        updated[i] = updated[i].withPercentage(lp)
                        updated[i + 1] = updated[i + 1].withPercentage(rp)
                        onRootChanged(node.withColumns(updated))
                    }
                )
                .frame(width: 16, height: containerSize.height)
                .offset(x: boundaryX - 8, y: 0)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipped()
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowsLayout(_ rs: [CanvasNode<Content>]) -> some View {
        let total = max(rs.reduce(0.0) { $0 + $1.percentage }, 1.0)
        let totalGaps = tileGap * CGFloat(rs.count - 1)
        let available = containerSize.height - totalGaps
        let pxPerPct = available / CGFloat(total)
        let frames = childFrames(rs, size: containerSize, isColumns: false)

        ZStack(alignment: .topLeading) {
            VStack(spacing: tileGap) {
                ForEach(Array(frames.enumerated()), id: \.offset) { i, item in
                    CanvasTileView(
                        node: item.node,
                        path: path + [i],
                        containerSize: item.frame.size,
                        onRootChanged: { newChild in
                            var updated = rs
                            updated[i] = newChild
                            onRootChanged(node.withRows(updated))
                        },
                        onDelete: {
                            var updated = rs
                            let deletedPct = updated.remove(at: i).percentage
                            let perSibling = deletedPct / Double(updated.count)
                            updated = updated.map { $0.withPercentage($0.percentage + perSibling) }
                            if updated.count == 1 {
                                onRootChanged(updated[0].withPercentage(node.percentage))
                            } else {
                                onRootChanged(node.withRows(updated))
                            }
                        },
                        tileLabel: tileLabel,
                        style: style
                    )
                    .frame(width: item.frame.width, height: item.frame.height)
                }
            }

            ForEach(0..<(frames.count - 1), id: \.self) { i in
                let boundaryY = frames[i].frame.maxY + tileGap / 2
                RowDragHandle(
                    topPct: rs[i].percentage,
                    bottomPct: rs[i + 1].percentage,
                    pxPerPct: pxPerPct,
                    onChanging: { tp, bp in
                        var updated = rs
                        updated[i] = updated[i].withPercentage(tp)
                        updated[i + 1] = updated[i + 1].withPercentage(bp)
                        onRootChanged(node.withRows(updated))
                    },
                    onCommitted: { tp, bp in
                        var updated = rs
                        updated[i] = updated[i].withPercentage(tp)
                        updated[i + 1] = updated[i + 1].withPercentage(bp)
                        onRootChanged(node.withRows(updated))
                    }
                )
                .frame(width: containerSize.width, height: 16)
                .offset(x: 0, y: boundaryY - 8)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipped()
    }

    // MARK: - Leaf tile

    private var leafTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(style.cell)
            Text("\(Int(node.percentage.rounded()))%")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .overlay {
            ZStack(alignment: .topLeading) {
                // Split overlay is below — scissors cursor rect covers the whole cell.
                CellSplitOverlay(
                    onSplitColumns: {
                        onRootChanged(node.withColumns([
                            node.withPercentage(50),
                            .empty(percentage: 50),
                        ]))
                    },
                    onSplitRows: {
                        onRootChanged(node.withRows([
                            node.withPercentage(50),
                            .empty(percentage: 50),
                        ]))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Delete button is above — its CursorView(.arrow) beats scissors in its area,
                // and its tap gesture beats CellSplitOverlay's tap gesture.
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(4)
                }
            }
        }
    }

    // MARK: - Frame calculation

    func childFrames(
        _ children: [CanvasNode<Content>],
        size: CGSize,
        isColumns: Bool
    ) -> [(node: CanvasNode<Content>, frame: CGRect)] {
        let total = max(children.reduce(0.0) { $0 + $1.percentage }, 1.0)
        let totalGaps = tileGap * CGFloat(max(0, children.count - 1))
        let available = isColumns ? (size.width - totalGaps) : (size.height - totalGaps)
        var offset: CGFloat = 0
        return children.map { child in
            let fraction = CGFloat(child.percentage / total)
            if isColumns {
                let w = available * fraction
                let frame = CGRect(x: offset, y: 0, width: w, height: size.height)
                offset += w + tileGap
                return (child, frame)
            } else {
                let h = available * fraction
                let frame = CGRect(x: 0, y: offset, width: size.width, height: h)
                offset += h + tileGap
                return (child, frame)
            }
        }
    }
}
