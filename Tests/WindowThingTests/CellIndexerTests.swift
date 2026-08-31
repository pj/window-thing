import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("CellIndexer Tests")
struct CellIndexerTests {

    // MARK: - address(forIndex:)

    @Test("address(forIndex:) returns numeric for 1-35")
    func addressNumericRange() {
        #expect(CellIndexer.address(forIndex: 1) == .numeric(1))
        #expect(CellIndexer.address(forIndex: 35) == .numeric(35))
        #expect(CellIndexer.address(forIndex: 17) == .numeric(17))
    }

    @Test("address(forIndex:) returns alpha for 36-61")
    func addressAlphaRange() {
        #expect(CellIndexer.address(forIndex: 36) == .alpha("a"))
        #expect(CellIndexer.address(forIndex: 37) == .alpha("b"))
        #expect(CellIndexer.address(forIndex: 61) == .alpha("z"))
    }

    @Test("address(forIndex:) returns nil for out of range")
    func addressOutOfRange() {
        #expect(CellIndexer.address(forIndex: 0) == nil)
        #expect(CellIndexer.address(forIndex: -1) == nil)
        #expect(CellIndexer.address(forIndex: 62) == nil)
    }

    // MARK: - ghostPositions

    @Test("ghostPositions returns two ghosts per display (column + row)")
    func ghostPositionsCount() {
        let layout = Layout(
            name: "Simple",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .empty(percentage: 50),
                    .empty(percentage: 50)
                ])
            ])
        )
        let ghosts = CellIndexer.ghostPositions(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(ghosts.count == 2)
        #expect(ghosts[0].direction == .trailingColumn)
        #expect(ghosts[1].direction == .trailingRow)
    }

    @Test("ghostPositions dual display returns four ghosts")
    func ghostPositionsDualDisplay() {
        let layout = Layout(
            name: "Dual",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .empty(),
                "External Display": .empty()
            ])
        )
        let ghosts = CellIndexer.ghostPositions(layout: layout, displays: TestFixtures.dualDisplays)
        #expect(ghosts.count == 4)
        // First display's ghosts
        #expect(ghosts[0].displayName == "Main Display")
        #expect(ghosts[0].direction == .trailingColumn)
        #expect(ghosts[1].displayName == "Main Display")
        #expect(ghosts[1].direction == .trailingRow)
        // Second display's ghosts
        #expect(ghosts[2].displayName == "External Display")
        #expect(ghosts[3].displayName == "External Display")
    }

    @Test("ghostPositions trailing column is disabled when too many columns")
    func ghostColumnDisabledWhenTooMany() {
        // 6 columns = each 16.7%. Adding a 7th would be 14.3% < 15% min
        let layout = Layout(
            name: "ManyColumns",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.5)
                ])
            ])
        )
        let ghosts = CellIndexer.ghostPositions(layout: layout, displays: TestFixtures.singleDisplay)
        let colGhost = ghosts.first { $0.direction == .trailingColumn }!
        #expect(colGhost.isDisabled == true)
    }

    @Test("ghostPositions trailing row is disabled when too many rows")
    func ghostRowDisabledWhenTooMany() {
        // 6 rows = each 16.7%. Adding a 7th would be 14.3% < 15% min
        let layout = Layout(
            name: "ManyRows",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .rows([
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.7),
                    .empty(percentage: 16.5)
                ])
            ])
        )
        let ghosts = CellIndexer.ghostPositions(layout: layout, displays: TestFixtures.singleDisplay)
        let rowGhost = ghosts.first { $0.direction == .trailingRow }!
        #expect(rowGhost.isDisabled == true)
    }

    @Test("ghostPositions not disabled for leaf nodes (would become 2 = 50% each)")
    func ghostNotDisabledForLeaf() {
        let layout = Layout(
            name: "Single",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .empty()
            ])
        )
        let ghosts = CellIndexer.ghostPositions(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(ghosts[0].isDisabled == false)  // column ghost
        #expect(ghosts[1].isDisabled == false)  // row ghost
    }

    @Test("ghostPositions estimated frames are within display bounds")
    func ghostFramesWithinDisplay() {
        let layout = Layout(
            name: "Simple",
            screens: ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .empty(percentage: 50),
                    .empty(percentage: 50)
                ])
            ])
        )
        let display = TestFixtures.singleDisplay[0]
        let ghosts = CellIndexer.ghostPositions(layout: layout, displays: TestFixtures.singleDisplay)

        for ghost in ghosts {
            #expect(ghost.estimatedFrame.x >= display.frame.x)
            #expect(ghost.estimatedFrame.y >= display.frame.y)
            #expect(ghost.estimatedFrame.x + ghost.estimatedFrame.width <= display.frame.x + display.frame.width)
            #expect(ghost.estimatedFrame.y + ghost.estimatedFrame.height <= display.frame.y + display.frame.height)
        }
    }

    @Test("A layout naming only absent displays falls back, and the fallback has ghosts")
    func ghostPositionsNoMatch() {
        let layout = Layout(
            name: "NoMatch",
            screens: ScreenConfig(layouts: [
                "Unknown Monitor": .empty()
            ])
        )
        // The fallback is a single fullscreen stack on the main display, which
        // can be extended like any other pane.
        let ghosts = CellIndexer.ghostPositions(layout: layout, displays: TestFixtures.singleDisplay)
        #expect(ghosts.allSatisfy { $0.displayName == "Main Display" })
    }
}
