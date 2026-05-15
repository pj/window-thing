import Testing
@testable import WindowThingCore

@Suite("Screen Set Modification")
struct ScreenSetModificationTests {

    // MARK: - Add Display

    @Test("Add display key to empty screen config")
    func addDisplayToEmpty() {
        let config = ScreenConfig(layouts: [:])
        let result = ScreenSetModification.addDisplay(key: "External Display", to: config)
        #expect(result.layouts.count == 1)
        #expect(result.layouts["External Display"] == .stackAll())
    }

    @Test("Add display key to existing screen config with $PRIMARY")
    func addDisplayAlongsidePrimary() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .pinned(app: "Xcode")
        ])
        let result = ScreenSetModification.addDisplay(key: "External Display", to: config)
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
        let result = ScreenSetModification.addDisplay(key: "External Display", defaultNode: newNode, to: config)
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
        let result = ScreenSetModification.addDisplay(key: "Left Monitor", defaultNode: customNode, to: config)
        #expect(result.layouts["Left Monitor"] == customNode)
    }

    // MARK: - Remove Display

    @Test("Remove existing display key")
    func removeExistingKey() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External Display": .pinned(app: "Safari")
        ])
        let result = ScreenSetModification.removeDisplay(key: "External Display", from: config)
        #expect(result != nil)
        #expect(result!.layouts.count == 1)
        #expect(result!.layouts[ScreenConfig.primaryKey] == .stackAll())
    }

    @Test("Remove non-existent key returns nil")
    func removeNonExistentKey() {
        let config = ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        let result = ScreenSetModification.removeDisplay(key: "Unknown", from: config)
        #expect(result == nil)
    }

    @Test("Remove $PRIMARY key is allowed")
    func removePrimaryKey() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External Display": .pinned(app: "Safari")
        ])
        let result = ScreenSetModification.removeDisplay(key: ScreenConfig.primaryKey, from: config)
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
        let result = ScreenSetModification.renameDisplay(from: "Old Name", to: "New Name", in: config)
        #expect(result != nil)
        #expect(result!.layouts["Old Name"] == nil)
        #expect(result!.layouts["New Name"] == node)
        #expect(result!.layouts[ScreenConfig.primaryKey] == .stackAll())
    }

    @Test("Rename non-existent key returns nil")
    func renameNonExistent() {
        let config = ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        let result = ScreenSetModification.renameDisplay(from: "Unknown", to: "New", in: config)
        #expect(result == nil)
    }

    @Test("Rename to existing key returns nil (conflict)")
    func renameConflict() {
        let config = ScreenConfig(layouts: [
            "Display A": .stackAll(),
            "Display B": .pinned(app: "Safari")
        ])
        let result = ScreenSetModification.renameDisplay(from: "Display A", to: "Display B", in: config)
        #expect(result == nil)
    }

    @Test("Rename $PRIMARY key is allowed")
    func renamePrimary() {
        let config = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External Display": .pinned(app: "Safari")
        ])
        let result = ScreenSetModification.renameDisplay(from: ScreenConfig.primaryKey, to: "Main Monitor", in: config)
        #expect(result != nil)
        #expect(result!.layouts[ScreenConfig.primaryKey] == nil)
        #expect(result!.layouts["Main Monitor"] == .stackAll())
    }

    // MARK: - Default Display Node

    @Test("Default node is stackAll")
    func defaultNode() {
        #expect(ScreenSetModification.defaultDisplayNode == .stackAll())
    }

    // MARK: - Layout Convenience Extensions

    @Test("Layout addingDisplay to specific screen set")
    func layoutAddDisplay() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])]
        )
        let result = layout.addingDisplay(key: "External Display", toScreenSetAt: 0)
        #expect(result != nil)
        #expect(result!.screenSets[0].layouts.count == 2)
        #expect(result!.screenSets[0].layouts["External Display"] == .stackAll())
    }

    @Test("Layout addingDisplay with invalid index returns nil")
    func layoutAddDisplayInvalidIndex() {
        let layout = Layout(name: "Test", screenSets: [])
        let result = layout.addingDisplay(key: "External", toScreenSetAt: 0)
        #expect(result == nil)
    }

    @Test("Layout removingDisplay from specific screen set")
    func layoutRemoveDisplay() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                "External Display": .pinned(app: "Safari")
            ])]
        )
        let result = layout.removingDisplay(key: "External Display", fromScreenSetAt: 0)
        #expect(result != nil)
        #expect(result!.screenSets[0].layouts.count == 1)
    }

    @Test("Layout renamingDisplay in specific screen set")
    func layoutRenameDisplay() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                "Old Monitor": .pinned(app: "Safari")
            ])]
        )
        let result = layout.renamingDisplay(from: "Old Monitor", to: "New Monitor", inScreenSetAt: 0)
        #expect(result != nil)
        #expect(result!.screenSets[0].layouts["Old Monitor"] == nil)
        #expect(result!.screenSets[0].layouts["New Monitor"] == .pinned(app: "Safari"))
    }
}
