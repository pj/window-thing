import SwiftUI
import WindowThingCanvas

struct DemoItem: Hashable, Sendable {
    let name: String
}

struct ContentView: View {
    @State private var root: CanvasNode<DemoItem> = .columns([
        .pinned(DemoItem(name: "Alpha"), percentage: 50),
        .rows([
            .empty(percentage: 50),
            .empty(percentage: 50),
        ], percentage: 50),
    ])

    var body: some View {
        VStack(spacing: 0) {
            LayoutCanvasView(
                root: root,
                onRootChanged: { root = $0 },
                tileLabel: { $0.name }
            )

            Divider()

            HStack(spacing: 12) {
                Button("Reset to single tile") { root = .empty() }
                    .buttonStyle(.bordered)
                Button("Reset to columns") {
                    root = .columns([
                        .empty(percentage: 33),
                        .empty(percentage: 34),
                        .empty(percentage: 33),
                    ])
                }
                .buttonStyle(.bordered)
                Spacer()
                Text(rootSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var rootSummary: String {
        switch root.kind {
        case .empty:              return "empty"
        case .stack:              return "stack"
        case .pinned(let c):      return "pinned(\(c.name))"
        case .columns(let cols):  return "columns(\(cols.count))"
        case .rows(let rs):       return "rows(\(rs.count))"
        }
    }
}
