import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Layout Modification - Extended Coverage")
struct LayoutModificationExtendedTests {

    // MARK: - leafCount

    @Test("leafCount of single leaf node is 1")
    func leafCountSingleLeaf() {
        #expect(LayoutNode.empty().leafCount == 1)
        #expect(LayoutNode.pinned(app: "Terminal").leafCount == 1)
        #expect(LayoutNode(type: .stack, percentage: 100).leafCount == 1)
    }

    @Test("leafCount of columns node counts all leaves")
    func leafCountColumns() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        #expect(node.leafCount == 2)
    }

    @Test("leafCount of nested structure counts all leaves recursively")
    func leafCountNested() {
        let node = LayoutNode.columns([
            .rows([
                .empty(percentage: 50),
                .empty(percentage: 50)
            ]),
            .empty(percentage: 50),
            .rows([
                .empty(percentage: 33),
                .empty(percentage: 33),
                .empty(percentage: 34)
            ])
        ])
        // 2 + 1 + 3 = 6
        #expect(node.leafCount == 6)
    }

    // MARK: - leafIndex(at:)

    @Test("leafIndex at root leaf returns 1")
    func leafIndexAtRoot() {
        let node = LayoutNode.empty()
        #expect(node.leafIndex(at: NodePath([])) == 1)
    }

    @Test("leafIndex at first column child returns 1")
    func leafIndexFirstChild() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        #expect(node.leafIndex(at: NodePath([0])) == 1)
        #expect(node.leafIndex(at: NodePath([1])) == 2)
    }

    @Test("leafIndex with nested structure counts preceding leaves")
    func leafIndexNested() {
        let node = LayoutNode.columns([
            .rows([
                .empty(percentage: 50),
                .empty(percentage: 50)
            ]),
            .empty(percentage: 50)
        ])
        // First row's first child = leaf 1
        #expect(node.leafIndex(at: NodePath([0, 0])) == 1)
        // First row's second child = leaf 2
        #expect(node.leafIndex(at: NodePath([0, 1])) == 2)
        // Second column = leaf 3 (after 2 leaves in first column)
        #expect(node.leafIndex(at: NodePath([1])) == 3)
    }

    @Test("leafIndex for non-leaf path returns nil")
    func leafIndexNonLeaf() {
        let node = LayoutNode.columns([
            .rows([
                .empty(percentage: 50),
                .empty(percentage: 50)
            ]),
            .empty(percentage: 50)
        ])
        // Path [0] points to a rows node, not a leaf
        #expect(node.leafIndex(at: NodePath([0])) == nil)
    }

    @Test("leafIndex for out-of-bounds path returns nil")
    func leafIndexOutOfBounds() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        #expect(node.leafIndex(at: NodePath([5])) == nil)
    }

    @Test("leafIndex for path going deeper than leaf returns nil")
    func leafIndexTooDeep() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        // [0, 0] tries to go into an empty leaf
        #expect(node.leafIndex(at: NodePath([0, 0])) == nil)
    }

    // MARK: - withPercentage

    @Test("withPercentage returns copy with new percentage")
    func withPercentage() {
        let node = LayoutNode.empty(percentage: 50)
        let result = node.withPercentage(75)
        #expect(result.percentage == 75)
        #expect(result.type == .empty)
    }

    @Test("withPercentage preserves pinned config")
    func withPercentagePreservesPinned() {
        let node = LayoutNode.pinned(app: "Terminal", percentage: 50)
        let result = node.withPercentage(30)
        #expect(result.percentage == 30)
        #expect(result.type == .pinned)
        #expect(result.pinned?.application == "Terminal")
    }

    // MARK: - withColumns

    @Test("withColumns converts node to columns type")
    func withColumns() {
        let node = LayoutNode.empty(percentage: 60)
        let children = [LayoutNode.empty(percentage: 50), LayoutNode.empty(percentage: 50)]
        let result = node.withColumns(children)
        #expect(result.type == .columns)
        #expect(result.percentage == 60)
        #expect(result.columns?.count == 2)
    }

    // MARK: - withRows

    @Test("withRows converts node to rows type")
    func withRows() {
        let node = LayoutNode.empty(percentage: 40)
        let children = [LayoutNode.empty(percentage: 50), LayoutNode.pinned(app: "Safari", percentage: 50)]
        let result = node.withRows(children)
        #expect(result.type == .rows)
        #expect(result.percentage == 40)
        #expect(result.rows?.count == 2)
    }

    // MARK: - withType

    @Test("withType converts empty to stack")
    func withTypeEmptyToStack() {
        let node = LayoutNode.empty(percentage: 50)
        let result = node.withType(.stack)
        #expect(result.type == .stack)
        #expect(result.percentage == 50)
    }

    @Test("withType to pinned preserves pinned config")
    func withTypeToPinnedPreservesConfig() {
        let node = LayoutNode.pinned(app: "Terminal", percentage: 30)
        let result = node.withType(.pinned)
        #expect(result.type == .pinned)
        #expect(result.pinned?.application == "Terminal")
        #expect(result.percentage == 30)
    }

    @Test("withType to non-pinned clears pinned config")
    func withTypeToNonPinnedClearsConfig() {
        let node = LayoutNode.pinned(app: "Terminal", percentage: 30)
        let result = node.withType(.empty)
        #expect(result.type == .empty)
        #expect(result.pinned == nil)
        #expect(result.percentage == 30)
    }

    @Test("withType clears columns/rows children")
    func withTypeClearsChildren() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let result = node.withType(.empty)
        #expect(result.type == .empty)
        #expect(result.columns == nil)
    }

    // MARK: - appendTrailingColumn

    @Test("appendTrailingColumn to columns node adds column with equal percentages")
    func appendColumnToColumnsNode() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let result = LayoutModification.appendTrailingColumn(to: node)
        #expect(result.type == .columns)
        #expect(result.columns?.count == 3)
        // All should be ~33.3%
        for col in result.columns ?? [] {
            #expect(abs((col.percentage ?? 0) - 100.0/3.0) < 0.01)
        }
    }

    @Test("appendTrailingColumn to leaf wraps in 2 columns at 50/50")
    func appendColumnToLeaf() {
        let node = LayoutNode.pinned(app: "Terminal", percentage: 100)
        let result = LayoutModification.appendTrailingColumn(to: node)
        #expect(result.type == .columns)
        #expect(result.columns?.count == 2)
        #expect(result.columns?[0].type == .pinned)
        #expect(result.columns?[0].pinned?.application == "Terminal")
        #expect(result.columns?[0].percentage == 50)
        #expect(result.columns?[1].type == .stack)
        #expect(result.columns?[1].percentage == 50)
    }

    @Test("appendTrailingColumn to rows node wraps in 2 columns")
    func appendColumnToRowsNode() {
        let node = LayoutNode.rows([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let result = LayoutModification.appendTrailingColumn(to: node)
        #expect(result.type == .columns)
        #expect(result.columns?.count == 2)
        #expect(result.columns?[0].type == .rows)
        #expect(result.columns?[0].rows?.count == 2)
    }

    @Test("appendTrailingColumn with custom newNode")
    func appendColumnCustomNode() {
        let node = LayoutNode.empty()
        let result = LayoutModification.appendTrailingColumn(
            to: node,
            newNode: .pinned(app: "Safari")
        )
        #expect(result.columns?.count == 2)
        #expect(result.columns?[1].type == .pinned)
        #expect(result.columns?[1].pinned?.application == "Safari")
    }

    // MARK: - appendTrailingRow

    @Test("appendTrailingRow to rows node adds row with equal percentages")
    func appendRowToRowsNode() {
        let node = LayoutNode.rows([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let result = LayoutModification.appendTrailingRow(to: node)
        #expect(result.type == .rows)
        #expect(result.rows?.count == 3)
        for row in result.rows ?? [] {
            #expect(abs((row.percentage ?? 0) - 100.0/3.0) < 0.01)
        }
    }

    @Test("appendTrailingRow to leaf wraps in 2 rows at 50/50")
    func appendRowToLeaf() {
        let node = LayoutNode.pinned(app: "Terminal", percentage: 100)
        let result = LayoutModification.appendTrailingRow(to: node)
        #expect(result.type == .rows)
        #expect(result.rows?.count == 2)
        #expect(result.rows?[0].type == .pinned)
        #expect(result.rows?[0].pinned?.application == "Terminal")
        #expect(result.rows?[0].percentage == 50)
        #expect(result.rows?[1].type == .stack)
    }

    @Test("appendTrailingRow to columns node wraps in 2 rows")
    func appendRowToColumnsNode() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let result = LayoutModification.appendTrailingRow(to: node)
        #expect(result.type == .rows)
        #expect(result.rows?.count == 2)
        #expect(result.rows?[0].type == .columns)
    }

    // MARK: - canAppendColumn

    @Test("canAppendColumn with 2 columns (adding 3rd = 33%) returns true")
    func canAppendColumn2Existing() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        #expect(LayoutModification.canAppendColumn(to: node) == true)
    }

    @Test("canAppendColumn with 6 columns (adding 7th = 14.3%) returns false")
    func canAppendColumn6Existing() {
        let node = LayoutNode.columns([
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.5)
        ])
        #expect(LayoutModification.canAppendColumn(to: node) == false)
    }

    @Test("canAppendColumn with leaf node (becomes 2 = 50%) returns true")
    func canAppendColumnLeaf() {
        #expect(LayoutModification.canAppendColumn(to: .empty()) == true)
    }

    @Test("canAppendColumn custom minPercentage")
    func canAppendColumnCustomMin() {
        let node = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        // 3 columns = 33.3% each, so min 35% would fail
        #expect(LayoutModification.canAppendColumn(to: node, minPercentage: 35) == false)
        // But min 30% would pass
        #expect(LayoutModification.canAppendColumn(to: node, minPercentage: 30) == true)
    }

    // MARK: - canAppendRow

    @Test("canAppendRow with 2 rows (adding 3rd = 33%) returns true")
    func canAppendRow2Existing() {
        let node = LayoutNode.rows([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        #expect(LayoutModification.canAppendRow(to: node) == true)
    }

    @Test("canAppendRow with 6 rows (adding 7th = 14.3%) returns false")
    func canAppendRow6Existing() {
        let node = LayoutNode.rows([
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.7),
            .empty(percentage: 16.5)
        ])
        #expect(LayoutModification.canAppendRow(to: node) == false)
    }

    @Test("canAppendRow with leaf node (becomes 2 = 50%) returns true")
    func canAppendRowLeaf() {
        #expect(LayoutModification.canAppendRow(to: .empty()) == true)
    }

    // MARK: - Layout.movingApplication(monitor:applicationName:windowTitle:to:)

    @Test("movingApplication moves pinned app to new location")
    func movingApplicationPinnedToNew() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Terminal", percentage: 50),
                    LayoutNode(type: .stack, percentage: 50)
                ])
            ])
        )
        let result = layout.movingApplication(
            monitor: ScreenConfig.primaryKey,
            applicationName: "Terminal",
            windowTitle: nil,
            to: [1]
        )
        #expect(result.changed == true)
        // Terminal should now be at path [1]
        let primary = result.layout.screens.layouts[ScreenConfig.primaryKey]
        let targetNode = primary?.nodeAt(path: [1])
        #expect(targetNode?.type == .pinned)
        #expect(targetNode?.pinned?.application == "Terminal")
    }

    @Test("movingApplication from stack to empty cell")
    func movingApplicationFromStack() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .empty(percentage: 50),
                    LayoutNode(type: .stack, percentage: 50)
                ])
            ])
        )
        // App is in the stack (not pinned anywhere), move to cell [0]
        let result = layout.movingApplication(
            monitor: ScreenConfig.primaryKey,
            applicationName: "Safari",
            windowTitle: nil,
            to: [0]
        )
        #expect(result.changed == true)
        let primary = result.layout.screens.layouts[ScreenConfig.primaryKey]
        let targetNode = primary?.nodeAt(path: [0])
        #expect(targetNode?.type == .pinned)
        #expect(targetNode?.pinned?.application == "Safari")
    }

    @Test("movingApplication with no screen sets returns unchanged")
    func movingApplicationNoScreenSets() {
        let layout = Layout(name: "Empty")
        let result = layout.movingApplication(
            monitor: ScreenConfig.primaryKey,
            applicationName: "Terminal",
            windowTitle: nil,
            to: [0]
        )
        #expect(result.changed == false)
    }

    @Test("movingApplication with invalid monitor returns unchanged")
    func movingApplicationInvalidMonitor() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .empty()
            ])
        )
        let result = layout.movingApplication(
            monitor: "Nonexistent",
            applicationName: "Terminal",
            windowTitle: nil,
            to: [0]
        )
        #expect(result.changed == false)
    }

    @Test("movingApplication from/to with same monitor delegates correctly")
    func movingApplicationFromTo() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Terminal", percentage: 50),
                    LayoutNode(type: .stack, percentage: 50)
                ])
            ])
        )
        let from = LayoutLocation(monitor: ScreenConfig.primaryKey, path: [0])
        let to = LayoutLocation(monitor: ScreenConfig.primaryKey, path: [1])
        let result = layout.movingApplication(
            from: from,
            to: to,
            applicationName: "Terminal",
            windowTitle: nil
        )
        #expect(result.changed == true)
    }

    @Test("movingApplication from/to different monitors returns unchanged")
    func movingApplicationCrossMonitor() {
        let layout = Layout(
            name: "Test",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .empty(),
                "External": .empty()
            ])
        )
        let from = LayoutLocation(monitor: ScreenConfig.primaryKey, path: [])
        let to = LayoutLocation(monitor: "External", path: [])
        let result = layout.movingApplication(
            from: from,
            to: to,
            applicationName: "Terminal",
            windowTitle: nil
        )
        #expect(result.changed == false)
    }
}
