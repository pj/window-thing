import Foundation

// MARK: - App Pane State

/// Describes a single pane within an app's internal layout.
public struct SubPane: Equatable, Sendable {
    /// 1-based sub-cell index (depth-first leaf enumeration).
    public let index: Int
    /// Display title for this pane (e.g. the shell command running in a tmux pane).
    public let title: String?
    /// Whether this pane currently has focus within the app.
    public let isFocused: Bool

    public init(index: Int, title: String? = nil, isFocused: Bool = false) {
        self.index = index
        self.title = title
        self.isFocused = isFocused
    }
}

/// The current internal pane state of an app, as reported by its driver.
public struct AppPaneState: Equatable, Sendable {
    /// The pane structure expressed as a LayoutNode tree.
    public let layout: LayoutNode
    /// Flat list of leaf panes with their 1-based indices.
    public let panes: [SubPane]
    /// Index of the currently focused pane, or nil.
    public let focusedIndex: Int?

    public init(layout: LayoutNode, panes: [SubPane], focusedIndex: Int? = nil) {
        self.layout = layout
        self.panes = panes
        self.focusedIndex = focusedIndex
    }
}

// MARK: - App Driver Protocol

/// Protocol for integrating with apps that have internal pane/split concepts.
///
/// Real implementations (e.g. tmux via shell commands) live outside WindowThingCore.
/// WindowThingCore defines the protocol and tests against mock implementations.
public protocol AppDriver: Sendable {
    /// The driver type identifier (must match `SublayoutConfig.driverType`).
    var driverType: String { get }

    /// Query the app's current internal pane layout.
    func queryPaneState() async throws -> AppPaneState

    /// Apply a target sublayout to the app (split, resize, merge panes as needed).
    func applySublayout(_ layout: LayoutNode) async throws

    /// Focus a specific sub-pane by its 1-based index.
    func focusPane(at index: Int) async throws

    /// Get the 1-based index of the currently focused pane, or nil.
    func focusedPaneIndex() async throws -> Int?
}
