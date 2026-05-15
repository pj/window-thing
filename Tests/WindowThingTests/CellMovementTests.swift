import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Cell Movement Across Displays")
struct CellMovementTests {

    // MARK: - CellIndexer Multi-Display Addressing

    @Test("CellIndexer assigns cells across two displays left-to-right")
    func cellsAcrossTwoDisplays() {
        let layout = Layout(
            name: "Dual Columns",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ]),
                    "External Display": .columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
            ]
        )
        let cells = CellIndexer.indexCells(layout: layout, displays: TestFixtures.dualDisplays)

        // Main display (x: 0) has 2 cells, External (x: 1920) has 2 cells
        // Sorted left-to-right: main first, then external
        #expect(cells.count == 4)

        // Cells 1-2 on main display
        #expect(cells[0].address == .numeric(1))
        #expect(cells[0].frame.x >= 0)
        #expect(cells[0].frame.x + cells[0].frame.width <= 1920)

        #expect(cells[1].address == .numeric(2))
        #expect(cells[1].frame.x >= 0)
        #expect(cells[1].frame.x + cells[1].frame.width <= 1920)

        // Cells 3-4 on external display
        #expect(cells[2].address == .numeric(3))
        #expect(cells[2].frame.x >= 1920)

        #expect(cells[3].address == .numeric(4))
        #expect(cells[3].frame.x >= 1920)
    }

    @Test("Triple displays ordered by x coordinate: left, main, external")
    func tripleDisplaysOrderedByX() {
        let layout = Layout(
            name: "Triple",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty(),
                    "Left Display": .empty()
                ])
            ]
        )
        let cells = CellIndexer.indexCells(layout: layout, displays: TestFixtures.tripleDisplays)

        // Left Display (x: -1920) first, Main (x: 0) second, External (x: 1920) third
        #expect(cells.count == 3)
        #expect(cells[0].frame.x < 0, "First cell should be on left display (negative x)")
        #expect(cells[1].frame.x >= 0 && cells[1].frame.x < 1920, "Second cell should be on main")
        #expect(cells[2].frame.x >= 1920, "Third cell should be on external")
    }

    @Test("Cell display names are correct")
    func cellDisplayNames() {
        let layout = Layout(
            name: "Dual",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty()
                ])
            ]
        )
        let cells = CellIndexer.indexCells(layout: layout, displays: TestFixtures.dualDisplays)
        #expect(cells.count == 2)
        #expect(cells[0].displayName == "Main Display")
        #expect(cells[1].displayName == "External Display")
    }

    // MARK: - moveWindow Cross-Display

    @Test("moveWindow to cell on same display positions within display bounds")
    func moveToSameDisplay() throws {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.dualDisplays
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)
        let layout = Layout(
            name: "Dual Columns",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ]),
                    "External Display": .columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
            ]
        )
        layoutManager.applyLayout(layout)
        layoutManager.waitForPendingApply()
        mockWindowManager.setWindowFrameCalls = []

        // Move code window to cell 1 (left half of main display)
        try layoutManager.moveWindow(
            TestFixtures.codeWindow,
            toCellAt: .numeric(1),
            displays: TestFixtures.dualDisplays
        )

        #expect(mockWindowManager.setWindowFrameCalls.count == 1)
        let call = mockWindowManager.setWindowFrameCalls[0]
        #expect(call.frame.x == 0)
        #expect(call.frame.width == 960)  // 50% of 1920
    }

    @Test("moveWindow to cell on different display positions on that display")
    func moveToDifferentDisplay() throws {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.dualDisplays
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)
        let layout = Layout(
            name: "Dual Columns",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ]),
                    "External Display": .columns([
                        .empty(percentage: 50),
                        .empty(percentage: 50)
                    ])
                ])
            ]
        )
        layoutManager.applyLayout(layout)
        layoutManager.waitForPendingApply()
        mockWindowManager.setWindowFrameCalls = []

        // Move code window to cell 3 (left half of external display)
        try layoutManager.moveWindow(
            TestFixtures.codeWindow,
            toCellAt: .numeric(3),
            displays: TestFixtures.dualDisplays
        )

        #expect(mockWindowManager.setWindowFrameCalls.count == 1)
        let call = mockWindowManager.setWindowFrameCalls[0]
        #expect(call.frame.x == 1920)  // Start of external display
        #expect(call.frame.width == 960)  // 50% of 1920
    }

    @Test("moveWindow to invalid cell address throws addressNotFound")
    func moveToInvalidAddress() throws {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)
        let layout = Layout(
            name: "Simple",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([.empty(percentage: 50), .empty(percentage: 50)])
            ])]
        )
        layoutManager.applyLayout(layout)
        layoutManager.waitForPendingApply()

        // Only 2 cells exist, try to move to cell 9
        #expect(throws: CellMoveError.self) {
            try layoutManager.moveWindow(
                TestFixtures.codeWindow,
                toCellAt: .numeric(9),
                displays: TestFixtures.singleDisplay
            )
        }
    }

    @Test("moveWindow with no active layout throws noActiveLayout")
    func moveWithNoLayout() throws {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)
        // No layout applied

        #expect(throws: CellMoveError.self) {
            try layoutManager.moveWindow(
                TestFixtures.codeWindow,
                toCellAt: .numeric(1),
                displays: TestFixtures.singleDisplay
            )
        }
    }
}
