import Foundation

// MARK: - Layout Types (matching modal-commander structure)

public enum LayoutType: String, Codable, Sendable {
    case stack
    case pinned
    case columns
    case rows
    case floatZoomed = "float_zoomed"
    case empty
}

public struct PinnedConfig: Codable, Equatable, Sendable {
    public let application: String?
    public let bundleId: String?
    /// Specific window titles to pin. nil or empty = all windows of the app.
    public let windowTitles: [String]?

    public init(application: String?, bundleId: String?, windowTitles: [String]? = nil) {
        self.application = application
        self.bundleId = bundleId
        self.windowTitles = windowTitles?.isEmpty == true ? nil : windowTitles
    }

    // Backward-compatible YAML decoding: accepts both `windowTitles` (new) and `windowTitle` (old).
    enum CodingKeys: String, CodingKey {
        case application, bundleId, windowTitles, windowTitle
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        application = try c.decodeIfPresent(String.self, forKey: .application)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        if let titles = try c.decodeIfPresent([String].self, forKey: .windowTitles) {
            windowTitles = titles.isEmpty ? nil : titles
        } else if let single = try c.decodeIfPresent(String.self, forKey: .windowTitle) {
            windowTitles = [single]
        } else {
            windowTitles = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(application, forKey: .application)
        try c.encodeIfPresent(bundleId, forKey: .bundleId)
        try c.encodeIfPresent(windowTitles, forKey: .windowTitles)
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

    public static func pinned(app: String? = nil, bundleId: String? = nil, windowTitles: [String]? = nil, percentage: Double = 100) -> LayoutNode {
        LayoutNode(
            type: .pinned,
            percentage: percentage,
            pinned: PinnedConfig(application: app, bundleId: bundleId, windowTitles: windowTitles)
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

public struct Layout: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var quickKey: String?
    public var screenSets: [ScreenConfig]

    public init(id: UUID = UUID(), name: String, quickKey: String? = nil, screenSets: [ScreenConfig] = []) {
        self.id = id
        self.name = name
        self.quickKey = quickKey
        self.screenSets = screenSets
    }

    // Find the best matching screen set for current display configuration
    public func matchingScreenSet(for displays: [Display]) -> ScreenConfig? {
        guard !screenSets.isEmpty else { return nil }

        let displayNames = Set(displays.map { $0.name })
        var bestScreenSet: ScreenConfig?
        var bestMatchCount = -1

        for screenSet in screenSets {
            let screenSetNames = Set(screenSet.layouts.keys.filter { $0 != ScreenConfig.primaryKey })

            // A screen set matches if all its named displays are available
            // (we ignore $PRIMARY since it always matches the main display)
            guard screenSetNames.isSubset(of: displayNames) || screenSetNames.isEmpty else {
                continue
            }

            // Count how many displays this screen set actually uses
            // This includes both named displays and $PRIMARY
            let matchCount = screenSetNames.count + (screenSet.layouts.keys.contains(ScreenConfig.primaryKey) ? 1 : 0)

            // Prefer screen sets that use more displays
            // For ties, prefer the one that appears earlier (first occurrence wins)
            if matchCount > bestMatchCount {
                bestScreenSet = screenSet
                bestMatchCount = matchCount
            }
        }

        // Return nil if no valid match found (fallback handled by caller)
        return bestScreenSet
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
