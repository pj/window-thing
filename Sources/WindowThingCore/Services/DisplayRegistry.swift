import Foundation

/// Persists the names of every display the machine has ever connected.
/// Used by the screen set editor to offer monitors as picker options
/// even when they are not currently plugged in.
public final class DisplayRegistry: @unchecked Sendable {

    public static let shared = DisplayRegistry()

    private let userDefaultsKey = "seenDisplayNames"
    private var _knownNames: Set<String>

    public init(userDefaults: UserDefaults = .standard) {
        if let stored = userDefaults.stringArray(forKey: "seenDisplayNames") {
            _knownNames = Set(stored)
        } else {
            _knownNames = []
        }
        self.defaults = userDefaults
    }

    private let defaults: UserDefaults

    /// Sorted list of all display names ever observed. Never includes "$PRIMARY".
    public var knownDisplayNames: [String] {
        _knownNames.sorted()
    }

    /// Record the names of the currently connected displays.
    /// New names are appended; existing names are ignored.
    public func record(displays: [Display]) {
        var changed = false
        for display in displays where display.name != ScreenConfig.primaryKey {
            if _knownNames.insert(display.name).inserted {
                changed = true
            }
        }
        if changed {
            defaults.set(Array(_knownNames), forKey: userDefaultsKey)
        }
    }
}
