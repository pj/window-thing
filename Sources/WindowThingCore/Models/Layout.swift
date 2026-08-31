import Foundation
import CoreGraphics

// MARK: - Cell Address

/// A globally unique address for a leaf cell in the active layout, indexed
/// left-to-right top-to-bottom across all monitors.
/// Indices 1–35 are `.numeric`; overflow indices 36–61 are `.alpha` ('a'–'z').
public enum CellAddress: Hashable, Sendable {
    case numeric(Int)   // 1–35
    case alpha(Character) // 'a'–'z'

    /// Create from a 1-based sequential index.
    public static func from(index: Int) -> CellAddress? {
        if index >= 1 && index <= 35 {
            return .numeric(index)
        } else if index >= 36 && index <= 61 {
            let letter = Character(UnicodeScalar(Int(("a" as UnicodeScalar).value) + index - 36)!)
            return .alpha(letter)
        }
        return nil
    }

    /// String representation used in config ("1", "2", … "a", "b").
    public var stringValue: String {
        switch self {
        case .numeric(let n): return "\(n)"
        case .alpha(let c): return String(c)
        }
    }

    /// Create from the string representation used in config.
    public init?(string: String) {
        guard !string.isEmpty else { return nil }
        if let n = Int(string), n >= 1, n <= 35 {
            self = .numeric(n)
        } else if string.count == 1, let c = string.first, c.isLowercase, c.isLetter {
            self = .alpha(c)
        } else {
            return nil
        }
    }
}

extension CellAddress: CustomStringConvertible {
    public var description: String { stringValue }
}

extension CellAddress: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let addr = CellAddress(string: s) else {
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Invalid CellAddress: '\(s)'")
        }
        self = addr
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

// MARK: - Sub-Cell Address

/// A two-level address: a parent cell plus a 1-based sub-index within its sublayout.
/// String form: "3.1", "a.2", etc.
public struct SubCellAddress: Hashable, Sendable, Codable {
    public let parent: CellAddress
    public let subIndex: Int  // 1-based

    public init(parent: CellAddress, subIndex: Int) {
        self.parent = parent
        self.subIndex = subIndex
    }

    public var stringValue: String {
        "\(parent.stringValue).\(subIndex)"
    }

