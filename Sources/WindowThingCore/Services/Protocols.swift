import Foundation
import CoreGraphics

// MARK: - Window Management Protocol

public protocol WindowManaging {
    func getDisplays() -> [Display]
    func getWindows() -> [Window]
    func setWindowFrame(pid: pid_t, windowTitle: String?, frame: WindowFrame) -> Bool
    func setWindowFrame(pid: pid_t, windowId: CGWindowID, frame: WindowFrame) -> Bool

    /// Bracket a run of `setWindowFrame` calls so window lookups can be
    /// memoised for its duration. Optional: the default pair does nothing, and
    /// correctness never depends on them being called.
    func beginFrameBatch()
    func endFrameBatch()
    func getFocusedApplication() -> Application?
}

// MARK: - Configuration Protocol

public protocol ConfigProviding {
    var config: AppConfig { get }
    var configFilePath: URL { get }
    var setupsFilePath: URL { get }

    func loadConfig()
    func saveConfig()
    func saveLayouts(_ layouts: [Layout])
}

// MARK: - Layout Management Protocol

public protocol LayoutManaging {
    var layouts: [Layout] { get }
    var savedSetups: [SavedSetup] { get }
    var currentLayout: Layout? { get }
    var lastUsedLayout: Layout? { get }

    func loadLayouts(from config: AppConfig)
    func applyLayout(_ layout: Layout)
    func updateLayout(_ layout: Layout)
    func saveCurrentSetup(name: String)
    func loadSetup(_ setup: SavedSetup)
    func moveWindow(_ window: Window, toCellAt address: CellAddress, displays: [Display]) throws
    func cellAddresses(for layout: Layout, displays: [Display]) -> [IndexedCell]
}


public extension WindowManaging {
    func beginFrameBatch() {}
    func endFrameBatch() {}
}
