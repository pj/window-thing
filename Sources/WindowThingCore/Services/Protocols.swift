import Foundation

// MARK: - Window Management Protocol

public protocol WindowManaging {
    func getDisplays() -> [Display]
    func getWindows() -> [Window]
    func setWindowFrame(pid: pid_t, windowTitle: String?, frame: WindowFrame) -> Bool
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
