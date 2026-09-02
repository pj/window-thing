import Foundation
import CoreGraphics

// MARK: - Hotkey Configuration

public struct HotKeyConfig: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: [String]

    public init(keyCode: UInt32, modifiers: [String]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Default: Ctrl+Option+W
    public static var `default`: HotKeyConfig {
        HotKeyConfig(keyCode: 13, modifiers: ["control", "option"])  // W = 13
    }

    /// Default for moving the focused window to a cell: Ctrl+Option+M.
    ///
    /// Given a default at all because the feature was unreachable without one.
    /// Everything behind it worked — the addresses, the move, the ghost cells
    /// for extending the layout — but nothing triggered it unless you had
    /// written `cellPickerHotKey` into config.yaml yourself, and nothing in the
    /// app told you that key existed.
    public static var defaultCellPicker: HotKeyConfig {
        HotKeyConfig(keyCode: 46, modifiers: ["control", "option"])  // M = 46
    }
}

// MARK: - App Configuration

public struct AppConfig: Codable, Sendable {
    public var activationHotKey: HotKeyConfig
    public var layouts: [Layout]
    public var defaultLayoutName: String?

    // Visual settings
    public var overlayOpacity: Double
    public var overlayBackgroundColor: String
    public var highlightColor: String

    // Behavior settings
    public var pollIntervalMs: Int
    public var minimumWindowWidth: CGFloat
    public var minimumWindowHeight: CGFloat

    /// Windows layouts should leave alone, beyond what can be detected
    /// automatically. Absent means `WindowExclusion.defaults`; present replaces
    /// them entirely, so an empty list turns exclusions off.
    public var excludedWindows: [WindowExclusion]?

    /// The rules actually in force.
    public var effectiveExclusions: [WindowExclusion] {
        excludedWindows ?? WindowExclusion.defaults
    }

    // Cell hotkeys: key is CellAddress string ("1", "2", "a", …)
    public var cellHotKeys: [String: HotKeyConfig]?

    // Hotkey to open the interactive cell picker. nil = no hotkey.
    public var cellPickerHotKey: HotKeyConfig?

    // How often (seconds) to refresh window thumbnails. Clamped to 2–5 at runtime.
    public var thumbnailCaptureInterval: TimeInterval?

    public var minimumWindowSize: CGSize {
        CGSize(width: minimumWindowWidth, height: minimumWindowHeight)
    }

    public init(
        activationHotKey: HotKeyConfig,
        layouts: [Layout],
        defaultLayoutName: String? = nil,
        overlayOpacity: Double,
        overlayBackgroundColor: String,
        highlightColor: String,
        pollIntervalMs: Int,
        minimumWindowWidth: CGFloat,
        minimumWindowHeight: CGFloat,
        excludedWindows: [WindowExclusion]? = nil,
        cellHotKeys: [String: HotKeyConfig]? = nil,
        cellPickerHotKey: HotKeyConfig? = nil,
        thumbnailCaptureInterval: TimeInterval? = nil
    ) {
        self.activationHotKey = activationHotKey
        self.layouts = layouts
        self.defaultLayoutName = defaultLayoutName
        self.overlayOpacity = overlayOpacity
        self.overlayBackgroundColor = overlayBackgroundColor
        self.highlightColor = highlightColor
        self.pollIntervalMs = pollIntervalMs
        self.minimumWindowWidth = minimumWindowWidth
        self.minimumWindowHeight = minimumWindowHeight
        self.excludedWindows = excludedWindows
        self.cellHotKeys = cellHotKeys
        self.cellPickerHotKey = cellPickerHotKey
        self.thumbnailCaptureInterval = thumbnailCaptureInterval
    }

    public static var `default`: AppConfig {
        AppConfig(
            activationHotKey: .default,
            layouts: [
                Layout(
                    name: "Fullscreen",
                    quickKey: "z",
                    screens: ScreenConfig(layouts: [
                            ScreenConfig.primaryKey: .stackAll()
                    ])
                ),
                Layout(
                    name: "Half Split",
                    quickKey: "1",
                    screens: ScreenConfig(layouts: [
                            ScreenConfig.primaryKey: .columns([
                                .stackAll(percentage: 50),
                                .empty(percentage: 50)
                            ])
                    ])
                ),
                Layout(
                    name: "Thirds",
                    quickKey: "2",
                    screens: ScreenConfig(layouts: [
                            ScreenConfig.primaryKey: .columns([
                                .stackAll(percentage: 33.33),
                                .empty(percentage: 33.33),
                                .empty(percentage: 33.34)
                            ])
                    ])
                ),
                Layout(
                    name: "Main + Side",
                    quickKey: "3",
                    screens: ScreenConfig(layouts: [
                            ScreenConfig.primaryKey: .columns([
                                .stackAll(percentage: 70),
                                .rows([
                                    .empty(percentage: 50),
                                    .empty(percentage: 50)
                                ])
                            ])
                    ])
                )
            ],
            defaultLayoutName: nil,
            overlayOpacity: 0.95,
            overlayBackgroundColor: "#1a1a2e",
            highlightColor: "#4a9eff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200,
            cellPickerHotKey: .defaultCellPicker
        )
    }
}
