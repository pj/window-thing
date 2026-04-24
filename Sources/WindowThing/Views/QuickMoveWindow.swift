import SwiftUI
import AppKit
import WindowThingCore
import WindowThingViewModel

// MARK: - QuickMoveWindow

class QuickMoveWindow: NSWindow {

    init() {
        let width: CGFloat = 600
        let height: CGFloat = 340
        let screenBounds = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let rect = NSRect(
            x: (screenBounds.width  - width)  / 2 + screenBounds.origin.x,
            y: (screenBounds.height - height) / 2 + screenBounds.origin.y,
            width: width,
            height: height
        )

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let view = QuickMoveView { [weak self] in self?.hide() }
        let hv = NSHostingView(rootView: view)
        hv.frame = NSRect(origin: .zero, size: rect.size)
        contentView = hv
    }

    func show() {
        // Re-centre on whichever screen the cursor is on
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        let sf = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: sf.midX - frame.width  / 2,
            y: sf.midY - frame.height / 2
        ))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { orderOut(nil) }

    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { hide(); return }   // Escape
        if let ch = event.charactersIgnoringModifiers,
           LayoutManager.shared.applyLayoutByQuickKey(ch) {
            hide(); return
        }
        super.keyDown(with: event)
    }
}

// MARK: - QuickMoveView

struct QuickMoveView: View {
    let onDismiss: () -> Void

    @State private var layouts: [WTLayout] = []

    private let columns = [GridItem(.adaptive(minimum: 152, maximum: 200), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Apply Layout")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("Press key or click to apply")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().opacity(0.4)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(layouts) { layout in
                        QuickMoveCard(layout: layout) {
                            LayoutManager.shared.applyLayout(layout)
                            onDismiss()
                        }
                    }
                }
                .padding(14)
            }
        }
        .background {
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: 14).glassEffect()
            } else {
                RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { layouts = LayoutManager.shared.layouts }
    }
}

// MARK: - QuickMoveCard

struct QuickMoveCard: View {
    let layout: WTLayout
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                // Layout preview thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.1))
                    if let screenSet = layout.screenSets.first {
                        MultiMonitorPreviewView(
                            screenConfig: screenSet,
                            graphicSize: CGSize(width: 126, height: 68)
                        )
                    }
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(.separatorColor), lineWidth: 0.5)
                }
                .frame(height: 74)

                // Name + quick-key badge
                HStack(spacing: 5) {
                    Text(layout.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    if let key = layout.quickKey {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color(.separatorColor), lineWidth: 0.5))
                                .shadow(color: .secondary.opacity(0.3), radius: 0, x: 0, y: 1)
                            Text(key.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 18, height: 15)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(hovering ? Color.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(hovering ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
