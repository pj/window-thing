import Testing
import Yams
@testable import WindowThingCore

@Suite("Config Parsing Tests")
struct ConfigParsingTests {

    // MARK: - Layout Node Decoding

    @Test("Decode empty layout node")
    func decodeEmptyLayoutNode() throws {
        let yaml = """
        type: empty
        percentage: 50
        """
        let decoder = YAMLDecoder()
        let node = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(node.type == .empty)
        #expect(node.percentage == 50)
    }

    @Test("Decode pinned layout node")
    func decodePinnedLayoutNode() throws {
        let yaml = """
        type: pinned
        percentage: 60
        pinned:
          application: Code
          bundleId: com.microsoft.VSCode
        """
        let decoder = YAMLDecoder()
        let node = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(node.type == .pinned)
        #expect(node.percentage == 60)
        #expect(node.pinned != nil)
        #expect(node.pinned?.application == "Code")
        #expect(node.pinned?.bundleId == "com.microsoft.VSCode")
    }

    @Test("Decode columns layout node")
    func decodeColumnsLayoutNode() throws {
        let yaml = """
        type: columns
        columns:
          - type: empty
            percentage: 50
          - type: empty
            percentage: 50
        """
        let decoder = YAMLDecoder()
        let node = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(node.type == .columns)
        #expect(node.columns != nil)
        #expect(node.columns?.count == 2)
    }

    @Test("Decode rows layout node")
    func decodeRowsLayoutNode() throws {
        let yaml = """
        type: rows
        rows:
          - type: pinned
            percentage: 60
            pinned:
              application: Terminal
          - type: pinned
            percentage: 40
            pinned:
              application: Safari
        """
        let decoder = YAMLDecoder()
        let node = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(node.type == .rows)
        #expect(node.rows != nil)
        #expect(node.rows?.count == 2)
        #expect(node.rows?[0].pinned?.application == "Terminal")
    }

    @Test("Decode stack layout node")
    func decodeStackLayoutNode() throws {
        let yaml = """
        type: stack
        windows:
          - application: Safari
          - application: Finder
        """
        let decoder = YAMLDecoder()
        let node = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(node.type == .stack)
        #expect(node.windows != nil)
        #expect(node.windows?.count == 2)
    }

    @Test("Decode float zoomed layout node")
    func decodeFloatZoomedLayoutNode() throws {
        let yaml = """
        type: float_zoomed
        layout:
          type: columns
          columns:
            - type: empty
              percentage: 50
            - type: empty
              percentage: 50
        floats:
          - application: Finder
        zoomed:
          - application: Safari
        """
        let decoder = YAMLDecoder()
        let node = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(node.type == .floatZoomed)
        #expect(node.layout != nil)
        #expect(node.layout?.value.type == .columns)
        #expect(node.floats != nil)
        #expect(node.floats?.count == 1)
        #expect(node.zoomed != nil)
        #expect(node.zoomed?.count == 1)
    }

    @Test("Decode nested layout")
    func decodeNestedLayout() throws {
        let yaml = """
        type: columns
        columns:
          - type: pinned
            percentage: 60
            pinned:
              bundleId: com.microsoft.VSCode
          - type: rows
            percentage: 40
            rows:
              - type: pinned
                percentage: 50
                pinned:
                  application: Terminal
              - type: pinned
                percentage: 50
                pinned:
                  application: Safari
        """
        let decoder = YAMLDecoder()
        let node = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(node.type == .columns)
        #expect(node.columns?.count == 2)
        #expect(node.columns?[1].type == .rows)
        #expect(node.columns?[1].rows?.count == 2)
    }

    // MARK: - Screen Config Decoding

    @Test("Decode screen config")
    func decodeScreenConfig() throws {
        let yaml = """
        layouts:
          $PRIMARY:
            type: columns
            columns:
              - type: empty
                percentage: 50
              - type: empty
                percentage: 50
        """
        let decoder = YAMLDecoder()
        let config = try decoder.decode(ScreenConfig.self, from: yaml)

        #expect(config.layouts.keys.contains(ScreenConfig.primaryKey))
        #expect(config.layouts[ScreenConfig.primaryKey]?.type == .columns)
    }

