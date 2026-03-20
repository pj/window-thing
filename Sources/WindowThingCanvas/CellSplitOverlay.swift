import SwiftUI
import AppKit

/// A cross of perforated dashed lines shown over every leaf tile.
/// Hovering the left/right half highlights the vertical line (split into columns);
/// hovering the top/bottom half highlights the horizontal line (split into rows).
/// Clicking fires the appropriate split action.
struct CellSplitOverlay: View {
    let onSplitColumns: () -> Void
    let onSplitRows: () -> Void

    @State private var hoverAxis: SplitAxis? = nil

    enum SplitAxis { case columns, rows }

    static let scissorCursor: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
        if let img = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
            let hotSpot = NSPoint(x: img.size.width * 0.15, y: img.size.height * 0.5)
            return NSCursor(image: img, hotSpot: hotSpot)
        }
        return .crosshair
    }()

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let dashStyle = StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                let inset: CGFloat = 6

                var vPath = Path()
                vPath.move(to: CGPoint(x: size.width / 2, y: inset))
                vPath.addLine(to: CGPoint(x: size.width / 2, y: size.height - inset))
                ctx.stroke(vPath,
                           with: .color(hoverAxis == .columns
                               ? Color.accentColor
                               : Color.secondary.opacity(0.2)),
                           style: dashStyle)

                var hPath = Path()
                hPath.move(to: CGPoint(x: inset, y: size.height / 2))
                hPath.addLine(to: CGPoint(x: size.width - inset, y: size.height / 2))
                ctx.stroke(hPath,
                           with: .color(hoverAxis == .rows
                               ? Color.accentColor
                               : Color.secondary.opacity(0.2)),
                           style: dashStyle)
            }
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        let relX = abs(loc.x - geo.size.width / 2)
                        let relY = abs(loc.y - geo.size.height / 2)
                        hoverAxis = relX > relY ? .rows : .columns
                    case .ended:
                        hoverAxis = nil
                    }
                }
                .onTapGesture {
                    switch hoverAxis {
                    case .columns: onSplitColumns()
                    case .rows:    onSplitRows()
                    case nil:      break
                    }
                }
        }
    }
}
