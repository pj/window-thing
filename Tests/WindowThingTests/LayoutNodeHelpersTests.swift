import Testing
import CoreGraphics
@testable import WindowThingCore

// MARK: - withPercentage / withColumns / withRows / withType

@Suite("LayoutNode Mutation Helpers")
struct LayoutNodeMutationTests {

    // MARK: - withPercentage

    @Test("withPercentage preserves type and children")
    func withPercentagePreservesTypeAndChildren() {
        let node = LayoutNode.columns([
            .empty(percentage: 60),
            .empty(percentage: 40)
        ])
        let updated = node.withPercentage(75)
        #expect(updated.percentage == 75)
        #expect(updated.type == .columns)
        #expect(updated.columns?.count == 2)
    }

    @Test("withPercentage on pinned preserves pinned config")
    func withPercentageOnPinnedPreservesPinnedConfig() {
        let node = LayoutNode.pinned(app: "Safari", percentage: 50)
        let updated = node.withPercentage(30)
        #expect(updated.percentage == 30)
        #expect(updated.type == .pinned)
        #expect(updated.pinned?.application == "Safari")
    }

    @Test("withPercentage on stack preserves stackRemaining")
    func withPercentageOnStackPreservesStackRemaining() {
        let node = LayoutNode.stackAll(percentage: 100)
        let updated = node.withPercentage(60)
        #expect(updated.percentage == 60)
        #expect(updated.stackRemaining == true)
    }

    // MARK: - withColumns

    @Test("withColumns sets type to columns and replaces children")
    func withColumnsSetsTypeAndChildren() {
        let original = LayoutNode.empty(percentage: 50)
        let children = [LayoutNode.empty(percentage: 60), LayoutNode.empty(percentage: 40)]
        let result = original.withColumns(children)
        #expect(result.type == .columns)
        #expect(result.columns?.count == 2)
        #expect(result.percentage == 50)  // preserved from original
    }

    @Test("withColumns on existing columns replaces children")
    func withColumnsOnExistingColumnsReplacesChildren() {
        let original = LayoutNode.columns([.empty(percentage: 100)])
        let newChildren = [LayoutNode.empty(percentage: 33), .empty(percentage: 33), .empty(percentage: 34)]
        let result = original.withColumns(newChildren)
        #expect(result.columns?.count == 3)
    }

    // MARK: - withRows

    @Test("withRows sets type to rows and replaces children")
    func withRowsSetsTypeAndChildren() {
        let original = LayoutNode.empty(percentage: 80)
        let children = [LayoutNode.empty(percentage: 70), LayoutNode.empty(percentage: 30)]
        let result = original.withRows(children)
        #expect(result.type == .rows)
        #expect(result.rows?.count == 2)
        #expect(result.percentage == 80)  // preserved from original
    }

    // MARK: - withType

    @Test("withType empty to pinned clears structure")
    func withTypeEmptyToPinned() {
        let node = LayoutNode.empty(percentage: 45)
        let result = node.withType(.pinned)
        #expect(result.type == .pinned)
        #expect(result.percentage == 45)
        #expect(result.columns == nil)
        #expect(result.rows == nil)
    }

    @Test("withType pinned to stack clears pinned config")
    func withTypePinnedToStack() {
        let node = LayoutNode.pinned(app: "Safari", percentage: 60)
        let result = node.withType(.stack)
        #expect(result.type == .stack)
        #expect(result.pinned == nil)
        #expect(result.percentage == 60)
    }

    @Test("withType preserves pinned config when staying pinned")
    func withTypePreservesPinnedConfig() {
        let node = LayoutNode.pinned(app: "Safari", percentage: 50)
        let result = node.withType(.pinned)
        #expect(result.pinned?.application == "Safari")
    }

    @Test("withType pinned to empty clears pinned config")
    func withTypePinnedToEmpty() {
        let node = LayoutNode.pinned(app: "Firefox", percentage: 50)
        let result = node.withType(.empty)
        #expect(result.type == .empty)
        #expect(result.pinned == nil)
    }

    @Test("withType columns to empty clears columns")
    func withTypeColumnsToEmpty() {
        let node = LayoutNode.columns([.empty(percentage: 50), .empty(percentage: 50)])
        let result = node.withType(.empty)
        #expect(result.type == .empty)
        #expect(result.columns == nil)
    }
}

// MARK: - nodeAt(path:)

@Suite("LayoutNode.nodeAt")
struct LayoutNodeAtTests {

    @Test("nodeAt empty path returns self")
    func nodeAtEmptyPathReturnsSelf() {
        let node = LayoutNode.empty(percentage: 100)
        #expect(node.nodeAt(path: []) == node)
    }

    @Test("nodeAt single-level column")
    func nodeAtSingleLevelColumn() {
        let left = LayoutNode.pinned(app: "Safari", percentage: 40)
        let right = LayoutNode.empty(percentage: 60)
        let root = LayoutNode.columns([left, right])
        #expect(root.nodeAt(path: [0]) == left)
        #expect(root.nodeAt(path: [1]) == right)
    }

    @Test("nodeAt nested path")
    func nodeAtNestedPath() {
        let target = LayoutNode.pinned(app: "Terminal", percentage: 50)
        let inner = LayoutNode.rows([target, LayoutNode.empty(percentage: 50)])
        let root = LayoutNode.columns([LayoutNode.empty(percentage: 50), inner])
        #expect(root.nodeAt(path: [1, 0]) == target)
    }

