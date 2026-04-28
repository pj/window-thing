import Foundation
import Yams

// MARK: - Cell Move Error

public enum CellMoveError: Error, Sendable {
    case noActiveLayout
    case addressNotFound(CellAddress)
}

// MARK: - Layout Calculation Result Types

/// Represents a calculated window position
public struct WindowPlacement: Equatable, Sendable {
    public let window: Window
    public let targetFrame: WindowFrame
    public let placementType: PlacementType

    public enum PlacementType: Equatable, Sendable {
        case pinned
        case stacked
        case floating
        case zoomed
    }

    public init(window: Window, targetFrame: WindowFrame, placementType: PlacementType = .pinned) {
        self.window = window
        self.targetFrame = targetFrame
        self.placementType = placementType
    }
}

/// Result of phase 1: finding the stack location and placed windows
public struct LayoutReconcileResult: Equatable {
    public var stackFrame: WindowFrame?
    public var placedWindowIds: Set<UInt32>
    public var placements: [WindowPlacement]

    public init(stackFrame: WindowFrame? = nil, placedWindowIds: Set<UInt32> = [], placements: [WindowPlacement] = []) {
        self.stackFrame = stackFrame
        self.placedWindowIds = placedWindowIds
        self.placements = placements
    }

    public mutating func merge(_ other: LayoutReconcileResult) {
        // Stack frame: keep the first one found (or use the other's if we don't have one)
        if stackFrame == nil {
            stackFrame = other.stackFrame
        }
        placedWindowIds.formUnion(other.placedWindowIds)
        placements.append(contentsOf: other.placements)
    }
}

// MARK: - Layout Calculator (Pure functions for testing)

/// Pure layout calculation engine - no side effects, fully testable
///
/// Uses two-phase reconciliation like modal-commander:
/// 1. Phase 1: Process pinned windows, find the stack location
/// 2. Phase 2: Place all remaining windows at the stack location
public enum LayoutCalculator {

    // MARK: - Public API

    /// Calculate window placements for a layout on given displays
    ///
    /// Processing order:
    /// 1. Non-main displays first (to identify pinned windows)
    /// 2. Main display last (stack collects all remaining windows)
    public static func calculatePlacements(
        layout: Layout,
        displays: [Display],
        windows: [Window]
    ) -> [WindowPlacement] {
        let screenSet: ScreenConfig

        if let matchedScreenSet = layout.matchingScreenSet(for: displays) {
            screenSet = matchedScreenSet
        } else {
            // Fallback: single stack on primary screen when no monitors match
            screenSet = ScreenConfig(layouts: [
                ScreenConfig.primaryKey: LayoutNode(type: .stack, percentage: 100)
            ])
        }

        return calculateScreenSetPlacements(
            screenSet: screenSet,
            displays: displays,
            windows: windows
        )
    }

    /// Calculate placements for a screen set
    public static func calculateScreenSetPlacements(
        screenSet: ScreenConfig,
        displays: [Display],
        windows: [Window]
    ) -> [WindowPlacement] {
        var allPlacements: [WindowPlacement] = []
        var placedWindowIds: Set<UInt32> = []
        var mainDisplayResult: LayoutReconcileResult?
        var mainDisplay: Display?
        var mainFrame: WindowFrame?

        // Sort displays: non-main first, main last
        // This ensures pinned windows on secondary monitors are processed first
        let sortedEntries = screenSet.layouts.sorted { entry1, entry2 in
            let isMain1 = entry1.key == ScreenConfig.primaryKey || displays.first(where: { $0.name == entry1.key })?.isMain == true
            let isMain2 = entry2.key == ScreenConfig.primaryKey || displays.first(where: { $0.name == entry2.key })?.isMain == true
            return !isMain1 && isMain2  // Non-main before main
        }

        for (displayKey, layoutNode) in sortedEntries {
            let targetDisplay: Display?

            if displayKey == ScreenConfig.primaryKey {
                targetDisplay = displays.first(where: { $0.isMain })
            } else {
                targetDisplay = displays.first(where: { $0.name == displayKey })
            }

            guard let display = targetDisplay else {
                continue
            }

            let isMainDisplay = display.isMain

            // Phase 1: Reconcile the layout (find stack, place pinned windows)
            let result = reconcileLayout(
                node: layoutNode,
                frame: display.frame,
                screenFrame: display.frame,
                windows: windows,
                placedWindowIds: placedWindowIds
            )

            if isMainDisplay {
                // Save main display for phase 2
                mainDisplayResult = result
                mainDisplay = display
                mainFrame = display.frame
            }

            // Add placements and track placed windows
            allPlacements.append(contentsOf: result.placements)
            placedWindowIds.formUnion(result.placedWindowIds)
        }

        // Phase 2: Stack remaining windows on main display
        if let stackFrame = mainDisplayResult?.stackFrame, let _ = mainDisplay {
            let remainingWindows = windows.filter { !placedWindowIds.contains($0.id) }
            for window in remainingWindows {
                allPlacements.append(WindowPlacement(
                    window: window,
                    targetFrame: stackFrame,
                    placementType: .stacked
                ))
            }
        } else if let frame = mainFrame {
            // No stack found - place remaining windows fullscreen on main display
            let remainingWindows = windows.filter { !placedWindowIds.contains($0.id) }
            for window in remainingWindows {
                allPlacements.append(WindowPlacement(
                    window: window,
                    targetFrame: frame,
                    placementType: .stacked
                ))
            }
        }

        return allPlacements
    }

