import Testing
@testable import WindowThingCore

@Suite("Screen modification")
struct ScreenSetModificationTests {

    // MARK: - Add Display

    @Test("Add display key to empty screen config")
    func addDisplayToEmpty() {
        let config = ScreenConfig(layouts: [:])
        let result = ScreenModification.addDisplay(key: "External Display", to: config)
        #expect(result.layouts.count == 1)
        #expect(result.layouts["External Display"] == .stackAll())
    }

    @Test("Add display key to existing screen config with $PRIMARY")
    func addDisplayAlongsidePrimary() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .pinned(app: "Xcode")
        ])
        let result = ScreenModification.addDisplay(key: "External Display", to: config)
        #expect(result.layouts.count == 2)
        #expect(result.layouts[ScreenConfig.primaryKey] == .pinned(app: "Xcode"))
        #expect(result.layouts["External Display"] == .stackAll())
    }

    @Test("Add duplicate display key replaces layout node")
    func addDuplicateKeyReplaces() {
        let config = ScreenConfig(layouts: [
            "External Display": .pinned(app: "Safari")
        ])
        let newNode = LayoutNode.columns([.empty(percentage: 50), .empty(percentage: 50)])
        let result = ScreenModification.addDisplay(key: "External Display", defaultNode: newNode, to: config)
        #expect(result.layouts.count == 1)
        #expect(result.layouts["External Display"] == newNode)
    }

    @Test("Add display with custom node uses provided node")
    func addDisplayCustomNode() {
        let config = ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        let customNode = LayoutNode.columns([
            .pinned(app: "Terminal", percentage: 50),
            .pinned(app: "Safari", percentage: 50)
        ])
        let result = ScreenModification.addDisplay(key: "Left Monitor", defaultNode: customNode, to: config)
        #expect(result.layouts["Left Monitor"] == customNode)
    }

    // MARK: - Remove Display

    @Test("Remove existing display key")
    func removeExistingKey() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External Display": .pinned(app: "Safari")
        ])
        let result = ScreenModification.removeDisplay(key: "External Display", from: config)
        #expect(result != nil)
        #expect(result!.layouts.count == 1)
        #expect(result!.layouts[ScreenConfig.primaryKey] == .stackAll())
    }

    @Test("Remove non-existent key returns nil")
    func removeNonExistentKey() {
        let config = ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        let result = ScreenModification.removeDisplay(key: "Unknown", from: config)
        #expect(result == nil)
    }

    @Test("Remove $PRIMARY key is allowed")
    func removePrimaryKey() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External Display": .pinned(app: "Safari")
        ])
        let result = ScreenModification.removeDisplay(key: ScreenConfig.primaryKey, from: config)
        #expect(result != nil)
        #expect(result!.layouts.count == 1)
        #expect(result!.layouts["External Display"] != nil)
    }

    // MARK: - Rename Display

    @Test("Rename display key preserves layout node")
    func renamePreservesNode() {
        let node = LayoutNode.columns([.pinned(app: "Terminal", percentage: 50), .empty(percentage: 50)])
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "Old Name": node
        ])
        let result = ScreenModification.renameDisplay(from: "Old Name", to: "New Name", in: config)
        #expect(result != nil)
        #expect(result!.layouts["Old Name"] == nil)
        #expect(result!.layouts["New Name"] == node)
        #expect(result!.layouts[ScreenConfig.primaryKey] == .stackAll())
    }

    @Test("Rename non-existent key returns nil")
    func renameNonExistent() {
        let config = ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        let result = ScreenModification.renameDisplay(from: "Unknown", to: "New", in: config)
        #expect(result == nil)
    }

    @Test("Rename to existing key returns nil (conflict)")
    func renameConflict() {
        let config = ScreenConfig(layouts: [
            "Display A": .stackAll(),
            "Display B": .pinned(app: "Safari")
        ])
        let result = ScreenModification.renameDisplay(from: "Display A", to: "Display B", in: config)
        #expect(result == nil)
    }

    @Test("Rename $PRIMARY key is allowed")
    func renamePrimary() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External Display": .pinned(app: "Safari")
        ])
        let result = ScreenModification.renameDisplay(from: ScreenConfig.primaryKey, to: "Main Monitor", in: config)
        #expect(result != nil)
        #expect(result!.layouts[ScreenConfig.primaryKey] == nil)
        #expect(result!.layouts["Main Monitor"] == .stackAll())
    }

    // MARK: - Default Display Node

    @Test("Default node is stackAll")
    func defaultNode() {
        #expect(ScreenModification.defaultDisplayNode == .stackAll())
    }

    // MARK: - Layout Convenience Extensions
    //
    // No index any more: a layout has one display map, so there is nothing to
    // pick between when adding, removing or renaming a display.

    @Test("Layout addingDisplay adds a key to the layout's one map")
    func layoutAddDisplay() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        )
        let result = layout.addingDisplay(key: "External Display")
        #expect(result.screens.layouts.count == 2)
        #expect(result.screens.layouts["External Display"] == .stackAll())
    }

    @Test("Adding a display to a layout with no map starts one")
    func layoutAddDisplayToEmpty() {
        // There is no longer an index to get wrong, so this cannot fail.
        let result = Layout(name: "Test").addingDisplay(key: "External")
        #expect(result.screens.layouts["External"] == .stackAll())
    }

    @Test("Layout removingDisplay takes a key out")
    func layoutRemoveDisplay() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                "External Display": .pinned(app: "Safari")
            ])
        )
        let result = layout.removingDisplay(key: "External Display")
        #expect(result != nil)
        #expect(result!.screens.layouts.count == 1)
    }

    @Test("Layout renamingDisplay moves a key, keeping its tree")
    func layoutRenameDisplay() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                "Old Monitor": .pinned(app: "Safari")
            ])
        )
        let result = layout.renamingDisplay(from: "Old Monitor", to: "New Monitor")
        #expect(result != nil)
        #expect(result!.screens.layouts["Old Monitor"] == nil)
        #expect(result!.screens.layouts["New Monitor"] == .pinned(app: "Safari"))
    }
}
