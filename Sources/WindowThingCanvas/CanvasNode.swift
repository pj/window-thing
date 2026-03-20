/// A generic recursive layout node. Content is whatever the caller wants to pin in a leaf —
/// the canvas has no knowledge of what it represents.
public struct CanvasNode<Content: Hashable & Sendable>: Hashable, Sendable {

    // MARK: - Kind

    public enum Kind: Hashable, Sendable {
        case empty
        case stack
        case pinned(Content)
        case columns([CanvasNode<Content>])
        case rows([CanvasNode<Content>])
    }

    // MARK: - Properties

    public var kind: Kind
    public var percentage: Double

    public init(kind: Kind, percentage: Double = 100) {
        self.kind = kind
        self.percentage = percentage
    }

    // MARK: - Factories

    public static func empty(percentage: Double = 100) -> Self {
        Self(kind: .empty, percentage: percentage)
    }

    public static func stack(percentage: Double = 100) -> Self {
        Self(kind: .stack, percentage: percentage)
    }

    public static func pinned(_ content: Content, percentage: Double = 100) -> Self {
        Self(kind: .pinned(content), percentage: percentage)
    }

    public static func columns(_ children: [CanvasNode<Content>], percentage: Double = 100) -> Self {
        Self(kind: .columns(children), percentage: percentage)
    }

    public static func rows(_ children: [CanvasNode<Content>], percentage: Double = 100) -> Self {
        Self(kind: .rows(children), percentage: percentage)
    }

    // MARK: - Immutable mutation

    public func withPercentage(_ pct: Double) -> Self {
        Self(kind: kind, percentage: pct)
    }

    public func withKind(_ newKind: Kind) -> Self {
        Self(kind: newKind, percentage: percentage)
    }

    public func withColumns(_ children: [CanvasNode<Content>]) -> Self {
        Self(kind: .columns(children), percentage: percentage)
    }

    public func withRows(_ children: [CanvasNode<Content>]) -> Self {
        Self(kind: .rows(children), percentage: percentage)
    }

    // MARK: - Accessors

    public var pinnedContent: Content? {
        if case .pinned(let c) = kind { return c }
        return nil
    }

    public var columnChildren: [CanvasNode<Content>]? {
        if case .columns(let cols) = kind { return cols }
        return nil
    }

    public var rowChildren: [CanvasNode<Content>]? {
        if case .rows(let rs) = kind { return rs }
        return nil
    }

    // MARK: - Tree navigation

    public func nodeAt(path: [Int]) -> CanvasNode<Content>? {
        guard !path.isEmpty else { return self }
        let idx = path[0]
        let rest = Array(path.dropFirst())
        switch kind {
        case .columns(let cols):
            guard idx < cols.count else { return nil }
            return cols[idx].nodeAt(path: rest)
        case .rows(let rs):
            guard idx < rs.count else { return nil }
            return rs[idx].nodeAt(path: rest)
        default:
            return nil
        }
    }

    public func replacingNode(at path: [Int], with replacement: CanvasNode<Content>) -> CanvasNode<Content>? {
        guard !path.isEmpty else { return replacement }
        let idx = path[0]
        let rest = Array(path.dropFirst())
        switch kind {
        case .columns(var cols):
            guard idx < cols.count else { return nil }
            guard let updated = cols[idx].replacingNode(at: rest, with: replacement) else { return nil }
            cols[idx] = updated
            return withColumns(cols)
        case .rows(var rs):
            guard idx < rs.count else { return nil }
            guard let updated = rs[idx].replacingNode(at: rest, with: replacement) else { return nil }
            rs[idx] = updated
            return withRows(rs)
        default:
            return nil
        }
    }
}
