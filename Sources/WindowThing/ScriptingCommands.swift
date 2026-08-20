import AppKit
import Carbon
import Foundation
import WindowThingCore

/// AppleScript commands. See `packaging/WindowThing.sdef` for the terminology.
///
/// Each is named with `@objc(...)` because the sdef resolves handlers by
/// Objective-C class name, and Swift would otherwise mangle them into something
/// the runtime can't find — the failure being a silent "command not handled"
/// rather than anything that points at the cause.
///
/// Everything here runs on the main thread: AppleScript delivers commands on it,
/// and both the layout manager and the surface expect that.

/// Convenience for reaching the app from a command.
private var appDelegate: AppDelegate? {
    AppDelegate.shared
}

private extension NSScriptCommand {
    /// The app delegate, or a script error saying so.
    ///
    /// Returning nil quietly would make a command that cannot reach the app
    /// indistinguishable from one that succeeded and had nothing to say, which
    /// is the worst kind of failure to debug from a script.
    func requireDelegate() -> AppDelegate? {
        guard let delegate = appDelegate else {
            scriptErrorNumber = -1728  // errAENoSuchObject
            scriptErrorString = "WindowThing is running but its app delegate is unavailable."
            return nil
        }
        return delegate
    }
}

@objc(WTListLayoutsCommand)
final class WTListLayoutsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        LayoutManager.shared.layouts.map(\.name)
    }
}

@objc(WTCurrentLayoutCommand)
final class WTCurrentLayoutCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Empty rather than missing value: scripts can compare it without
        // having to guard, and "no layout applied yet" is not an error.
        LayoutManager.shared.currentLayout?.name
            ?? LayoutManager.shared.lastUsedLayout?.name
            ?? ""
    }
}

@objc(WTApplyLayoutCommand)
final class WTApplyLayoutCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let name = directParameter as? String else {
            // -1701 is errAEDescNotFound, which AppleScript reports as a
            // missing parameter. Spelled numerically because the OSA constants
            // are not exposed to Swift.
            scriptErrorNumber = -1701
            scriptErrorString = "apply layout needs the name of a layout."
            return false
        }

        let manager = LayoutManager.shared
        guard let layout = manager.layouts.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            // Not a script error: asking for a layout that isn't there is a
            // reasonable question with a false answer, and raising would stop a
            // script that is probing.
            return false
        }

        manager.applyLayout(layout)
        return true
    }
}

@objc(WTShowSurfaceCommand)
final class WTShowSurfaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let delegate = requireDelegate() else { return nil }

        let pinned = (evaluatedArguments?["pinned"] as? Bool) ?? false
        delegate.spaceOverlay.staysVisibleWhenInactive = pinned
        delegate.showSpaceOverlayForScripting()
        return nil
    }
}

@objc(WTHideSurfaceCommand)
final class WTHideSurfaceCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let delegate = requireDelegate() else { return nil }
        delegate.spaceOverlay.staysVisibleWhenInactive = false
        delegate.spaceOverlay.hide()
        return nil
    }
}

@objc(WTSurfaceIsOpenCommand)
final class WTSurfaceIsOpenCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        appDelegate?.spaceOverlay.isVisible ?? false
    }
}

@objc(WTAddLayoutCommand)
final class WTAddLayoutCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let delegate = requireDelegate() else { return nil }
        let before = Set(LayoutManager.shared.layouts.map(\.id))
        delegate.spaceOverlay.viewModel.addLayout()
        // Return the name so a script can act on what it just made without
        // having to guess how the app names new layouts.
        return LayoutManager.shared.layouts.first { !before.contains($0.id) }?.name ?? ""
    }
}

@objc(WTRenameLayoutCommand)
final class WTRenameLayoutCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let current = directParameter as? String,
              let replacement = evaluatedArguments?["newName"] as? String else {
            scriptErrorNumber = -1701
            scriptErrorString = "rename layout needs a layout name and a `to` name."
            return false
        }
        guard let delegate = requireDelegate() else { return nil }

        let viewModel = delegate.spaceOverlay.viewModel
        guard var layout = LayoutManager.shared.layouts.first(where: {
            $0.name.caseInsensitiveCompare(current) == .orderedSame
        }) else { return false }

        layout.name = replacement
        viewModel.updateLayoutMeta(layout)
        return true
    }
}

@objc(WTDeleteLayoutCommand)
final class WTDeleteLayoutCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let name = directParameter as? String else {
            scriptErrorNumber = -1701
            scriptErrorString = "delete layout needs the name of a layout."
            return false
        }
        guard let delegate = requireDelegate() else { return nil }

        let manager = LayoutManager.shared
        guard manager.layouts.count > 1,
              let layout = manager.layouts.first(where: {
                  $0.name.caseInsensitiveCompare(name) == .orderedSame
              }) else { return false }

        delegate.spaceOverlay.viewModel.deleteLayout(layout)
        return true
    }
}
