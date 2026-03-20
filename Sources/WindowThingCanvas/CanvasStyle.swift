import SwiftUI

/// Visual configuration for `LayoutCanvasView`.
public struct CanvasStyle: Sendable {
    /// The canvas background — should contrast clearly with `cell`.
    public var background: Color
    /// Fill color for individual leaf tiles.
    public var cell: Color

    public init(background: Color, cell: Color) {
        self.background = background
        self.cell = cell
    }

    /// Default: dark backing with light cells for clear contrast.
    public static let `default` = CanvasStyle(
        background: Color(nsColor: .underPageBackgroundColor),
        cell: Color(nsColor: .controlBackgroundColor)
    )
}
