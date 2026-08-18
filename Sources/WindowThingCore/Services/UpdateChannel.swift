import Foundation

/// How this particular copy of the app can be updated.
///
/// Sparkle updates by replacing the `.app` bundle on disk, which only works
/// when that bundle is somewhere writable. A copy installed by a package
/// manager is not: `/nix/store` is read-only and root-owned, so an update
/// attempt can only fail. Rather than offering a check that is guaranteed to
/// error, the app asks here first and says who owns updates instead.
public enum UpdateChannel: Equatable, Sendable {

    /// A normal install — Sparkle can download and swap the bundle.
    case sparkle

    /// Installed by a package manager into a read-only location. The associated
    /// value names it, for the message shown in the menu.
    case managed(by: String)

    /// Running as a bare executable rather than from a `.app` — a `swift run` or
    /// `.build/debug` binary. There is no bundle to replace.
    case unpackaged

    /// Whether Sparkle should be started and its menu item enabled.
    public var supportsInAppUpdates: Bool { self == .sparkle }

    /// What to show in the menu in place of "Check for Updates…".
    public var unavailableReason: String? {
        switch self {
        case .sparkle:            return nil
        case .managed(let name):  return "Updates managed by \(name)"
        case .unpackaged:         return "Updates unavailable in development builds"
        }
    }
}

public enum UpdateChannelResolver {

    /// Package-manager prefixes that install into a read-only store. Matched on
    /// the *resolved* bundle path — nix-darwin and home-manager both surface the
    /// app as a symlink or alias into /Applications, so the caller has to
    /// resolve symlinks before asking.
    private static let managedPrefixes: [(prefix: String, manager: String)] = [
        ("/nix/store/", "nix")
    ]

    /// Resolve the update channel for a bundle path.
    ///
    /// - Parameter bundlePath: the resolved filesystem path of the running
    ///   bundle, or nil when there is none.
    public static func channel(forBundlePath bundlePath: String?) -> UpdateChannel {
        guard let path = bundlePath, path.hasSuffix(".app") else {
            return .unpackaged
        }

        for entry in managedPrefixes where path.hasPrefix(entry.prefix) {
            return .managed(by: entry.manager)
        }

        return .sparkle
    }
}
