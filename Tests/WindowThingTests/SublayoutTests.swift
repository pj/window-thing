import Testing
import Foundation
@testable import WindowThingCore

// MARK: - SubCellAddress Tests

@Suite("SubCellAddress")
struct SubCellAddressTests {

    @Test("stringValue formats as parent.subIndex")
    func stringValue() {
        let addr = SubCellAddress(parent: .numeric(3), subIndex: 1)
        #expect(addr.stringValue == "3.1")

        let addr2 = SubCellAddress(parent: .alpha("a"), subIndex: 5)
        #expect(addr2.stringValue == "a.5")
    }

    @Test("parse numeric parent")
    func parseNumeric() {
        let addr = SubCellAddress(string: "3.1")
        #expect(addr != nil)
        #expect(addr?.parent == .numeric(3))
        #expect(addr?.subIndex == 1)
    }

    @Test("parse alpha parent")
    func parseAlpha() {
        let addr = SubCellAddress(string: "a.2")
        #expect(addr != nil)
        #expect(addr?.parent == .alpha("a"))
        #expect(addr?.subIndex == 2)
    }

    @Test("parse multi-digit parent and subIndex")
    func parseMultiDigit() {
        let addr = SubCellAddress(string: "15.12")
        #expect(addr != nil)
        #expect(addr?.parent == .numeric(15))
        #expect(addr?.subIndex == 12)
    }

    @Test("parse invalid strings return nil")
    func parseInvalid() {
        #expect(SubCellAddress(string: "") == nil)
        #expect(SubCellAddress(string: "3") == nil)
        #expect(SubCellAddress(string: "3.") == nil)
        #expect(SubCellAddress(string: ".1") == nil)
        #expect(SubCellAddress(string: "3.0") == nil)
        #expect(SubCellAddress(string: "3.abc") == nil)
        #expect(SubCellAddress(string: "..") == nil)
    }

    @Test("roundtrip through stringValue")
    func roundtrip() {
        let original = SubCellAddress(parent: .numeric(7), subIndex: 3)
        let parsed = SubCellAddress(string: original.stringValue)
        #expect(parsed == original)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = SubCellAddress(parent: .numeric(3), subIndex: 2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubCellAddress.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable roundtrip with alpha parent")
    func codableRoundtripAlpha() throws {
        let original = SubCellAddress(parent: .alpha("z"), subIndex: 9)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubCellAddress.self, from: data)
        #expect(decoded == original)
    }

    @Test("equality")
    func equality() {
        let a = SubCellAddress(parent: .numeric(1), subIndex: 1)
        let b = SubCellAddress(parent: .numeric(1), subIndex: 1)
        let c = SubCellAddress(parent: .numeric(1), subIndex: 2)
        let d = SubCellAddress(parent: .numeric(2), subIndex: 1)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }
}

// MARK: - SublayoutConfig Tests

@Suite("SublayoutConfig")
struct SublayoutConfigTests {

    @Test("init stores driverType and layout")
    func initStoresValues() {
        let layout = LayoutNode.columns([.empty(percentage: 50), .empty(percentage: 50)])
        let config = SublayoutConfig(driverType: "tmux", layout: layout)
        #expect(config.driverType == "tmux")
        #expect(config.layoutNode == layout)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let layout = LayoutNode.columns([
            .empty(percentage: 60),
            .empty(percentage: 40)
        ])
        let original = SublayoutConfig(driverType: "tmux", layout: layout)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SublayoutConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable roundtrip with nested rows/columns")
    func codableRoundtripNested() throws {
        let layout = LayoutNode.columns([
            .rows([.empty(percentage: 50), .empty(percentage: 50)]),
            .empty(percentage: 40)
        ])
        let original = SublayoutConfig(driverType: "vim", layout: layout)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SublayoutConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("equality")
    func equality() {
        let a = SublayoutConfig(driverType: "tmux", layout: .empty())
        let b = SublayoutConfig(driverType: "tmux", layout: .empty())
        let c = SublayoutConfig(driverType: "vim", layout: .empty())
        let d = SublayoutConfig(driverType: "tmux", layout: .columns([.empty(), .empty()]))
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }
}

// MARK: - PinnedConfig Backward Compatibility Tests

