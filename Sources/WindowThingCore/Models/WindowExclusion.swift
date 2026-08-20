import Foundation

/// A rule for windows a layout should leave alone.
///
/// Most transient UI can be spotted automatically — menus and popovers report a
/// non-standard Accessibility subrole, or none at all, and are filtered without
/// anyone having to say so. Some windows cannot. Finder's Get Info window is a
/// genuine `AXStandardWindow`: movable, resizable, listed by Accessibility, and
/// indistinguishable by any attribute from Activity Monitor or System Settings,
/// which are windows you very much do want placed. Asking for it by name is the
/// honest answer, rather than inventing a heuristic that quietly drops real
/// windows to catch it.
///
/// Every field given must match. A rule with no fields matches nothing, so a
/// malformed entry cannot swallow the whole session's windows.
public struct WindowExclusion: Codable, Equatable, Sendable {

    /// Application name, matched case-insensitively in full.
    public let application: String?
    /// Bundle identifier, matched exactly.
    public let bundleId: String?
    /// Substring the window's title must contain, matched case-insensitively.
    public let titleContains: String?

    public init(application: String? = nil, bundleId: String? = nil, titleContains: String? = nil) {
        self.application = application
        self.bundleId = bundleId
        self.titleContains = titleContains
    }

    /// Whether this rule says anything at all. An empty rule is ignored rather
    /// than treated as "matches everything".
    public var isMeaningful: Bool {
        application != nil || bundleId != nil || titleContains != nil
    }

    public func matches(_ window: Window) -> Bool {
        guard isMeaningful else { return false }

        if let application,
           window.application.caseInsensitiveCompare(application) != .orderedSame {
            return false
        }
        if let bundleId, window.bundleId != bundleId {
            return false
        }
        if let titleContains,
           window.title.range(of: titleContains, options: .caseInsensitive) == nil {
            return false
        }
        return true
    }
}

public extension Array where Element == WindowExclusion {
    /// Whether any rule claims this window.
    func excludes(_ window: Window) -> Bool {
        contains { $0.matches(window) }
    }
}

public extension WindowExclusion {
    /// Applied when the config says nothing, and replaced wholesale the moment
    /// it does — so what is in the file is what is in effect, with nothing
    /// invisible added on top.
    ///
    /// Finder's Get Info windows are titled "<name> Info" and are otherwise
    /// identical to real Finder windows.
    static let defaults: [WindowExclusion] = [
        WindowExclusion(bundleId: "com.apple.finder", titleContains: " Info")
    ]
}
