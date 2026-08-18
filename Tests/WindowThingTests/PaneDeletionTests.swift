import Testing
@testable import WindowThingCore

/// Deleting a pane that sits beside the stack — the smallest layout where the
/// stack's "there must always be one" rule and pane removal interact.
@Suite("Pane deletion beside the stack")
struct PaneDeletionTests {

    @Test("Removing the pinned column of a stack+pinned pair leaves the stack")
    func removePinnedNextToStack() {
        let root = LayoutNode.columns([
            .stackAll(percentage: 50),
            .pinned(app: "Mail", percentage: 50)
        ])

        let trimmed = root.removingColumn(at: 1)

        #expect(trimmed != nil)
        #expect(trimmed?.columns?.count == 1)
        #expect(trimmed?.columns?.first?.type == .stack)
    }

    @Test("Removing the stack column re-creates a stack in what remains")
    func removeStackNextToPinned() {
        let root = LayoutNode.columns([
            .stackAll(percentage: 50),
            .pinned(app: "Mail", percentage: 50)
        ])

        let trimmed = root.removingColumn(at: 0)

        #expect(trimmed != nil)
        #expect(trimmed?.findStackLocation() != nil)
    }

    @Test("A single-child container refuses removal")
    func refusesToEmptyContainer() {
        let root = LayoutNode.columns([.stackAll(percentage: 100)])
        #expect(root.removingColumn(at: 0) == nil)
    }

    @Test("Rows behave the same as columns")
    func removePinnedRowNextToStack() {
        let root = LayoutNode.rows([
            .stackAll(percentage: 50),
            .pinned(app: "Mail", percentage: 50)
        ])

        let trimmed = root.removingRow(at: 1)

        #expect(trimmed?.rows?.count == 1)
        #expect(trimmed?.rows?.first?.type == .stack)
    }
}
