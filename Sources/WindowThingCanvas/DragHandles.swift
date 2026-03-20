import SwiftUI
import AppKit

// MARK: - Column Drag Handle

/// A vertical strip placed on the boundary between two sibling columns.
/// Uses AppKit mouse tracking so the cursor can be locked to the divider via CGWarpMouseCursorPosition.
struct ColumnDragHandle: View {
    let leftPct: Double
    let rightPct: Double
    let pxPerPct: CGFloat
    let onChanging: (Double, Double) -> Void
    let onCommitted: (Double, Double) -> Void

    @State private var dragging = false
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(dragging ? Color.accentColor.opacity(0.2) : Color.clear)
                .overlay(
                    Rectangle()
                        .fill(dragging ? Color.accentColor : Color.secondary.opacity(hovering ? 0.4 : 0.18))
                        .frame(width: 2)
                )
            DragHandleRepresentable(
                axis: .horizontal,
                pxPerPct: pxPerPct,
                startPctA: leftPct,
                startPctB: rightPct,
                onHoverChanged: { hovering = $0 },
                onDragStarted: { dragging = true },
                onDragEnded: { dragging = false },
                onChanging: onChanging,
                onCommitted: onCommitted
            )
        }
    }
}

// MARK: - Row Drag Handle

/// A horizontal strip placed on the boundary between two sibling rows.
struct RowDragHandle: View {
    let topPct: Double
    let bottomPct: Double
    let pxPerPct: CGFloat
    let onChanging: (Double, Double) -> Void
    let onCommitted: (Double, Double) -> Void

    @State private var dragging = false
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(dragging ? Color.accentColor.opacity(0.2) : Color.clear)
                .overlay(
                    Rectangle()
                        .fill(dragging ? Color.accentColor : Color.secondary.opacity(hovering ? 0.4 : 0.18))
                        .frame(height: 2)
                )
            DragHandleRepresentable(
                axis: .vertical,
                pxPerPct: pxPerPct,
                startPctA: topPct,
                startPctB: bottomPct,
                onHoverChanged: { hovering = $0 },
                onDragStarted: { dragging = true },
                onDragEnded: { dragging = false },
                onChanging: onChanging,
                onCommitted: onCommitted
            )
        }
    }
}

// MARK: - NSViewRepresentable bridge

private struct DragHandleRepresentable: NSViewRepresentable {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    let pxPerPct: CGFloat
    let startPctA: Double
    let startPctB: Double
    let onHoverChanged: (Bool) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    let onChanging: (Double, Double) -> Void
    let onCommitted: (Double, Double) -> Void

    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView()
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        nsView.axis = axis
        nsView.pxPerPct = pxPerPct
        nsView.startPctA = startPctA
        nsView.startPctB = startPctB
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
        nsView.onChanging = onChanging
        nsView.onCommitted = onCommitted
    }
}

// MARK: - NSView implementation

private class DragHandleNSView: NSView {
    var axis: DragHandleRepresentable.Axis = .horizontal
    var pxPerPct: CGFloat = 1
    // These hold the percentages at the LAST committed state.
    // We capture them into capturedA/B at mouseDown so updateNSView calls mid-drag don't corrupt them.
    var startPctA: Double = 0
    var startPctB: Double = 0
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onDragStarted: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onChanging: (Double, Double) -> Void = { _, _ in }
    var onCommitted: (Double, Double) -> Void = { _, _ in }

    private var isDragging = false
    private var capturedA: Double = 0
    private var capturedB: Double = 0
    private var lastA: Double = 0
    private var lastB: Double = 0
    // Divider center in window coords at the moment the drag started.
    // Using absolute locationInWindow avoids mouse-acceleration artifacts from deltaX/deltaY.
    private var dragStartWindowPos: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        capturedA = startPctA
        capturedB = startPctB
        lastA = startPctA
        lastB = startPctB
    }

    override func mouseDragged(with event: NSEvent) {
        if !isDragging {
            isDragging = true
            // Snap cursor to divider center so the drag baseline is unambiguous.
            // We warp once here, then immediately cancel the suppression interval so
            // subsequent locationInWindow reads are accurate.
            snapCursorToCenter()
            CGAssociateMouseAndMouseCursorPosition(1)
            dragStartWindowPos = dividerCenterInWindow()
            onDragStarted()
            // Don't process movement on the snap frame — the event's locationInWindow
            // still reflects the click position, not the warped position.
            return
        }

        // Absolute cursor position → no mouse-acceleration artifacts.
        // Cocoa y increases upward; for rows, moving down should grow the top tile,
        // so negate the vertical displacement.
        let curPos = axis == .horizontal ? event.locationInWindow.x : event.locationInWindow.y
        let rawDisp = curPos - dragStartWindowPos
        let displacement = axis == .horizontal ? rawDisp : -rawDisp

        let localTotal = capturedA + capturedB
        let deltaPct = Double(displacement) / Double(pxPerPct)
        let newA = min(max(5, capturedA + deltaPct), localTotal - 5)
        lastA = newA
        lastB = localTotal - newA
        onChanging(lastA, lastB)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDragEnded()
        onCommitted(lastA, lastB)
    }

    // MARK: Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged(true)
        (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
        NSCursor.pop()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    // MARK: Cursor helpers

    /// The divider center's position along the drag axis, in window coordinates.
    private func dividerCenterInWindow() -> CGFloat {
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
        return axis == .horizontal ? center.x : center.y
    }

    /// Warp the cursor to the divider center so the drag baseline starts exactly there.
    /// Only called once at drag start; after this call the caller must invoke
    /// CGAssociateMouseAndMouseCursorPosition(1) to cancel the suppression interval.
    private func snapCursorToCenter() {
        guard let window = self.window, let primaryScreen = NSScreen.screens.first else { return }
        let inWindow = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
        let inScreen = window.convertPoint(toScreen: inWindow)
        CGWarpMouseCursorPosition(CGPoint(x: inScreen.x,
                                          y: primaryScreen.frame.height - inScreen.y))
    }

}
