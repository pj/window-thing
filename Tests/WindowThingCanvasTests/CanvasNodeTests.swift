import Testing
@testable import WindowThingCanvas

// MARK: - CanvasNode unit tests
// No UI framework needed — pure value-type logic.

@Suite("CanvasNode factories") struct CanvasNodeFactoryTests {

    @Test func emptyDefaults() {
        let node = CanvasNode<String>.empty()
        #expect(node.kind == .empty)
        #expect(node.percentage == 100)
        #expect(node.pinnedContent == nil)
        #expect(node.columnChildren == nil)
        #expect(node.rowChildren == nil)
    }

    @Test func emptyCustomPercentage() {
        let node = CanvasNode<String>.empty(percentage: 33)
        #expect(node.percentage == 33)
    }

    @Test func stack() {
        let node = CanvasNode<String>.stack(percentage: 75)
        #expect(node.kind == .stack)
        #expect(node.percentage == 75)
    }

    @Test func pinned() {
        let node = CanvasNode<String>.pinned("hello", percentage: 60)
        #expect(node.pinnedContent == "hello")
        #expect(node.percentage == 60)
    }

    @Test func columns() {
        let children: [CanvasNode<String>] = [.empty(percentage: 40), .stack(percentage: 60)]
        let node = CanvasNode<String>.columns(children)
        #expect(node.columnChildren?.count == 2)
        #expect(node.rowChildren == nil)
    }

    @Test func rows() {
        let children: [CanvasNode<String>] = [.empty(percentage: 50), .stack(percentage: 50)]
        let node = CanvasNode<String>.rows(children)
        #expect(node.rowChildren?.count == 2)
        #expect(node.columnChildren == nil)
    }
}

@Suite("CanvasNode mutation") struct CanvasNodeMutationTests {

    @Test func withPercentagePreservesKind() {
        let node = CanvasNode<String>.pinned("x", percentage: 30).withPercentage(70)
        #expect(node.percentage == 70)
        #expect(node.pinnedContent == "x")
    }

    @Test func withKindPreservesPercentage() {
        let node = CanvasNode<String>.empty(percentage: 40).withKind(.stack)
        #expect(node.percentage == 40)
        #expect(node.kind == .stack)
    }

    @Test func withColumns() {
        let cols: [CanvasNode<String>] = [.empty(percentage: 50), .stack(percentage: 50)]
        let result = CanvasNode<String>.empty().withColumns(cols)
        #expect(result.columnChildren?.count == 2)
    }

    @Test func withRows() {
        let rs: [CanvasNode<String>] = [.empty(percentage: 50), .stack(percentage: 50)]
        let result = CanvasNode<String>.empty().withRows(rs)
        #expect(result.rowChildren?.count == 2)
    }
}

@Suite("CanvasNode.nodeAt") struct NodeAtTests {

    @Test func emptyPathReturnsSelf() {
        let node = CanvasNode<String>.pinned("x", percentage: 75)
        #expect(node.nodeAt(path: []) == node)
    }

    @Test func singleLevelColumns() {
        let child = CanvasNode<String>.pinned("target", percentage: 40)
        let root = CanvasNode<String>.columns([child, .empty(percentage: 60)])
        #expect(root.nodeAt(path: [0]) == child)
    }

    @Test func singleLevelRows() {
        let child = CanvasNode<String>.stack(percentage: 60)
        let root = CanvasNode<String>.rows([.empty(percentage: 40), child])
        #expect(root.nodeAt(path: [1]) == child)
    }

    @Test func nestedPath() {
        let leaf = CanvasNode<String>.pinned("deep")
        let inner = CanvasNode<String>.rows([leaf, .empty()])
        let root = CanvasNode<String>.columns([inner, .empty()])
        #expect(root.nodeAt(path: [0, 0]) == leaf)
    }

    @Test func outOfBoundsReturnsNil() {
        let root = CanvasNode<String>.columns([.empty()])
        #expect(root.nodeAt(path: [5]) == nil)
    }

    @Test func pathBeyondLeafReturnsNil() {
        let root = CanvasNode<String>.empty()
        #expect(root.nodeAt(path: [0]) == nil)
    }
}

@Suite("CanvasNode.replacingNode") struct ReplacingNodeTests {

    @Test func replacesAtRoot() {
        let root = CanvasNode<String>.empty()
        let replacement = CanvasNode<String>.stack()
        let result = root.replacingNode(at: [], with: replacement)
        #expect(result?.kind == .stack)
    }

    @Test func replacesInColumns() {
        let root = CanvasNode<String>.columns([
            .empty(percentage: 50),
            .empty(percentage: 50),
        ])
        let replacement = CanvasNode<String>.pinned("new", percentage: 50)
        let result = root.replacingNode(at: [1], with: replacement)
        #expect(result?.columnChildren?[1].pinnedContent == "new")
        #expect(result?.columnChildren?[0].kind == .empty)
    }

    @Test func replacesNested() {
        let root = CanvasNode<String>.columns([
            .rows([.empty(percentage: 50), .stack(percentage: 50)]),
            .empty(percentage: 50),
        ])
        let replacement = CanvasNode<String>.pinned("nested")
        let result = root.replacingNode(at: [0, 1], with: replacement)
        #expect(result?.columnChildren?[0].rowChildren?[1].pinnedContent == "nested")
    }

    @Test func outOfBoundsReturnsNil() {
        let root = CanvasNode<String>.columns([.empty()])
        #expect(root.replacingNode(at: [5], with: .stack()) == nil)
    }

    @Test func preservesOtherChildren() {
        let original = CanvasNode<String>.pinned("original", percentage: 40)
        let root = CanvasNode<String>.columns([original, .stack(percentage: 60)])
        let result = root.replacingNode(at: [1], with: .empty(percentage: 60))
        #expect(result?.columnChildren?[0] == original)
        #expect(result?.columnChildren?[1].kind == .empty)
    }
}

@Suite("CanvasNode equality") struct EqualityTests {

    @Test func equalEmpty() {
        #expect(CanvasNode<String>.empty(percentage: 50) == CanvasNode<String>.empty(percentage: 50))
    }

    @Test func unequalPercentage() {
        #expect(CanvasNode<String>.empty(percentage: 40) != CanvasNode<String>.empty(percentage: 60))
    }

    @Test func equalPinned() {
        #expect(CanvasNode<String>.pinned("x") == CanvasNode<String>.pinned("x"))
    }

    @Test func unequalPinnedContent() {
        #expect(CanvasNode<String>.pinned("x") != CanvasNode<String>.pinned("y"))
    }

    @Test func equalColumns() {
        let a = CanvasNode<String>.columns([.pinned("x", percentage: 40), .empty(percentage: 60)])
        let b = CanvasNode<String>.columns([.pinned("x", percentage: 40), .empty(percentage: 60)])
        #expect(a == b)
    }
}
