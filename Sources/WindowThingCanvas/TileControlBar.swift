import SwiftUI

/// The always-visible control bar at the top of every leaf tile.
/// Contains a delete button (non-root only) and a segmented type picker.
struct TileControlBar<Content: Hashable & Sendable>: View {
    let node: CanvasNode<Content>
    let isRoot: Bool
    let onDelete: () -> Void
    let onNodeChanged: (CanvasNode<Content>) -> Void
    /// AnyView-erased picker — the public API accepts any View via @ViewBuilder.
    let picker: (Content?, @escaping (Content) -> Void) -> AnyView

    private var isEmptyKind: Bool { if case .empty = node.kind { return true }; return false }
    private var isStackKind: Bool { if case .stack = node.kind { return true }; return false }

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

            HStack(spacing: 0) {
                segmentButton(label: "Empty", icon: "square", active: isEmptyKind) {
                    onNodeChanged(node.withKind(.empty))
                }

                Divider().frame(height: 14)

                segmentButton(label: "Stack", icon: "square.stack.fill", active: isStackKind) {
                    onNodeChanged(node.withKind(.stack))
                }

                Divider().frame(height: 14)

                // Caller-supplied picker — displayed as the third segment.
                picker(node.pinnedContent) { selected in
                    onNodeChanged(node.withKind(.pinned(selected)))
                }
            }
            .fixedSize()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

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
}