    @Test("Decode screen config multiple monitors")
    func decodeScreenConfigMultipleMonitors() throws {
        let yaml = """
        layouts:
          $PRIMARY:
            type: pinned
            pinned:
              application: Code
          "External Display":
            type: columns
            columns:
              - type: empty
                percentage: 50
              - type: empty
                percentage: 50
        """
        let decoder = YAMLDecoder()
        let config = try decoder.decode(ScreenConfig.self, from: yaml)

        #expect(config.layouts.count == 2)
        #expect(config.layouts.keys.contains("External Display"))
    }

    // MARK: - Full Layout Decoding

    @Test("Decode layout")
    func decodeLayout() throws {
        let yaml = """
        id: 123e4567-e89b-12d3-a456-426614174000
        name: "My Layout"
        quickKey: "1"
        screenSets:
          - layouts:
              $PRIMARY:
                type: empty
        """
        let decoder = YAMLDecoder()
        let layout = try decoder.decode(Layout.self, from: yaml)

        #expect(layout.name == "My Layout")
        #expect(layout.quickKey == "1")
        // Old configs still decode: a screenSets list collapses to one map.
        #expect(layout.screens.layouts.count == 1)
    }

    // MARK: - Migration from screen sets

    @Test("An old config's screen sets collapse to the most specific one")
    func oldScreenSetsCollapse() throws {
        // The list existed to be chosen between, and there is nothing to choose
        // any more. The set naming the most displays is kept — that is what the
        // old matcher preferred with everything plugged in, so a full setup
        // keeps the arrangement it had.
        let yaml = """
        name: Legacy
        quickKey: "9"
        screenSets:
          - layouts:
              $PRIMARY:
                type: stack
          - layouts:
              $PRIMARY:
                type: columns
                columns:
                  - type: stack
                    percentage: 50
                  - type: empty
                    percentage: 50
              External Display:
                type: empty
        """
        let layout = try YAMLDecoder().decode(Layout.self, from: yaml)

        #expect(layout.name == "Legacy")
        #expect(layout.screens.layouts.count == 2)
        #expect(layout.screens.layouts[ScreenConfig.primaryKey]?.type == .columns)
        #expect(layout.screens.layouts["External Display"]?.type == .empty)
    }

    @Test("A config written in the new shape decodes as itself")
    func newShapeDecodes() throws {
        let yaml = """
        name: Modern
        screens:
          layouts:
            $PRIMARY:
              type: stack
        """
        let layout = try YAMLDecoder().decode(Layout.self, from: yaml)
        #expect(layout.screens.layouts[ScreenConfig.primaryKey]?.type == .stack)
    }

    @Test("Encoding writes the new shape and never the old list")
    func encodingDropsTheOldShape() throws {
        let layout = Layout(
            name: "Round Trip",
            screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        )
        let yaml = try YAMLEncoder().encode(layout)
        #expect(yaml.contains("screens:"))
        #expect(!yaml.contains("screenSets:"))

        let back = try YAMLDecoder().decode(Layout.self, from: yaml)
        #expect(back.screens == layout.screens)
        #expect(back.id == layout.id)
    }

    // MARK: - Full Config Decoding

    @Test("Decode app config")
    func decodeAppConfig() throws {
        let yaml = """
        activationHotKey:
          keyCode: 49
          modifiers:
            - command
            - shift
        layouts:
          - id: 123e4567-e89b-12d3-a456-426614174000
            name: "Half Split"
            quickKey: "1"
            screenSets:
              - layouts:
                  $PRIMARY:
                    type: columns
                    columns:
                      - type: empty
                        percentage: 50
                      - type: empty
                        percentage: 50
        overlayOpacity: 0.95
        overlayBackgroundColor: "#1a1a2e"
        highlightColor: "#4a9eff"
        pollIntervalMs: 500
        minimumWindowWidth: 200
        minimumWindowHeight: 200
        """
        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yaml)