@Suite("PinnedConfig Sublayout")
struct PinnedConfigSublayoutTests {

    @Test("PinnedConfig without sublayout has nil")
    func withoutSublayout() {
        let config = PinnedConfig(application: "Terminal", bundleId: nil)
        #expect(config.sublayout == nil)
    }

    @Test("PinnedConfig with sublayout stores it")
    func withSublayout() {
        let sub = SublayoutConfig(driverType: "tmux", layout: .columns([.empty(), .empty()]))
        let config = PinnedConfig(application: "Terminal", bundleId: nil, sublayout: sub)
        #expect(config.sublayout == sub)
        #expect(config.sublayout?.driverType == "tmux")
    }

    @Test("PinnedConfig Codable roundtrip with sublayout")
    func codableWithSublayout() throws {
        let sub = SublayoutConfig(driverType: "tmux", layout: .columns([
            .empty(percentage: 60),
            .empty(percentage: 40)
        ]))
        let original = PinnedConfig(application: "Terminal", bundleId: "com.apple.Terminal", sublayout: sub)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PinnedConfig.self, from: data)
        #expect(decoded == original)
        #expect(decoded.sublayout?.driverType == "tmux")
    }

    @Test("PinnedConfig Codable without sublayout key decodes as nil")
    func codableWithoutSublayoutKey() throws {
        // Simulate existing JSON without sublayout field
        let json = """
        {"application":"Terminal","bundleId":"com.apple.Terminal"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PinnedConfig.self, from: data)
        #expect(decoded.application == "Terminal")
        #expect(decoded.sublayout == nil)
    }

    @Test("LayoutNode.pinned factory with sublayout")
    func pinnedFactoryWithSublayout() {
        let sub = SublayoutConfig(driverType: "tmux", layout: .empty())
        let node = LayoutNode.pinned(app: "Terminal", percentage: 50, sublayout: sub)
        #expect(node.type == .pinned)
        #expect(node.percentage == 50)
        #expect(node.pinned?.application == "Terminal")
        #expect(node.pinned?.sublayout?.driverType == "tmux")
    }

    @Test("LayoutNode.pinned factory without sublayout still works")
    func pinnedFactoryWithoutSublayout() {
        let node = LayoutNode.pinned(app: "Safari", bundleId: "com.apple.Safari")
        #expect(node.pinned?.sublayout == nil)
    }
}

// MARK: - CellIndexer Sub-Cell Tests

@Suite("CellIndexer SubCells")
struct CellIndexerSubCellTests {

    @Test("indexSubCells with 2-column sublayout produces 2 sub-cells")
    func twoColumnSublayout() {
        let sublayout = LayoutNode.columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ])
        let parentFrame = WindowFrame(x: 0, y: 0, width: 1920, height: 1080)
        let subCells = CellIndexer.indexSubCells(
            parentAddress: .numeric(1),
            sublayout: sublayout,
            parentFrame: parentFrame
        )
        #expect(subCells.count == 2)
        #expect(subCells[0].address == SubCellAddress(parent: .numeric(1), subIndex: 1))
        #expect(subCells[1].address == SubCellAddress(parent: .numeric(1), subIndex: 2))
        // Left half
        #expect(subCells[0].frame.x == 0)
        #expect(subCells[0].frame.width == 960)
        // Right half
        #expect(subCells[1].frame.x == 960)
        #expect(subCells[1].frame.width == 960)
    }

    @Test("indexSubCells with 2x2 grid produces 4 sub-cells depth-first")
    func twoByTwoGrid() {
        let sublayout = LayoutNode.columns([
            .rows([.empty(percentage: 50), .empty(percentage: 50)]),
            .rows([.empty(percentage: 50), .empty(percentage: 50)])
        ])
        let parentFrame = WindowFrame(x: 100, y: 100, width: 1000, height: 800)
        let subCells = CellIndexer.indexSubCells(
            parentAddress: .numeric(3),
            sublayout: sublayout,
            parentFrame: parentFrame
        )
        #expect(subCells.count == 4)
        // Depth-first: left-top, left-bottom, right-top, right-bottom
        #expect(subCells[0].address.subIndex == 1)
        #expect(subCells[1].address.subIndex == 2)
        #expect(subCells[2].address.subIndex == 3)
        #expect(subCells[3].address.subIndex == 4)
        // All share parent address
        for sc in subCells {
            #expect(sc.parentAddress == .numeric(3))
            #expect(sc.address.parent == .numeric(3))
        }
    }

    @Test("indexSubCells with single leaf returns one sub-cell")
    func singleLeaf() {
        let sublayout = LayoutNode.empty()
        let parentFrame = WindowFrame(x: 0, y: 0, width: 800, height: 600)
        let subCells = CellIndexer.indexSubCells(
            parentAddress: .alpha("a"),
            sublayout: sublayout,
            parentFrame: parentFrame
        )
        #expect(subCells.count == 1)
        #expect(subCells[0].address == SubCellAddress(parent: .alpha("a"), subIndex: 1))
        #expect(subCells[0].frame == parentFrame)
    }

    @Test("indexSubCells sub-cell frames fit within parent frame")
    func subCellsWithinParent() {
        let sublayout = LayoutNode.columns([
            .empty(percentage: 30),
            .rows([.empty(percentage: 50), .empty(percentage: 50)]),
            .empty(percentage: 30)
        ])
        let parentFrame = WindowFrame(x: 500, y: 200, width: 1000, height: 800)
        let subCells = CellIndexer.indexSubCells(
            parentAddress: .numeric(2),
            sublayout: sublayout,
            parentFrame: parentFrame
        )
        for sc in subCells {
            #expect(sc.frame.x >= parentFrame.x)
            #expect(sc.frame.y >= parentFrame.y)
            #expect(sc.frame.x + sc.frame.width <= parentFrame.x + parentFrame.width + 0.01)
            #expect(sc.frame.y + sc.frame.height <= parentFrame.y + parentFrame.height + 0.01)
        }
    }

    @Test("indexAllCells includes sub-cells for pinned nodes with sublayouts")
    func indexAllCellsWithSublayouts() {
        let sub = SublayoutConfig(driverType: "tmux", layout: .columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ]))
        let layout = Layout(
            name: "With Sublayout",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Terminal", bundleId: "com.apple.Terminal", percentage: 50, sublayout: sub),
                    .empty(percentage: 50)
                ])
            ])]
        )
        let cellMap = CellIndexer.indexAllCells(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(cellMap.cells.count == 2)
        #expect(cellMap.subCells.count == 2)
        #expect(cellMap.subCells[0].address == SubCellAddress(parent: .numeric(1), subIndex: 1))
        #expect(cellMap.subCells[1].address == SubCellAddress(parent: .numeric(1), subIndex: 2))
    }

    @Test("indexAllCells without sublayouts has empty subCells")
    func indexAllCellsWithoutSublayouts() {
        let layout = Layout(
            name: "No Sublayout",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Terminal", percentage: 50),
                    .empty(percentage: 50)
                ])
            ])]
        )
        let cellMap = CellIndexer.indexAllCells(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(cellMap.cells.count == 2)
        #expect(cellMap.subCells.isEmpty)
    }

    @Test("indexAllCells with no matching screen set returns empty map")
    func indexAllCellsNoMatch() {
        let layout = Layout(
            name: "NoMatch",
            screenSets: [ScreenConfig(layouts: [
                "Unknown": .empty()
            ])]
        )
        let cellMap = CellIndexer.indexAllCells(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(cellMap.cells.isEmpty)
        #expect(cellMap.subCells.isEmpty)
    }

    @Test("CellMap lookup by SubCellAddress")
    func cellMapSubCellLookup() {
        let sub = SublayoutConfig(driverType: "tmux", layout: .columns([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ]))
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: "Terminal", sublayout: sub)
            ])]
        )
        let cellMap = CellIndexer.indexAllCells(layout: layout, displays: TestFixtures.singleDisplay)
        let addr = SubCellAddress(parent: .numeric(1), subIndex: 2)
        let found = cellMap.subCell(at: addr)
        #expect(found != nil)
        #expect(found?.address == addr)
    }

    @Test("CellMap lookup by CellAddress")
    func cellMapCellLookup() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([.empty(percentage: 50), .empty(percentage: 50)])
            ])]
        )
        let cellMap = CellIndexer.indexAllCells(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(cellMap.cell(at: .numeric(1)) != nil)
        #expect(cellMap.cell(at: .numeric(2)) != nil)
        #expect(cellMap.cell(at: .numeric(3)) == nil)
    }

    @Test("CellMap hasSubCells")
    func cellMapHasSubCells() {
        let sub = SublayoutConfig(driverType: "tmux", layout: .columns([.empty(), .empty()]))
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: "Terminal", percentage: 50, sublayout: sub),
                    .empty(percentage: 50)
                ])
            ])]
        )
        let cellMap = CellIndexer.indexAllCells(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(cellMap.hasSubCells(at: .numeric(1)) == true)
        #expect(cellMap.hasSubCells(at: .numeric(2)) == false)
    }

    @Test("indexAllCells with multi-display sublayouts")
    func multiDisplaySublayouts() {
        let sub = SublayoutConfig(driverType: "tmux", layout: .rows([
            .empty(percentage: 50),
            .empty(percentage: 50)
        ]))
        let layout = Layout(
            name: "Dual",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: "Terminal", sublayout: sub),
                "External Display": .columns([
                    .pinned(app: "VSCode", percentage: 50, sublayout: SublayoutConfig(
                        driverType: "vim",
                        layout: .columns([.empty(percentage: 50), .empty(percentage: 50)])
                    )),
                    .empty(percentage: 50)
                ])
            ])]
        )
        let cellMap = CellIndexer.indexAllCells(layout: layout, displays: TestFixtures.dualDisplays)
        // Cell 1: Terminal on main (has 2 sub-cells from rows sublayout)
        // Cells 2-3: VSCode + empty on external
        // Cell 2 (VSCode) has 2 sub-cells from columns sublayout
        #expect(cellMap.cells.count == 3)
        #expect(cellMap.subCells.count == 4)  // 2 from cell 1 + 2 from cell 2
        #expect(cellMap.hasSubCells(at: .numeric(1)) == true)
        #expect(cellMap.hasSubCells(at: .numeric(2)) == true)
        #expect(cellMap.hasSubCells(at: .numeric(3)) == false)
    }
}

// MARK: - Mock App Driver Tests

@Suite("MockAppDriver")
struct MockAppDriverTests {

    @Test("queryPaneState returns configured state")
    func queryPaneState() async throws {
        let state = AppPaneState(
            layout: .columns([.empty(), .empty()]),
            panes: [
                SubPane(index: 1, title: "bash", isFocused: true),
                SubPane(index: 2, title: "vim", isFocused: false)
            ],
            focusedIndex: 1
        )
        let driver = MockAppDriver(driverType: "tmux", paneState: state)
        let result = try await driver.queryPaneState()
        #expect(result == state)
        #expect(result.panes.count == 2)
        #expect(result.focusedIndex == 1)
    }

    @Test("applySublayout records the layout")
    func applySublayout() async throws {
        let state = AppPaneState(layout: .empty(), panes: [], focusedIndex: nil)
        let driver = MockAppDriver(paneState: state)

        let target = LayoutNode.columns([.empty(), .empty(), .empty()])
        try await driver.applySublayout(target)

        #expect(driver.appliedSublayouts.count == 1)
        #expect(driver.appliedSublayouts[0] == target)
    }

    @Test("focusPane records the index")
    func focusPane() async throws {
        let state = AppPaneState(layout: .empty(), panes: [], focusedIndex: nil)
        let driver = MockAppDriver(paneState: state)

        try await driver.focusPane(at: 2)
        try await driver.focusPane(at: 5)

        #expect(driver.focusedPanes == [2, 5])
    }

    @Test("focusedPaneIndex returns configured value")
    func focusedPaneIndex() async throws {
        let state = AppPaneState(layout: .empty(), panes: [], focusedIndex: nil)
        let driver = MockAppDriver(paneState: state)
        driver.currentFocusedIndex = 3

        let result = try await driver.focusedPaneIndex()
        #expect(result == 3)
    }

    @Test("driverType matches configured value")
    func driverType() {
        let state = AppPaneState(layout: .empty(), panes: [], focusedIndex: nil)
        let driver = MockAppDriver(driverType: "tmux", paneState: state)
        #expect(driver.driverType == "tmux")
    }
}
