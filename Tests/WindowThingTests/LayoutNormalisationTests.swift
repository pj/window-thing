import Testing
@testable import WindowThingCore

/// Collapsing structure that has no effect on what a layout draws.
///
/// The rule that matters is that normalising never moves anything: every case
/// here is about a tree changing shape while the picture stays identical.
@Suite("Layout normalisation")
struct LayoutNormalisationTests {

    // The public constructors take no percentage, so build nodes directly.
    private func cols(_ children: [LayoutNode], _ pct: Double? = nil) -> LayoutNode {
        LayoutNode(type: .columns, percentage: pct, columns: children)
    }

    private func rows(_ children: [LayoutNode], _ pct: Double? = nil) -> LayoutNode {
        LayoutNode(type: .rows, percentage: pct, rows: children)
    }

    private func stack(_ pct: Double) -> LayoutNode { .stackAll(percentage: pct) }
    private func empty(_ pct: Double) -> LayoutNode { .empty(percentage: pct) }

    @Test("A container holding one child becomes that child")
    func singleChildCollapses() {
        let node = cols([stack(100)])
        #expect(node.normalized().type == .stack)
    }

    @Test("The child inherits the container's share, since it takes its place")
    func collapsedChildInheritsPercentage() {
        // The container is a third of its parent; its child claimed all of the
        // container. Collapsed, the child is a third of the parent — keeping
        // the child's own 100 would triple the space it draws in.
        let node = cols([stack(100)], 33)
        let out = node.normalized()
        #expect(out.type == .stack)
        #expect(out.percentage == 33)
    }

    @Test("Nested single-child containers collapse all the way down")
    func nestedSingleChildrenCollapse() {
        // The shape the menubar icon drew as an empty screen.
        let node = cols([rows([cols([stack(50), empty(50)])])])
        let out = node.normalized()
        #expect(out.type == .columns)
        #expect(out.columns?.count == 2)
        #expect(out.columns?.first?.type == .stack)
    }

    @Test("A container holding nothing becomes an empty pane, keeping its share")
    func emptyContainerBecomesEmptyPane() {
        let node = cols([], 40)
        let out = node.normalized()
        #expect(out.type == .empty)
        #expect(out.percentage == 40)
    }

    @Test("A container with two or more children is left alone")
    func realSplitsSurvive() {
        let node = cols([stack(60), empty(40)])
        #expect(node.normalized() == node)
    }

    @Test("Same-axis nesting is preserved — flattening would change editing")
    func sameAxisNestingIsNotFlattened() {
        // columns[a, columns[b, c]] draws the same as columns[a, b, c], but the
        // divider between b and c resizes only those two. Flattening would make
        // every divider resize against every sibling, which is a behaviour
        // change rather than a tidy-up.
        let node = cols([stack(50), cols([empty(50), empty(50)], 50)])
        let out = node.normalized()
        #expect(out.columns?.count == 2)
        #expect(out.columns?.last?.type == .columns)
    }

    @Test("Normalising twice changes nothing the first pass did not")
    func idempotent() {
        let node = cols([rows([cols([stack(50), empty(50)])])])
        let once = node.normalized()
        #expect(once.normalized() == once)
    }

    @Test("A leaf is returned untouched")
    func leavesAreUntouched() {
        let pinned = LayoutNode(type: .pinned, percentage: 100,
                                pinned: PinnedConfig(application: "Safari", bundleId: nil))
        for leaf in [stack(100), empty(100), pinned] {
            #expect(leaf.normalized() == leaf)
        }
    }

    @Test("Every screen set of every layout is normalised")
    func appliesAcrossTheLayout() {
        let debris = cols([rows([stack(100)])])
        let layout = Layout(
            name: "L",
            screenSets: [
                ScreenConfig(layouts: [ScreenConfig.primaryKey: debris, "Studio": debris])
            ]
        )
        let out = layout.normalized()
        #expect(out.screenSets[0].layouts[ScreenConfig.primaryKey]?.type == .stack)
        #expect(out.screenSets[0].layouts["Studio"]?.type == .stack)
    }
}
