import Foundation
import ServiceManagement
import WindowThingCore

/// Registers the app to start at login.
///
/// `SMAppService.mainApp` registers *this bundle* — no helper target, no
/// separate launchd plist to keep in sync — and macOS shows it under Login
/// Items, where the user can turn it off independently. Because it is keyed to
/// the bundle rather than a path, a Sparkle update in place keeps working.
///
/// This is deliberately unavailable when a package manager owns the install: a
/// nix copy is started by a launchd agent that nix itself writes, so registering
/// a second login item would run two copies of the app. See ``UpdateChannel``,
/// which draws the same distinction for updates.
enum LoginItem {

    /// Whether the app is allowed to manage its own login item.
    static var isSupported: Bool {
        switch UpdateChannelResolver.channel(
            forBundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path) {
        case .sparkle:      return true
        case .managed:      return false
        case .unpackaged:   return false
        }
    }

    /// Why the toggle is unavailable, or nil when it is available.
    static var unavailableReason: String? {
        switch UpdateChannelResolver.channel(
            forBundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path) {
        case .sparkle:           return nil
        case .managed(let by):   return "Managed by \(by)"
        case .unpackaged:        return "Unavailable in development builds"
        }
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isSupported else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