    public init?(string: String) {
        let parts = string.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let parent = CellAddress(string: String(parts[0])),
              let sub = Int(parts[1]),
              sub >= 1 else {
            return nil
        }
        self.parent = parent
        self.subIndex = sub
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let addr = SubCellAddress(string: s) else {
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Invalid SubCellAddress: '\(s)'")
        }
        self = addr
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

// MARK: - Layout Types (matching modal-commander structure)

public enum LayoutType: String, Codable, Sendable {
    case stack
    case pinned
    case columns
    case rows
    case floatZoomed = "float_zoomed"
    case empty
}

/// Configuration for an app's internal pane sublayout.
public struct SublayoutConfig: Codable, Equatable, Sendable {
    /// Identifier for the app driver (e.g. "tmux", "vim").
    public let driverType: String
    /// The internal pane layout tree — reuses LayoutNode (.columns, .rows, .empty are meaningful).
    /// Boxed to break the recursive value type cycle (SublayoutConfig → LayoutNode → PinnedConfig → SublayoutConfig).
    public let layout: Box<LayoutNode>
    /// Driver-specific target identifier (e.g. "main:0" for tmux session:window).
    public let target: String?

    public var layoutNode: LayoutNode { layout.value }

    public init(driverType: String, layout: LayoutNode, target: String? = nil) {
        self.driverType = driverType
        self.layout = Box(layout)
        self.target = target
    }
}

public struct PinnedConfig: Codable, Equatable, Sendable {
    public let application: String?
    public let bundleId: String?
    /// Specific window titles to pin. nil or empty = all windows of the app.
    public let windowTitles: [String]?

    /// The exact window this pin was made from.
    ///
    /// Window ids are unique and unambiguous, which titles are not: two
    /// documents called "notes.md" are indistinguishable by name, so a pin could
    /// swap between them from one pass to the next. Matching treats this as a
    /// preference and falls back to the title, then to any window of the app.
    ///
    /// **Deliberately not persisted.** An id only means anything to the running
    /// window server: it dies with the window and is handed out again to a later
    /// one. Written to the config it would be worse than absent — on the next
    /// launch it names either nothing at all or, if reused, some unrelated
    /// window of the same application, which is precisely the mistaken identity
    /// the id exists to prevent. It is therefore session state: set when a pin is
    /// made, dropped on save, nil after a reload, and the pin falls back to the
    /// title it also recorded.
    public let windowId: CGWindowID?

    /// Optional sublayout describing internal pane structure for app integration.
    public let sublayout: SublayoutConfig?

    public init(
        application: String?,
        bundleId: String?,
        windowTitles: [String]? = nil,
        windowId: CGWindowID? = nil,
        sublayout: SublayoutConfig? = nil
    ) {
        self.application = application
        self.bundleId = bundleId
        self.windowTitles = windowTitles?.isEmpty == true ? nil : windowTitles
        self.windowId = windowId
        self.sublayout = sublayout
    }

    // Backward-compatible YAML decoding: accepts both `windowTitles` (new) and `windowTitle` (old).
    enum CodingKeys: String, CodingKey {
        case application, bundleId, windowTitles, windowTitle, sublayout
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        application = try c.decodeIfPresent(String.self, forKey: .application)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        // Not read back either, so a hand-edited or older file cannot smuggle
        // in an id that now points at a different window.
        windowId = nil
        if let titles = try c.decodeIfPresent([String].self, forKey: .windowTitles) {
            windowTitles = titles.isEmpty ? nil : titles
        } else if let single = try c.decodeIfPresent(String.self, forKey: .windowTitle) {
            windowTitles = [single]
        } else {
            windowTitles = nil
        }
        sublayout = try c.decodeIfPresent(SublayoutConfig.self, forKey: .sublayout)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(application, forKey: .application)
        try c.encodeIfPresent(bundleId, forKey: .bundleId)
        try c.encodeIfPresent(windowTitles, forKey: .windowTitles)
        // windowId is deliberately absent — see the property. It is session
        // state, and a persisted one would name the wrong window.
        try c.encodeIfPresent(sublayout, forKey: .sublayout)
    }
}

public struct LayoutNode: Codable, Equatable, Sendable {
    public let type: LayoutType
    public let percentage: Double?

    // For pinned type
    public let pinned: PinnedConfig?

    // For columns type
    public let columns: [LayoutNode]?

    // For rows type
    public let rows: [LayoutNode]?

    // For stack type
    public let windows: [PinnedConfig]?

    // For stack type - when true, stack ALL remaining windows here
    public let stackRemaining: Bool?

    // For float_zoomed type
    public let layout: Box<LayoutNode>?
    public let floats: [PinnedConfig]?
    public let zoomed: [PinnedConfig]?

    enum CodingKeys: String, CodingKey {
        case type, percentage, pinned, columns, rows, windows, stackRemaining, layout, floats, zoomed
    }

    public init(
        type: LayoutType,
        percentage: Double? = nil,
        pinned: PinnedConfig? = nil,
        columns: [LayoutNode]? = nil,
        rows: [LayoutNode]? = nil,
        windows: [PinnedConfig]? = nil,
        stackRemaining: Bool? = nil,
        layout: LayoutNode? = nil,
        floats: [PinnedConfig]? = nil,
        zoomed: [PinnedConfig]? = nil
    ) {
        self.type = type
        self.percentage = percentage
        self.pinned = pinned
        self.columns = columns
        self.rows = rows
        self.windows = windows
        self.stackRemaining = stackRemaining
        self.layout = layout.map { Box($0) }
        self.floats = floats
        self.zoomed = zoomed
    }

    // Helper for creating common layouts
    public static func empty(percentage: Double = 100) -> LayoutNode {
        LayoutNode(type: .empty, percentage: percentage)
    }

    public static func pinned(app: String, percentage: Double = 100) -> LayoutNode {
        LayoutNode(
            type: .pinned,
            percentage: percentage,
            pinned: PinnedConfig(application: app, bundleId: nil)
        )
    }

    public static func pinned(app: String? = nil, bundleId: String? = nil, windowTitles: [String]? = nil, percentage: Double = 100, sublayout: SublayoutConfig? = nil) -> LayoutNode {
        LayoutNode(
            type: .pinned,
            percentage: percentage,
            pinned: PinnedConfig(application: app, bundleId: bundleId, windowTitles: windowTitles, sublayout: sublayout)
        )
    }

    public static func columns(_ cols: [LayoutNode]) -> LayoutNode {
        LayoutNode(type: .columns, columns: cols)
    }

    public static func rows(_ rs: [LayoutNode]) -> LayoutNode {
        LayoutNode(type: .rows, rows: rs)
    }

    public static func stack(_ windows: [PinnedConfig]) -> LayoutNode {
        LayoutNode(type: .stack, windows: windows)
    }

    public static func stackAll(percentage: Double = 100) -> LayoutNode {
        LayoutNode(type: .stack, percentage: percentage, stackRemaining: true)
    }
}

// Box wrapper for recursive reference in Codable struct
public final class Box<T: Codable & Equatable & Sendable>: Codable, Equatable, @unchecked Sendable {
    public let value: T

    public init(_ value: T) {
        self.value = value
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(T.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func == (lhs: Box<T>, rhs: Box<T>) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - Screen Configuration

public struct ScreenConfig: Codable, Equatable, Sendable {
    // Map of display name (or "$PRIMARY") to layout
    public var layouts: [String: LayoutNode]

    public static let primaryKey = "$PRIMARY"

    public init(layouts: [String: LayoutNode]) {
        self.layouts = layouts
    }
}

// MARK: - Layout Definition

/// How a layout treats a multi-display setup.
public enum DisplayScope: String, Codable, Sendable {
    /// Every display draws from one pool of windows, and the layout has a single
    /// stack wherever it happens to sit. Moving a window between screens is just
    /// pinning it to a pane on the other screen.
    case shared

    /// Each display keeps to its own windows: a display's panes only claim
    /// windows already on it, and its leftovers go to its own stack. Nothing
    /// crosses screens on its own.
    case perMonitor
}

public struct Layout: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var quickKey: String?

    /// What this layout puts on each display, keyed by display name, with
    /// `$PRIMARY` standing for whichever display is currently the main one.
    ///
    /// One map, not a list of alternatives. A layout used to carry several
    /// "screen sets" and pick between them by scoring how many of each set's
    /// named displays were plugged in. Supporting a second monitor is now a
    /// matter of making another layout, so nothing has to be chosen between:
    /// applying a layout uses whichever of these displays are actually
    /// attached, and degrades for the ones that are not.
    public var screens: ScreenConfig

    /// Optional so layouts written before this existed still decode; absent
    /// means `.shared`, which is what they behaved as.
    public var displayScope: DisplayScope?

    /// The scope to actually calculate with.
    public var effectiveDisplayScope: DisplayScope { displayScope ?? .shared }

    public init(
        id: UUID = UUID(),
        name: String,
        quickKey: String? = nil,
        screens: ScreenConfig = ScreenConfig(layouts: [:]),
        displayScope: DisplayScope? = nil
    ) {
        self.id = id
        self.name = name
        self.quickKey = quickKey
        self.screens = screens
        self.displayScope = displayScope
    }

    // MARK: - Decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, quickKey, screens, displayScope
        /// Only read, never written: the old list of alternatives.
        case screenSets
    }

    /// Reads both shapes, and writes only the new one.
    ///
    /// A config written before screen sets were removed holds a list. There is
    /// no information in the list that survives the change — the whole point of
    /// it was choosing between alternatives — so the most specific set is kept
    /// and the rest dropped. "Most specific" means the one naming the most
    /// displays, which is what the old matcher would have preferred when
    /// everything was plugged in, so a full setup keeps the arrangement it had.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        quickKey = try container.decodeIfPresent(String.self, forKey: .quickKey)
        displayScope = try container.decodeIfPresent(DisplayScope.self, forKey: .displayScope)

        if let screens = try container.decodeIfPresent(ScreenConfig.self, forKey: .screens) {
            self.screens = screens
        } else {
            let sets = try container.decodeIfPresent([ScreenConfig].self, forKey: .screenSets) ?? []
            self.screens = sets.max { $0.layouts.count < $1.layouts.count }
                ?? ScreenConfig(layouts: [:])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(quickKey, forKey: .quickKey)
        try container.encode(screens, forKey: .screens)
        try container.encodeIfPresent(displayScope, forKey: .displayScope)
    }
}

// MARK: - Saved Setup (snapshot of window positions)

public struct SavedWindowPosition: Codable, Equatable, Sendable {
    public let application: String
    public let bundleId: String?
    public let windowTitle: String?
    public let frame: WindowFrame
    public let displayName: String

    public init(application: String, bundleId: String?, windowTitle: String?, frame: WindowFrame, displayName: String) {
        self.application = application
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.frame = frame
        self.displayName = displayName
    }
}

public struct SavedSetup: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var windows: [SavedWindowPosition]

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), windows: [SavedWindowPosition] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.windows = windows
    }
}