    // MARK: - Phase 1: Layout Reconciliation

    /// Reconcile a layout node - finds stack location and places pinned windows
    /// Returns: stack location, set of placed window IDs, and placements
    public static func reconcileLayout(
        node: LayoutNode,
        frame: WindowFrame,
        screenFrame: WindowFrame,
        windows: [Window],
        placedWindowIds: Set<UInt32>
    ) -> LayoutReconcileResult {
        var result = LayoutReconcileResult()

        switch node.type {
        case .empty:
            // Empty nodes receive NO windows - they're just placeholders
            break

        case .pinned:
            guard let pinned = node.pinned else { break }

            // Find matching window that hasn't been placed
            if let window = windows.first(where: {
                !placedWindowIds.contains($0.id) && windowMatches($0, pinned: pinned)
            }) {
                result.placements.append(WindowPlacement(
                    window: window,
                    targetFrame: frame,
                    placementType: .pinned
                ))
                result.placedWindowIds.insert(window.id)
            }

        case .columns:
            guard let columns = node.columns else { break }
            result = reconcileColumns(
                columns: columns,
                frame: frame,
                screenFrame: screenFrame,
                windows: windows,
                placedWindowIds: placedWindowIds
            )

        case .rows:
            guard let rows = node.rows else { break }
            result = reconcileRows(
                rows: rows,
                frame: frame,
                screenFrame: screenFrame,
                windows: windows,
                placedWindowIds: placedWindowIds
            )

        case .stack:
            // Stack is the catchall - record its location
            // It will collect all remaining windows in phase 2
            result.stackFrame = frame

            // Also place any specifically pinned windows in the stack
            if let stackWindows = node.windows {
                for pinnedConfig in stackWindows {
                    if let window = windows.first(where: {
                        !placedWindowIds.contains($0.id) &&
                        !result.placedWindowIds.contains($0.id) &&
                        windowMatches($0, pinned: pinnedConfig)
                    }) {
                        result.placements.append(WindowPlacement(
                            window: window,
                            targetFrame: frame,
                            placementType: .stacked
                        ))
                        result.placedWindowIds.insert(window.id)
                    }
                }
            }

        case .floatZoomed:
            result = reconcileFloatZoomed(
                node: node,
                frame: frame,
                screenFrame: screenFrame,
                windows: windows,
                placedWindowIds: placedWindowIds
            )
        }

        return result
    }

    // MARK: - Container Reconciliation

    private static func reconcileColumns(
        columns: [LayoutNode],
        frame: WindowFrame,
        screenFrame: WindowFrame,
        windows: [Window],
        placedWindowIds: Set<UInt32>
    ) -> LayoutReconcileResult {
        let columnFrames = calculateColumnFrames(columns: columns, containerFrame: frame)
        var result = LayoutReconcileResult()
        var currentPlacedIds = placedWindowIds

        for (column, colFrame) in zip(columns, columnFrames) {
            let colResult = reconcileLayout(
                node: column,
                frame: colFrame,
                screenFrame: screenFrame,
                windows: windows,
                placedWindowIds: currentPlacedIds
            )
            result.merge(colResult)
            currentPlacedIds.formUnion(colResult.placedWindowIds)
        }

        return result
    }

