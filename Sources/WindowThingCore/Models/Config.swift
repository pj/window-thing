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
        minimumWindowHeight: CGFloat
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
    }

    public static var `default`: AppConfig {
        AppConfig(
            activationHotKey: .default,
            layouts: [
                Layout(
                    name: "Half Split",
                    quickKey: "1",
                    screenSets: [
                        ScreenConfig(layouts: [
                            ScreenConfig.primaryKey: .columns([
                                .empty(percentage: 50),
                                .empty(percentage: 50)
                            ])
                        ])
                    ]
                ),
                Layout(
                    name: "Thirds",
                    quickKey: "2",
                    screenSets: [
                        ScreenConfig(layouts: [
                            ScreenConfig.primaryKey: .columns([
                                .empty(percentage: 33.33),
                                .empty(percentage: 33.33),
                                .empty(percentage: 33.34)
                            ])
                        ])
                    ]
                ),
                Layout(
                    name: "Main + Side",
                    quickKey: "3",
                    screenSets: [
                        ScreenConfig(layouts: [
                            ScreenConfig.primaryKey: .columns([
                                .empty(percentage: 70),
                                .rows([
                                    .empty(percentage: 50),
                                    .empty(percentage: 50)
                                ])
                            ])
                        ])
                    ]
                )
            ],
            defaultLayoutName: nil,
            overlayOpacity: 0.95,
            overlayBackgroundColor: "#1a1a2e",
            highlightColor: "#4a9eff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )
    }
}
