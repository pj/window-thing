import Foundation

/// Pure functions for editing screen sets (adding, removing, renaming display keys).
public enum ScreenSetModification {

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

extension Layout {
    /// Return a copy with a new display key added to the screen set at `index`.
    public func addingDisplay(
        key: String,
        defaultNode: LayoutNode = .stackAll(),
        toScreenSetAt index: Int
    ) -> Layout? {
        guard index >= 0 && index < screenSets.count else { return nil }
        var copy = self
        copy.screenSets[index] = ScreenSetModification.addDisplay(
            key: key, defaultNode: defaultNode, to: screenSets[index]
        )
        return copy
    }

    /// Return a copy with a display key removed from the screen set at `index`.
    /// Returns nil if the key doesn't exist in that screen set.
    public func removingDisplay(
        key: String,
        fromScreenSetAt index: Int
    ) -> Layout? {
        guard index >= 0 && index < screenSets.count,
              let updated = ScreenSetModification.removeDisplay(key: key, from: screenSets[index])
        else { return nil }
        var copy = self
        copy.screenSets[index] = updated
        return copy
    }

    /// Return a copy with a display key renamed in the screen set at `index`.
    /// Returns nil if oldKey doesn't exist or newKey already exists.
    public func renamingDisplay(
        from oldKey: String,
        to newKey: String,
        inScreenSetAt index: Int
    ) -> Layout? {
        guard index >= 0 && index < screenSets.count,
              let updated = ScreenSetModification.renameDisplay(from: oldKey, to: newKey, in: screenSets[index])
        else { return nil }
        var copy = self
        copy.screenSets[index] = updated
        return copy
    }
}
