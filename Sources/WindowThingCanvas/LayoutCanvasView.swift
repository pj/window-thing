import SwiftUI

/// Entry point for the generic layout canvas.
///
/// `Content` is an opaque type representing whatever the caller pins to a leaf tile.
/// The canvas has no knowledge of what `Content` means — it only calls `tileLabel` to
/// display a string inside a pinned tile.
public struct LayoutCanvasView<Content: Hashable & Sendable>: View {

    public let root: CanvasNode<Content>
    public let onRootChanged: (CanvasNode<Content>) -> Void
    public let tileLabel: (Content) -> String
    public let style: CanvasStyle

    public init(
        root: CanvasNode<Content>,
        onRootChanged: @escaping (CanvasNode<Content>) -> Void,
        tileLabel: @escaping (Content) -> String = { _ in "" },
        style: CanvasStyle = .default
    ) {
        self.root = root
        self.onRootChanged = onRootChanged
        self.tileLabel = tileLabel
        self.style = style
    }

    public var body: some View {
        GeometryReader { geo in
            CanvasTileView(
                node: root,
                path: [],
                containerSize: geo.size,
                onRootChanged: onRootChanged,
                onDelete: nil,
                tileLabel: tileLabel,
                style: style
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(12)
        .background(style.background)
        .onHover { hovering in
            if hovering { CellSplitOverlay.scissorCursor.push() }
            else { NSCursor.pop() }
        }
    }
}
