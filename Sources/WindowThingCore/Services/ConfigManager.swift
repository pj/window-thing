import Foundation
import Yams

public class ConfigManager: ConfigProviding {
    public static let shared = ConfigManager()

    public private(set) var config: AppConfig = .default

    public var configFilePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configDir = appSupport.appendingPathComponent("WindowThing")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        return configDir.appendingPathComponent("config.yaml")
    }

    public var setupsFilePath: URL {
        configFilePath.deletingLastPathComponent().appendingPathComponent("setups.yaml")
    }

    private init() {}

    public func loadConfig() {
        // Create default config if doesn't exist
        if !FileManager.default.fileExists(atPath: configFilePath.path) {
            saveConfig()
            return
        }

        do {
            let yamlString = try String(contentsOf: configFilePath, encoding: .utf8)
            let decoder = YAMLDecoder()
            config = try decoder.decode(AppConfig.self, from: yamlString)
        } catch {
            print("Error loading config: \(error)")
            print("Using default configuration")
            config = .default
        }
    }

    public func saveConfig() {
        do {
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(config)

            // Add helpful header comment
            let header = """
            # WindowThing Configuration
            # -------------------------
            # Edit this file to customize WindowThing behavior.
            # Changes take effect after reloading (menubar > Reload Config).
            #
            # Hotkey modifiers: command, option, control, shift
            # Key codes: See https://eastmanreference.com/complete-list-of-applescript-key-codes
            #
            # Layout types:
            #   - empty: Placeholder for next available window
            #   - pinned: Pin specific app to location
            #   - columns: Horizontal split
            #   - rows: Vertical split
            #   - stack: Multiple windows in same space
            #     - stackRemaining: true  # Stacks ALL remaining windows here
            #   - float_zoomed: Floating + zoomed windows
            #
            # excludedWindows: windows layouts should leave alone. Menus and
            # popovers are skipped automatically; this is for real windows that
            # look like any other, such as Finder's Get Info. Every field given
            # must match. Omit the key for the built-in defaults; set it to []
            # to manage everything.
            #
            #   excludedWindows:
            #     - bundleId: com.apple.finder
            #       titleContains: " Info"
            #     - application: Photos

            """

            try (header + yamlString).write(to: configFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving config: \(error)")
        }
    }

    public func updateConfig(_ newConfig: AppConfig) {
        config = newConfig
        saveConfig()
    }

    /// Persist an updated layout list to disk, leaving all other config fields unchanged.
    public func saveLayouts(_ layouts: [Layout]) {
        var updated = config
        updated = AppConfig(
            activationHotKey: updated.activationHotKey,
            layouts: layouts,
            defaultLayoutName: updated.defaultLayoutName,
            overlayOpacity: updated.overlayOpacity,
            overlayBackgroundColor: updated.overlayBackgroundColor,
            highlightColor: updated.highlightColor,
            pollIntervalMs: updated.pollIntervalMs,
            minimumWindowWidth: updated.minimumWindowWidth,
            minimumWindowHeight: updated.minimumWindowHeight,
            excludedWindows: updated.excludedWindows,
            cellHotKeys: updated.cellHotKeys,
            cellPickerHotKey: updated.cellPickerHotKey,
            thumbnailCaptureInterval: updated.thumbnailCaptureInterval
        )
        config = updated
        saveConfig()
    }
}


// MARK: - Example Config Generation

extension ConfigManager {
    func generateExampleConfig() -> String {
        return """
        # WindowThing Configuration
        # -------------------------

        # Global hotkey to activate WindowThing
        activationHotKey:
          keyCode: 49  # Space
          modifiers:
            - command
            - shift

        # Visual settings
        overlayOpacity: 0.95
        overlayBackgroundColor: "#1a1a2e"
        highlightColor: "#4a9eff"

        # Behavior
        pollIntervalMs: 500
        minimumWindowSize:
          width: 200
          height: 200

        # Default layout to apply on startup (optional)
        defaultLayoutName: null

        # Layout definitions
        layouts:
          - name: "Half Split"
            quickKey: "1"
            screens:
              layouts:
                $PRIMARY:
                  type: columns
                  columns:
                    - type: empty
                      percentage: 50
                    - type: empty
                      percentage: 50

          - name: "Thirds"
            quickKey: "2"
            screens:
              layouts:
                $PRIMARY:
                  type: columns
                  columns:
                    - type: empty
                      percentage: 33.33
                    - type: empty
                      percentage: 33.33
                    - type: empty
                      percentage: 33.34

          - name: "Main + Side"
            quickKey: "3"
            screens:
              layouts:
                $PRIMARY:
                  type: columns
                  columns:
                    - type: empty
                      percentage: 70
                    - type: rows
                      rows:
                        - type: empty
                          percentage: 50
                        - type: empty
                          percentage: 50

          - name: "Coding Layout"
            quickKey: "c"
            screens:
              layouts:
                $PRIMARY:
                  type: columns
                  columns:
                    - type: pinned
                      percentage: 60
                      pinned:
                        application: "Code"
                        bundleId: "com.microsoft.VSCode"
                    - type: rows
                      percentage: 40
                      rows:
                        - type: pinned
                          percentage: 60
                          pinned:
                            application: "Terminal"
                        - type: pinned
                          percentage: 40
                          pinned:
                            application: "Safari"

          - name: "Focus + Stack"
            quickKey: "s"
            screens:
              layouts:
                $PRIMARY:
                  type: columns
                  columns:
                    - type: empty
                      percentage: 70
                    - type: stack
                      percentage: 30
                      stackRemaining: true  # All other windows stacked here
        """
    }
}
