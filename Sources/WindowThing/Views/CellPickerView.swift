import SwiftUI
import WindowThingCore
import WindowThingViewModel

// MARK: - CellPickerView

/// Overlay sheet that lets the user pick a cell (or a ghost cell to extend the layout)
/// for the window that is being moved.
struct CellPickerView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !viewModel.pickerCells.isEmpty {
                        cellSection
                    }
                    if !viewModel.pickerGhostPositions.isEmpty {
                        ghostSection
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(radius: 24, y: 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Move Window to Cell")
                    .font(.headline)
                if let window = viewModel.pendingMoveWindow {
                    Text(window.title.isEmpty ? window.application : window.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button {
                viewModel.hideCellPicker()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Cell Grid

    private var cellSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cells")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let grouped = Dictionary(grouping: viewModel.pickerCells) { $0.displayName }
            ForEach(grouped.keys.sorted(), id: \.self) { displayName in
                if let cells = grouped[displayName] {
                    VStack(alignment: .leading, spacing: 6) {
                        if grouped.count > 1 {
                            Text(displayName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                            spacing: 8
                        ) {
                            ForEach(cells, id: \.address) { cell in
                                CellAddressButton(
                                    label: cell.address.stringValue,
                                    isGhost: false,
                                    isDisabled: false
                                ) {
                                    viewModel.selectCell(cell.address)
                                    onDismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Ghost Cell Section

    private var ghostSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add New Cell")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(Array(viewModel.pickerGhostPositions.enumerated()), id: \.offset) { _, ghost in
                let label: String = switch ghost.direction {
                case .trailingColumn: "+ Column"
                case .trailingRow: "+ Row"
                }
                let icon: String = switch ghost.direction {
                case .trailingColumn: "rectangle.portrait.and.arrow.right"
                case .trailingRow: "rectangle.and.arrow.up.right.and.arrow.down.left"
                }
                Button {
                    viewModel.selectGhostCell(ghost)
                    onDismiss()
                } label: {
                    Label(label, systemImage: icon)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(ghost.isDisabled
                            ? Color.secondary.opacity(0.05)
                            : Color.accentColor.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ghost.isDisabled
                                    ? Color.secondary.opacity(0.15)
                                    : Color.accentColor.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(ghost.isDisabled)
                .opacity(ghost.isDisabled ? 0.45 : 1)
                .help(ghost.isDisabled ? "Cannot add — cell would be below minimum size (15%)" : "")
            }
        }
    }
}

// MARK: - CellAddressButton

private struct CellAddressButton: View {
    let label: String
    let isGhost: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(minWidth: 36, minHeight: 36)
                .background(
                    isGhost
                        ? Color.accentColor.opacity(0.06)
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isGhost
                                ? Color.accentColor.opacity(0.35)
                                : Color.secondary.opacity(0.2),
                            style: isGhost
                                ? StrokeStyle(lineWidth: 1, dash: [4, 3])
                                : StrokeStyle(lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
