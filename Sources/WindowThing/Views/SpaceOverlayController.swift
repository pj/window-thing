import AppKit
import WindowThingCore
import WindowThingViewModel

/// Owns the activation surface across every screen.
///
/// The surface is one thing spread over several windows: each screen gets its
/// own borderless overlay showing that screen's slice of the layout, and they
/// share a single `OverlayViewModel` so an edit made on one screen is the same
/// edit everywhere. Giving each window its own model would mean several copies
/// of the layout racing to save over each other.
final class SpaceOverlayController {
    let viewModel = OverlayViewModel()

    private(set) var windows: [SpaceOverlayWindow] = []

    var isVisible: Bool { windows.contains { $0.isVisible } }

    /// Set while capturing screenshots — nothing holds key focus in an
    /// automated session and the surface would dismiss itself immediately.
    var staysVisibleWhenInactive = false {
        didSet { windows.forEach { $0.staysVisibleWhenInactive = staysVisibleWhenInactive } }
    }

    init() {
        // Rebuild when displays are attached, removed, or rearranged.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        }
    }

    // MARK: - Presentation

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        // Capture the focused window before we steal focus: it's the subject of
        // the cell-address shortcuts.
        let manager = WindowManager.shared
        if let app = manager.getFocusedApplication(),
           let window = app.focusedWindow
            ?? manager.getWindows().first(where: { $0.pid == app.id || $0.bundleId == app.bundleId }) {
            viewModel.selectedMoveWindow = window
        }

        // Shared model work happens once, not once per screen.
        viewModel.refresh()
        viewModel.refreshRunningApps()
        viewModel.presentationCount += 1
        WindowThumbnailCache.shared.start()

        rebuildWindows()
        windows.forEach { $0.show() }

        // Key focus goes to the screen the pointer is on, so the keyboard acts
        // where the user is looking.
        (windowUnderPointer() ?? windows.first)?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        viewModel.hideAppSelector()
        viewModel.hideCellPicker()
        viewModel.isTextFieldFocused = false
        windows.forEach { $0.hide() }
    }

    /// Open with the cell picker already up for the frontmost window.
    func showCellPickerForFocusedWindow() {
        if !isVisible { show() }
        if let window = viewModel.selectedMoveWindow {
            viewModel.showCellPicker(for: window)
        }
    }

    // MARK: - Windows

    private func screensChanged() {
        guard isVisible else {
            // Not on screen: drop the windows and rebuild at next show.
            windows.forEach { $0.orderOut(nil) }
            windows = []
            return
        }
        viewModel.refresh()
        rebuildWindows()
        windows.forEach { $0.show() }
    }

    /// One window per screen, reusing any that still match a live screen.
    private func rebuildWindows() {
        let screens = NSScreen.screens
        let displays = viewModel.displays

        var rebuilt: [SpaceOverlayWindow] = []
        for screen in screens {
            let key = monitorKey(for: screen, displays: displays)
            if let existing = windows.first(where: {
                $0.targetScreen == screen && $0.monitorKey == key
            }) {
                rebuilt.append(existing)
                continue
            }
            let window = SpaceOverlayWindow(
                viewModel: viewModel,
                screen: screen,
                monitorKey: key,
                dismissAll: { [weak self] in self?.hide() }
            )
            window.staysVisibleWhenInactive = staysVisibleWhenInactive
            rebuilt.append(window)
        }

        // Retire windows whose screen has gone.
        for stale in windows where !rebuilt.contains(where: { $0 === stale }) {
            stale.orderOut(nil)
        }
        windows = rebuilt
    }

    /// A screen set names the main display `$PRIMARY` and the rest by name, so
    /// a layout keeps working when the main display changes.
    private func monitorKey(for screen: NSScreen, displays: [Display]) -> String {
        if screen == NSScreen.main { return ScreenConfig.primaryKey }
        let name = screen.localizedName
        return displays.first(where: { $0.name == name })?.name ?? name
    }

    private func windowUnderPointer() -> SpaceOverlayWindow? {
        let point = NSEvent.mouseLocation
        return windows.first { $0.targetScreen.frame.contains(point) }
    }
}