    private static func reconcileRows(
        rows: [LayoutNode],
        frame: WindowFrame,
        screenFrame: WindowFrame,
        windows: [Window],
        placedWindowIds: Set<UInt32>
    ) -> LayoutReconcileResult {
        let rowFrames = calculateRowFrames(rows: rows, containerFrame: frame)
        var result = LayoutReconcileResult()
        var currentPlacedIds = placedWindowIds

        for (row, rowFrame) in zip(rows, rowFrames) {
            let rowResult = reconcileLayout(
                node: row,
                frame: rowFrame,
                screenFrame: screenFrame,
                windows: windows,
                placedWindowIds: currentPlacedIds
            )
            result.merge(rowResult)
            currentPlacedIds.formUnion(rowResult.placedWindowIds)
        }

        return result
    }

    // MARK: - Float/Zoomed Reconciliation

    private static func reconcileFloatZoomed(
        node: LayoutNode,
        frame: WindowFrame,
        screenFrame: WindowFrame,
        windows: [Window],
        placedWindowIds: Set<UInt32>
    ) -> LayoutReconcileResult {
        var result = LayoutReconcileResult()
        var currentPlacedIds = placedWindowIds

        // First, process floating windows - they keep their current position
        // but are constrained to the screen bounds
        if let floats = node.floats {
            for pinnedConfig in floats {
                if let window = windows.first(where: {
                    !currentPlacedIds.contains($0.id) && windowMatches($0, pinned: pinnedConfig)
                }) {
                    // Keep window's current position, but constrain to screen
                    var windowFrame = window.frame
                    windowFrame.x = max(screenFrame.x, min(windowFrame.x, screenFrame.x + screenFrame.width - windowFrame.width))
                    windowFrame.y = max(screenFrame.y, min(windowFrame.y, screenFrame.y + screenFrame.height - windowFrame.height))

                    result.placements.append(WindowPlacement(
                        window: window,
                        targetFrame: windowFrame,
                        placementType: .floating
                    ))
                    result.placedWindowIds.insert(window.id)
                    currentPlacedIds.insert(window.id)
                }
            }
        }

        // Process zoomed windows - they go fullscreen on the screen
        if let zoomed = node.zoomed {
            for pinnedConfig in zoomed {
                if let window = windows.first(where: {
                    !currentPlacedIds.contains($0.id) && windowMatches($0, pinned: pinnedConfig)
                }) {
                    result.placements.append(WindowPlacement(
                        window: window,
                        targetFrame: screenFrame,
                        placementType: .zoomed
                    ))
                    result.placedWindowIds.insert(window.id)
                    currentPlacedIds.insert(window.id)
                }
            }
        }

        // Process the base layout
        if let baseLayout = node.layout?.value {
            let baseResult = reconcileLayout(
                node: baseLayout,
                frame: frame,
                screenFrame: screenFrame,
                windows: windows,
                placedWindowIds: currentPlacedIds
            )
            result.merge(baseResult)
        }

        return result
    }

    // MARK: - Window Matching

    /// Check if a window matches a pinned config
    public static func windowMatches(_ window: Window, pinned: PinnedConfig) -> Bool {
        // If bundleId is specified, it must match
        if let bundleId = pinned.bundleId {
            if window.bundleId != bundleId {
                return false
            }
        }

        // If application name is specified, it must match (case insensitive, partial)
        if let appName = pinned.application {
            if !window.application.lowercased().contains(appName.lowercased()) {
                return false
            }
        }

        // If specific window titles are listed, at least one must match (partial)
        if let titles = pinned.windowTitles, !titles.isEmpty {
            if !titles.contains(where: { window.title.contains($0) }) {
                return false
            }
        }

        // At least one criterion must be specified
        if pinned.bundleId == nil && pinned.application == nil {
            return false
        }

        return true
    }

    /// Find a window matching the pinned config
    public static func findMatchingWindow(for pinned: PinnedConfig, in windows: [Window]) -> Window? {
        return windows.first { windowMatches($0, pinned: pinned) }
    }

    // MARK: - Frame Calculation

    /// Calculate frames for column layout
    public static func calculateColumnFrames(
        columns: [LayoutNode],
        containerFrame: WindowFrame
    ) -> [WindowFrame] {
        var result: [WindowFrame] = []
        var currentX = containerFrame.x

        let explicitTotal = columns.compactMap { $0.percentage }.reduce(0, +)
        let autoSizedCount = columns.filter { $0.percentage == nil }.count
        let remainder = max(0, 100.0 - explicitTotal)
        let autoPercentage = autoSizedCount > 0 ? remainder / Double(autoSizedCount) : 0

        let effectivePercentages = columns.map { $0.percentage ?? autoPercentage }
        let total = effectivePercentages.reduce(0, +)

        for (_, percentage) in zip(columns, effectivePercentages) {
            let normalizedPercentage = total > 0 ? (percentage / total) : (1.0 / Double(columns.count))
            let columnWidth = containerFrame.width * CGFloat(normalizedPercentage)

            result.append(WindowFrame(
                x: currentX,
                y: containerFrame.y,
                width: columnWidth,
                height: containerFrame.height
            ))
            currentX += columnWidth
        }

        return result
    }