        #expect(config.activationHotKey.keyCode == 49)
        #expect(config.activationHotKey.modifiers == ["command", "shift"])
        #expect(config.layouts.count == 1)
        #expect(config.layouts[0].name == "Half Split")
        #expect(config.overlayOpacity == 0.95)
        #expect(config.pollIntervalMs == 500)
    }

    @Test("Decode app config with default layout name")
    func decodeAppConfigWithDefaultLayoutName() throws {
        let yaml = """
        activationHotKey:
          keyCode: 13
          modifiers:
            - control
            - option
        layouts: []
        defaultLayoutName: "Coding"
        overlayOpacity: 0.9
        overlayBackgroundColor: "#000000"
        highlightColor: "#ffffff"
        pollIntervalMs: 1000
        minimumWindowWidth: 100
        minimumWindowHeight: 100
        """
        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yaml)

        #expect(config.defaultLayoutName == "Coding")
    }

    // MARK: - Encoding

    @Test("Encode layout node")
    func encodeLayoutNode() throws {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .pinned(app: "Terminal", percentage: 50)
        ])

        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(node)

        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(LayoutNode.self, from: yaml)

        #expect(decoded.type == .columns)
        #expect(decoded.columns?.count == 2)
        #expect(decoded.columns?[0].type == .empty)
        #expect(decoded.columns?[1].type == .pinned)
    }

    @Test("Encode app config")
    func encodeAppConfig() throws {
        let config = AppConfig.default

        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(config)

        let decoder = YAMLDecoder()
        let decoded = try decoder.decode(AppConfig.self, from: yaml)

        #expect(decoded.layouts.count == config.layouts.count)
        #expect(decoded.overlayOpacity == config.overlayOpacity)
    }

    // MARK: - Saved Setup Decoding

    @Test("Decode saved setup")
    func decodeSavedSetup() throws {
        let yaml = """
        id: 123e4567-e89b-12d3-a456-426614174000
        name: "Work Setup"
        createdAt: 2024-01-15T10:30:00Z
        windows:
          - application: "Code"
            bundleId: "com.microsoft.VSCode"
            windowTitle: "main.swift"
            frame:
              x: 0
              y: 0
              width: 960
              height: 1080
            displayName: "Main Display"
        """
        let decoder = YAMLDecoder()
        let setup = try decoder.decode(SavedSetup.self, from: yaml)

        #expect(setup.name == "Work Setup")
        #expect(setup.windows.count == 1)
        #expect(setup.windows[0].application == "Code")
        #expect(setup.windows[0].frame.width == 960)
    }

    // MARK: - Error Handling

    @Test("Decode invalid layout type")
    func decodeInvalidLayoutType() {
        let yaml = """
        type: invalid_type
        """
        let decoder = YAMLDecoder()

        #expect(throws: (any Error).self) {
            try decoder.decode(LayoutNode.self, from: yaml)
        }
    }

    @Test("Decode empty yaml")
    func decodeEmptyYaml() {
        let yaml = ""
        let decoder = YAMLDecoder()

        #expect(throws: (any Error).self) {
            try decoder.decode(AppConfig.self, from: yaml)
        }
    }

    // MARK: - Pinned Config Edge Cases

    @Test("Decode pinned config all fields")
    func decodePinnedConfigAllFields() throws {
        let yaml = """
        application: "Safari"
        bundleId: "com.apple.Safari"
        windowTitle: "Apple"
        """
        let decoder = YAMLDecoder()
        let config = try decoder.decode(PinnedConfig.self, from: yaml)

        #expect(config.application == "Safari")
        #expect(config.bundleId == "com.apple.Safari")
        #expect(config.windowTitles == ["Apple"]) // backward-compat: old windowTitle key decodes to windowTitles
    }

    @Test("Decode pinned config only bundle ID")
    func decodePinnedConfigOnlyBundleId() throws {
        let yaml = """
        bundleId: "com.apple.Safari"
        """
        let decoder = YAMLDecoder()
        let config = try decoder.decode(PinnedConfig.self, from: yaml)

        #expect(config.application == nil)
        #expect(config.bundleId == "com.apple.Safari")
        #expect(config.windowTitles == nil)
    }

    @Test("Decode pinned config only application")
    func decodePinnedConfigOnlyApplication() throws {
        let yaml = """
        application: "Terminal"
        """
        let decoder = YAMLDecoder()
        let config = try decoder.decode(PinnedConfig.self, from: yaml)

        #expect(config.application == "Terminal")
        #expect(config.bundleId == nil)
    }
}
