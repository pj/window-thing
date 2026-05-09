import SwiftUI
import WindowThingCore
import WindowThingViewModel

// MARK: - AppSelectorView

struct AppSelectorView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var searchFieldFocused = false

    private var isStackMode: Bool { viewModel.selectorIsForStack }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if currentItemCount == 0 {
                emptyState
            } else {
                ScrollView {
                    gridContent
                        .padding(12)
                }
            }
        }
        .frame(width: 560, height: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(radius: 24, y: 8)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack {
                // Mode tabs
                HStack(spacing: 2) {
                    modeTab("Apps", mode: .app, icon: "square.grid.2x2")
                    modeTab("Windows", mode: .window, icon: "macwindow")
                }
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Text("Shift")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    viewModel.hideAppSelector()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField(
                    isStackMode ? "Filter stack windows..." : "Search apps...",
                    text: $viewModel.appSelectorSearchText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                if !viewModel.appSelectorSearchText.isEmpty {
                    Button {
                        viewModel.appSelectorSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
    }

    private func modeTab(_ title: String, mode: AppSelectorMode, icon: String) -> some View {
        Button {
            viewModel.appSelectorMode = mode
            viewModel.appSelectorSelectedIndex = 0
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: viewModel.appSelectorMode == mode ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    viewModel.appSelectorMode == mode
                        ? Color(nsColor: .controlBackgroundColor)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private let gridColumns = [GridItem(.adaptive(minimum: 160), spacing: 10)]

    private var currentItemCount: Int {
        viewModel.appSelectorMode == .app
            ? viewModel.filteredApps.count
            : (isStackMode ? viewModel.stackWindows.count : viewModel.filteredWindows.count)
    }

    @ViewBuilder
    private var gridContent: some View {
        if viewModel.appSelectorMode == .app {
            appGrid
        } else if isStackMode {
            stackGrid
        } else {
            windowGrid
        }
    }

    private var appGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(Array(viewModel.filteredApps.enumerated()), id: \.element.id) { index, app in
                AppGridItem(
                    name: app.name,
                    icon: appIcon(for: app),
                    thumbnails: appThumbnails(for: app),
                    index: index,
                    isSelected: index == viewModel.appSelectorSelectedIndex
                ) {
                    viewModel.applyAppSelectorSelection(at: index)
                }
            }
        }
    }

    private var windowGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(Array(viewModel.filteredWindows.enumerated()), id: \.element.id) { index, window in
                WindowGridItem(
                    window: window,
                    index: index,
                    isSelected: index == viewModel.appSelectorSelectedIndex
                ) {
                    viewModel.applyAppSelectorSelection(at: index)
                }
            }
        }
    }

    private var stackGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(Array(viewModel.stackWindows.enumerated()), id: \.element.id) { index, window in
                WindowGridItem(
                    window: window,
                    index: index,
                    isSelected: index == viewModel.appSelectorSelectedIndex
                ) {
                    viewModel.applyAppSelectorSelection(at: index)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func appThumbnails(for app: RunningAppInfo) -> [NSImage] {
        guard let bundleId = app.bundleId else { return [] }
        return viewModel.runningWindows
            .filter { $0.bundleId == bundleId }
            .prefix(3)
            .compactMap { WindowThumbnailCache.shared.nsImage(for: $0.id) }
    }

    private func appIcon(for app: RunningAppInfo) -> NSImage? {
        guard let bundleId = app.bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Grid Items

private struct AppGridItem: View {
    let name: String
    let icon: NSImage?
    let thumbnails: [NSImage]
    let index: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Thumbnail stack or app icon
                ZStack(alignment: .topTrailing) {
                    thumbnailStack
                        .frame(width: 72, height: 48)
                    if index < 9 {
                        numberBadge(index + 1)
                    }
                }

                // App icon + name to the right
                VStack(alignment: .leading, spacing: 3) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    Text(name)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailStack: some View {
        if thumbnails.isEmpty {
            // Fallback: show app icon large
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            ZStack {
                ForEach(Array(thumbnails.prefix(3).enumerated().reversed()), id: \.offset) { i, img in
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64 - CGFloat(i) * 4, height: 42 - CGFloat(i) * 2)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 1, x: 1, y: 1)
                        .offset(x: CGFloat(i) * -4, y: CGFloat(i) * -3)
                }
            }
        }
    }
}

private struct WindowGridItem: View {
    let window: WindowThingCore.Window
    let index: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Thumbnail
                ZStack(alignment: .topTrailing) {
                    thumbnailView
                        .frame(width: 72, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 1, y: 1)
                    if index < 9 {
                        numberBadge(index + 1)
                    }
                }

                // App icon + title to the right
                VStack(alignment: .leading, spacing: 3) {
                    appIconView
                        .frame(width: 18, height: 18)
                    Text(window.title.isEmpty ? window.application : window.title)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let img = WindowThumbnailCache.shared.nsImage(for: window.id) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.secondary.opacity(0.1)
                .overlay {
                    Image(systemName: "macwindow")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
        }
    }

    @ViewBuilder
    private var appIconView: some View {
        if let bundleId = window.bundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Number Badge

private func numberBadge(_ number: Int) -> some View {
    Text("\(number)")
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .background(Circle().fill(Color.accentColor.opacity(0.9)))
        .offset(x: 6, y: -6)
}