    /// Calculate frames for row layout
    public static func calculateRowFrames(
        rows: [LayoutNode],
        containerFrame: WindowFrame
    ) -> [WindowFrame] {
        var result: [WindowFrame] = []
        var currentY = containerFrame.y

        let explicitTotal = rows.compactMap { $0.percentage }.reduce(0, +)
        let autoSizedCount = rows.filter { $0.percentage == nil }.count
        let remainder = max(0, 100.0 - explicitTotal)
        let autoPercentage = autoSizedCount > 0 ? remainder / Double(autoSizedCount) : 0

        let effectivePercentages = rows.map { $0.percentage ?? autoPercentage }
        let total = effectivePercentages.reduce(0, +)

        for (_, percentage) in zip(rows, effectivePercentages) {
            let normalizedPercentage = total > 0 ? (percentage / total) : (1.0 / Double(rows.count))
            let rowHeight = containerFrame.height * CGFloat(normalizedPercentage)

            result.append(WindowFrame(
                x: containerFrame.x,
                y: currentY,
                width: containerFrame.width,
                height: rowHeight
            ))
            currentY += rowHeight
        }

        return result
    }

    // MARK: - Convenience Methods (Backward Compatibility)

    /// Calculate placements for a single layout node (convenience wrapper for testing)
    public static func calculateNodePlacements(
        node: LayoutNode,
        frame: WindowFrame,
        windows: [Window]
    ) -> [WindowPlacement] {
        let result = reconcileLayout(
            node: node,
            frame: frame,
            screenFrame: frame,
            windows: windows,
            placedWindowIds: []
        )

        // For stack nodes, also place remaining windows
        if result.stackFrame != nil {
            var placements = result.placements
            let remainingWindows = windows.filter { !result.placedWindowIds.contains($0.id) }
            for window in remainingWindows {
                placements.append(WindowPlacement(
                    window: window,
                    targetFrame: result.stackFrame!,
                    placementType: .stacked
                ))
            }
            return placements
        }

        return result.placements
    }
}

// MARK: - Layout Manager (Orchestration with side effects)

public class LayoutManager: LayoutManaging {
    public static let shared = LayoutManager(windowManager: WindowManager.shared)

    public private(set) var layouts: [Layout] = []
    public private(set) var savedSetups: [SavedSetup] = []
    public internal(set) var currentLayout: Layout?  // Allow internal modification for dynamic layout changes

    /// The most recently applied layout. Persisted across app restarts via UserDefaults.
    public private(set) var lastUsedLayout: Layout?

    private let windowManager: WindowManaging
    private let defaults: UserDefaults

    public init(windowManager: WindowManaging, userDefaults: UserDefaults = .standard) {
        self.windowManager = windowManager
        self.defaults = userDefaults
    }

    // MARK: - Layout Loading

    public func loadLayouts(from config: AppConfig) {
        layouts = config.layouts

        // Restore lastUsedLayout from UserDefaults
        if let uuidString = defaults.string(forKey: "lastUsedLayoutId"),
           let uuid = UUID(uuidString: uuidString) {
            lastUsedLayout = layouts.first { $0.id == uuid }
        }

        // Apply default layout if configured
        if let defaultName = config.defaultLayoutName,
           let defaultLayout = layouts.first(where: { $0.name == defaultName || $0.quickKey == defaultName }) {
            applyLayout(defaultLayout)
        }
    }

    // MARK: - Layout Application

