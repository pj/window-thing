import Foundation

/// Pure functions for editing a layout's display map — adding, removing and
/// renaming the display keys it holds.
///
/// These used to operate on one screen set chosen out of several. There is only
/// one map now, so the index is gone; what they do to it is unchanged.
public enum ScreenModification {

    /// The standard default layout node for a newly-added display.
    public static var defaultDisplayNode: LayoutNode { .stackAll() }

    /// Add a new display key to a screen config with a given layout node.
    /// If the key already exists, replaces its layout node.
    public static func addDisplay(
        key: String,
        defaultNode: LayoutNode = .stackAll(),
        to screenConfig: ScreenConfig
    ) -> ScreenConfig {
        var layouts = screenConfig.layouts
        layouts[key] = defaultNode
        return ScreenConfig(layouts: layouts)
    }

    /// Remove a display key from a screen config.
    /// Returns nil if the key doesn't exist.
    public static func removeDisplay(
        key: String,
        from screenConfig: ScreenConfig
    ) -> ScreenConfig? {
        guard screenConfig.layouts[key] != nil else { return nil }
        var layouts = screenConfig.layouts
        layouts.removeValue(forKey: key)
        return ScreenConfig(layouts: layouts)
    }

    /// Rename a display key within a screen config, preserving its layout node.
    /// Returns nil if oldKey doesn't exist or newKey already exists.
    public static func renameDisplay(
        from oldKey: String,
        to newKey: String,
        in screenConfig: ScreenConfig
    ) -> ScreenConfig? {
        guard let node = screenConfig.layouts[oldKey] else { return nil }
        guard screenConfig.layouts[newKey] == nil else { return nil }
        var layouts = screenConfig.layouts
        layouts.removeValue(forKey: oldKey)
        layouts[newKey] = node
        return ScreenConfig(layouts: layouts)
    }
}

// MARK: - Layout Convenience Extensions

public extension Layout {

    /// Give a display its own tree in this layout.
    ///
    /// Adding a display used to mean picking which of a layout's screen sets to
    /// add it to. With one map there is nothing to pick.
    func addingDisplay(key: String, defaultNode: LayoutNode = .stackAll()) -> Layout {
        var copy = self
        copy.screens = ScreenModification.addDisplay(key: key, defaultNode: defaultNode, to: screens)
        return copy
    }

    func removingDisplay(key: String) -> Layout? {
        guard let updated = ScreenModification.removeDisplay(key: key, from: screens) else {
            return nil
        }
        var copy = self
        copy.screens = updated
        return copy
    }

    func renamingDisplay(from oldKey: String, to newKey: String) -> Layout? {
        guard let updated = ScreenModification.renameDisplay(from: oldKey, to: newKey, in: screens) else {
            return nil
        }
        var copy = self
        copy.screens = updated
        return copy
    }
}

// MARK: - The one-stack invariant

public extension ScreenConfig {
    /// Display keys whose tree holds a stack.
    var stackKeys: [String] {
        layouts.filter { $0.value.containsStack }.keys.sorted()
    }

    /// Whether this layout has somewhere for unpinned windows to land.
    var containsStack: Bool { !stackKeys.isEmpty }

    /// A layout needs exactly one stack: two would both claim every unpinned
    /// window. Older versions could write a second — notably when adding a
    /// display, which used to default the new monitor to a full stack.
    func deduplicatingStacks() -> ScreenConfig {
        let keys = stackKeys
        guard keys.count > 1 else { return self }

        var copy = self
        for key in keys.dropFirst() {
            guard let node = copy.layouts[key],
                  let indices = node.findStackLocation() else { continue }
            let path = NodePath(indices)
            let percentage = (path.isRoot ? node : path.node(in: node))?.percentage
            copy.layouts[key] = node.replacingNode(
                at: indices,
                with: .empty(percentage: percentage ?? 100)
            ) ?? node
        }
        return copy
    }
}

public extension Layout {
    func deduplicatingStacks() -> Layout {
        var copy = self
        copy.screens = screens.deduplicatingStacks()
        return copy
    }

    /// Every layout has a tree for the main display, so every layout applies.
    ///
    /// The stack can sit on a secondary display, and `ScreenConfig.resolved`
    /// falls all the way back to a fullscreen stack when that display is gone.
    /// This makes the common case not need that: whatever else is unplugged,
    /// there is always something on the screen you are definitely looking at.
    func ensuringPrimaryDisplay() -> Layout {
        guard screens.layouts[ScreenConfig.primaryKey] == nil else { return self }
        var copy = self
        copy.screens.layouts[ScreenConfig.primaryKey] =
            screens.containsStack ? .empty() : .stackAll()
        return copy
    }

    /// The name a layout gets when it has none.
    public static let fallbackName = "Untitled"

    /// Every layout is nameable, because a layout is picked by its name.
    ///
    /// A layout with a blank name is unusable rather than merely untidy: it is
    /// an empty row in the menubar and a chip with nothing written on it, and
    /// the only handle for renaming it is the name it does not have. Applied on
    /// load so a config that already carries one — written by an earlier build,
    /// or by hand — is repaired rather than carried forward.
    func ensuringName() -> Layout {
        guard name.trimmingCharacters(in: .whitespaces).isEmpty else { return self }
        var copy = self
        copy.name = Self.fallbackName
        return copy
    }
}