    @Test("nodeAt out-of-bounds returns nil")
    func nodeAtOutOfBoundsReturnsNil() {
        let root = LayoutNode.columns([.empty(percentage: 100)])
        #expect(root.nodeAt(path: [5]) == nil)
    }

    @Test("nodeAt path beyond leaf depth returns nil")
    func nodeAtPathBeyondLeafDepthReturnsNil() {
        let root = LayoutNode.columns([.empty(percentage: 100)])
        // [0] → leaf, [0, 0] → remaining=[0] on leaf → nil (leaf has no children to recurse into)
        #expect(root.nodeAt(path: [0, 0, 0]) == nil)
    }

    @Test("nodeAt deeply nested path")
    func nodeAtDeeplyNestedPath() {
        let target = LayoutNode.pinned(app: "Xcode", percentage: 100)
        let level3 = LayoutNode.rows([target])
        let level2 = LayoutNode.columns([level3])
        let level1 = LayoutNode.rows([level2])
        let root = LayoutNode.columns([level1])
        #expect(root.nodeAt(path: [0, 0, 0, 0]) == target)
    }
}

// MARK: - replacingNode(at:with:)

@Suite("LayoutNode.replacingNode")
struct LayoutNodeReplacingTests {

    @Test("replacingNode empty path replaces root")
    func replacingNodeEmptyPathReplacesRoot() {
        let root = LayoutNode.empty()
        let newNode = LayoutNode.pinned(app: "Safari")
        let result = root.replacingNode(at: [], with: newNode)
        #expect(result == newNode)
    }

    @Test("replacingNode replaces first column child")
    func replacingNodeReplacesFirstColumnChild() {
        let left = LayoutNode.empty(percentage: 50)
        let right = LayoutNode.empty(percentage: 50)
        let root = LayoutNode.columns([left, right])
        let replacement = LayoutNode.pinned(app: "Safari", percentage: 50)

        let result = root.replacingNode(at: [0], with: replacement)
        #expect(result != nil)
        #expect(result?.nodeAt(path: [0]) == replacement)
        #expect(result?.nodeAt(path: [1]) == right)
    }

    @Test("replacingNode replaces nested child")
    func replacingNodeReplacesNestedChild() {
        let target = LayoutNode.empty(percentage: 50)
        let sibling = LayoutNode.empty(percentage: 50)
        let inner = LayoutNode.rows([target, sibling])
        let root = LayoutNode.columns([inner, LayoutNode.empty(percentage: 50)])
        let replacement = LayoutNode.pinned(app: "Firefox", percentage: 50)

        let result = root.replacingNode(at: [0, 0], with: replacement)
        #expect(result?.nodeAt(path: [0, 0]) == replacement)
        #expect(result?.nodeAt(path: [0, 1]) == sibling)
    }

    @Test("replacingNode out-of-bounds returns nil")
    func replacingNodeOutOfBoundsReturnsNil() {
        let root = LayoutNode.columns([.empty(percentage: 100)])
        let result = root.replacingNode(at: [5], with: .empty())
        #expect(result == nil)
    }

    @Test("replacingNode preserves percentage on container")
    func replacingNodePreservesPercentageOnContainer() {
        let root = LayoutNode(type: .columns, percentage: 75,
                              columns: [.empty(percentage: 50), .empty(percentage: 50)])
        let result = root.replacingNode(at: [0], with: .pinned(app: "Safari", percentage: 50))
        #expect(result?.percentage == 75)
    }

    @Test("replacingNode round-trip: nodeAt after replacingNode")
    func replacingNodeRoundTrip() {
        let original = LayoutNode.pinned(app: "Safari", percentage: 60)
        let sibling = LayoutNode.empty(percentage: 40)
        let root = LayoutNode.columns([original, sibling])
        let replacement = LayoutNode.pinned(app: "Firefox", percentage: 60)

        let newRoot = root.replacingNode(at: [0], with: replacement)
        let retrieved = newRoot?.nodeAt(path: [0])
        #expect(retrieved?.pinned?.application == "Firefox")
    }
}

// MARK: - MockLayoutManager

@Suite("MockLayoutManager")
struct MockLayoutManagerTests {

    @Test("applyLayout records call and sets currentLayout")
    func applyLayoutRecordsCall() {
        let mock = MockLayoutManager()
        let layout = TestFixtures.halfSplitLayout
        mock.applyLayout(layout)
        #expect(mock.appliedLayouts.count == 1)
        #expect(mock.currentLayout?.id == layout.id)
    }

    @Test("updateLayout replaces layout by id")
    func updateLayoutReplacesById() {
        let mock = MockLayoutManager()
        let layout = TestFixtures.halfSplitLayout
        mock.layouts = [layout]
        var updated = layout
        updated.name = "Updated"
        mock.updateLayout(updated)
        #expect(mock.layouts.first?.name == "Updated")
        #expect(mock.updatedLayouts.count == 1)
    }

    @Test("loadLayouts populates layouts from config")
    func loadLayoutsFromConfig() {
        let mock = MockLayoutManager()
        let config = AppConfig(
            activationHotKey: .default,
            layouts: [TestFixtures.halfSplitLayout, TestFixtures.codingLayout],
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )
        mock.loadLayouts(from: config)
        #expect(mock.layouts.count == 2)
    }
}