    public func updateLayout(_ layout: Layout) {
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[index] = layout
            // If this is the current layout, update the reference
            if currentLayout?.id == layout.id {
                currentLayout = layout
            }
        }
    }

    public func applyLayout(_ layout: Layout) {
        let displays = windowManager.getDisplays()
        let windows = windowManager.getWindows()

        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        currentLayout = layout
        lastUsedLayout = layout
        defaults.set(layout.id.uuidString, forKey: "lastUsedLayoutId")

        // Apply all placements
        for placement in placements {
            _ = windowManager.setWindowFrame(
                pid: placement.window.pid,
                windowId: placement.window.id,
                frame: placement.targetFrame
            )
        }
    }

    // MARK: - Cell Movement

    /// Move `window` to the cell identified by `address` in the current (or last-used) layout.
    /// If no layout is active, auto-applies `lastUsedLayout` first.
    /// Throws `CellMoveError.addressNotFound` if the address has no corresponding cell.
    public func moveWindow(_ window: Window, toCellAt address: CellAddress, displays: [Display]) throws {
        // Auto-apply last-used layout if nothing is current
        if currentLayout == nil, let last = lastUsedLayout {
            applyLayout(last)
        }
        guard let layout = currentLayout else {
            throw CellMoveError.noActiveLayout
        }
        let cells = CellIndexer.indexCells(layout: layout, displays: displays)
        guard let cell = cells.first(where: { $0.address == address }) else {
            throw CellMoveError.addressNotFound(address)
        }
        _ = windowManager.setWindowFrame(
            pid: window.pid,
            windowTitle: window.title,
            frame: cell.frame
        )
    }

    /// Return the current set of indexed cells for `layout` on the given displays.
    public func cellAddresses(for layout: Layout, displays: [Display]) -> [IndexedCell] {
        CellIndexer.indexCells(layout: layout, displays: displays)
    }

    /// Re-apply the current layout (for automatic reconciliation)
    /// This is called when windows/monitors change to maintain the layout
    public func reconcileCurrentLayout() {
        guard let layout = currentLayout else { return }

        let displays = windowManager.getDisplays()
        let windows = windowManager.getWindows()

        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // Apply all placements
        for placement in placements {
            _ = windowManager.setWindowFrame(
                pid: placement.window.pid,
                windowId: placement.window.id,
                frame: placement.targetFrame
            )
        }
    }

    // MARK: - Saved Setups

    public func loadSavedSetups() {
        let setupsPath = ConfigManager.shared.setupsFilePath

        guard FileManager.default.fileExists(atPath: setupsPath.path) else {
            return
        }

        do {
            let yamlString = try String(contentsOf: setupsPath, encoding: .utf8)
            let decoder = YAMLDecoder()
            savedSetups = try decoder.decode([SavedSetup].self, from: yamlString)
        } catch {
            print("Error loading saved setups: \(error)")
        }
    }

    public func saveCurrentSetup(name: String) {
        let displays = windowManager.getDisplays()
        let windows = windowManager.getWindows()

        var savedWindows: [SavedWindowPosition] = []

        for window in windows {
            let displayName = displays.first { display in
                let displayRect = display.frame.cgRect
                let windowCenter = CGPoint(
                    x: window.frame.x + window.frame.width / 2,
                    y: window.frame.y + window.frame.height / 2
                )
                return displayRect.contains(windowCenter)
            }?.name ?? "Unknown"

            savedWindows.append(SavedWindowPosition(
                application: window.application,
                bundleId: window.bundleId,
                windowTitle: window.title,
                frame: window.frame,
                displayName: displayName
            ))
        }

        let setup = SavedSetup(name: name, windows: savedWindows)
        savedSetups.append(setup)
        saveSavedSetups()
    }

    public func loadSetup(_ setup: SavedSetup) {
        let windows = windowManager.getWindows()

        for savedPosition in setup.windows {
            if let window = windows.first(where: {
                ($0.bundleId == savedPosition.bundleId || $0.application == savedPosition.application) &&
                (savedPosition.windowTitle?.isEmpty != false || $0.title.contains(savedPosition.windowTitle!))
            }) {
                _ = windowManager.setWindowFrame(
                    pid: window.pid,
                    windowTitle: window.title,
                    frame: savedPosition.frame
                )
            }
        }
    }

    public func deleteSetup(_ setup: SavedSetup) {
        savedSetups.removeAll { $0.id == setup.id }
        saveSavedSetups()
    }

    private func saveSavedSetups() {
        do {
            let encoder = YAMLEncoder()
            let yamlString = try encoder.encode(savedSetups)

            let header = """
            # WindowThing Saved Setups
            # ------------------------
            # These are your saved window arrangements.
            # You can edit this file manually or use the app to save new setups.

            """

            try (header + yamlString).write(to: ConfigManager.shared.setupsFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving setups: \(error)")
        }
    }

    // MARK: - Quick Actions

    public func getLayoutByQuickKey(_ key: String) -> Layout? {
        return layouts.first { $0.quickKey == key }
    }

    public func applyLayoutByQuickKey(_ key: String) -> Bool {
        guard let layout = getLayoutByQuickKey(key) else {
            return false
        }
        applyLayout(layout)
        return true
    }
}