// MARK: - Resolving against what is plugged in

public extension ScreenConfig {
    /// The layout to actually place windows with, given the displays present.
    ///
    /// A layout names displays that may or may not be attached. Rather than
    /// choosing between prepared alternatives, one map degrades to fit:
    ///
    /// - a display that is attached keeps its tree;
    /// - a display that is not is dropped, and any window pinned in its tree
    ///   falls back to the stack rather than being left nowhere;
    /// - if the stack itself was on a display that is gone, nothing is left to
    ///   catch those windows, so the whole layout gives way to a single
    ///   fullscreen stack.
    ///
    /// The last rule is why this returns a whole config rather than filtering
    /// in place: losing the stack is not a local repair, it invalidates the
    /// arrangement.
    func resolved(for displays: [Display]) -> ScreenConfig {
        let attached = Set(displays.map(\.name))
        let hasMain = displays.contains { $0.isMain }

        func isPresent(_ key: String) -> Bool {
            key == ScreenConfig.primaryKey ? hasMain : attached.contains(key)
        }

        let kept = layouts.filter { isPresent($0.key) }

        // Nothing left to place windows on at all.
        guard !kept.isEmpty else { return .fullscreenStack }

        // The stack going missing is what collapses a layout, not its absence.
        // A layout that never had one is simply a layout that pins everything
        // and lets the rest lie where it is; falling back for that would
        // rearrange screens the user had deliberately left alone.
        let hadStack = layouts.values.contains { $0.containsStack }
        let keptStack = kept.values.contains { $0.containsStack }
        guard !hadStack || keptStack else { return .fullscreenStack }

        return ScreenConfig(layouts: kept)
    }

    /// A single stack filling the main display: what a layout falls back to
    /// when it can no longer catch windows anywhere.
    static var fullscreenStack: ScreenConfig {
        ScreenConfig(layouts: [primaryKey: LayoutNode(type: .stack, percentage: 100)])
    }
}

public extension LayoutNode {
    /// Whether this tree has somewhere for unpinned windows to land.
    var containsStack: Bool {
        if type == .stack { return true }
        if let columns { return columns.contains { $0.containsStack } }
        if let rows { return rows.contains { $0.containsStack } }
        return false
    }
}
