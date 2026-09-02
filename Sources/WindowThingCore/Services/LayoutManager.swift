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
        return calculateScreenSetPlacements(
            screenSet: layout.screens.resolved(for: displays),
            displays: displays,
            windows: windows,
            scope: layout.effectiveDisplayScope
        )
    }

    /// Calculate placements for a screen set
    public static func calculateScreenSetPlacements(
        screenSet: ScreenConfig,
        displays: [Display],
        windows: [Window],
        scope: DisplayScope = .shared
    ) -> [WindowPlacement] {
        switch scope {
        case .shared:     return sharedPlacements(screenSet: screenSet, displays: displays, windows: windows)
        case .perMonitor: return perMonitorPlacements(screenSet: screenSet, displays: displays, windows: windows)
        }
    }

    /// The display a window is currently on, by its centre point. Falls back to
    /// the main display for windows sitting off every screen.
    public static func display(containing window: Window, in displays: [Display]) -> Display? {
        let centre = CGPoint(
            x: window.frame.x + window.frame.width / 2,
            y: window.frame.y + window.frame.height / 2
        )
        return displays.first { $0.frame.cgRect.contains(centre) }
            ?? displays.first { $0.isMain }
            ?? displays.first
    }

    /// Resolve a screen set key to a display. `$PRIMARY` means the main display.
    private static func display(forKey key: String, in displays: [Display]) -> Display? {
        key == ScreenConfig.primaryKey
            ? displays.first(where: { $0.isMain })
            : displays.first(where: { $0.name == key })
    }

    /// Displays in processing order: secondaries first so their pinned panes
    /// claim their windows before the stack sweeps up whatever is left.
    private static func orderedEntries(
        _ screenSet: ScreenConfig,
        displays: [Display]
    ) -> [(key: String, node: LayoutNode, display: Display)] {
        screenSet.layouts
            .compactMap { key, node in
                display(forKey: key, in: displays).map { (key: key, node: node, display: $0) }
            }
            .sorted { !$0.display.isMain && $1.display.isMain }
    }

    // MARK: - Shared scope

    /// One pool of windows across every display, and one stack for the layout.
    private static func sharedPlacements(
        screenSet: ScreenConfig,
        displays: [Display],
        windows: [Window]
    ) -> [WindowPlacement] {
        var allPlacements: [WindowPlacement] = []
        var placedWindowIds: Set<UInt32> = []
        var stackFrame: WindowFrame?
        var fallbackFrame: WindowFrame?

        for entry in orderedEntries(screenSet, displays: displays) {
            let result = reconcileLayout(
                node: entry.node,
                frame: entry.display.frame,
                screenFrame: entry.display.frame,
                windows: windows,
                placedWindowIds: placedWindowIds
            )

            // The layout has one stack; take it wherever it turns up. The main
            // display wins a tie, since that is where it usually lives.
            if let found = result.stackFrame, stackFrame == nil || entry.display.isMain {
                stackFrame = found
            }
            // With no stack anywhere, leftovers go fullscreen on the main display —
            // but only when the layout actually covers it. A layout that describes
            // just a secondary display has no opinion about the rest of the
            // windows, so they are left where they are rather than being dragged
            // onto a screen the layout never mentioned.
            if entry.display.isMain { fallbackFrame = entry.display.frame }

            allPlacements.append(contentsOf: result.placements)
            placedWindowIds.formUnion(result.placedWindowIds)
        }

        // Everything unclaimed lands in the one stack.
        if let target = stackFrame ?? fallbackFrame {
            for window in windows where !placedWindowIds.contains(window.id) {
                allPlacements.append(WindowPlacement(
                    window: window,
                    targetFrame: target,
                    placementType: .stacked
                ))
            }
        }

        return allPlacements
    }

    // MARK: - Per-monitor scope

    /// Each display is its own little layout: its panes only see windows already
    /// on that display, and its leftovers stack there rather than migrating.
    private static func perMonitorPlacements(
        screenSet: ScreenConfig,
        displays: [Display],
        windows: [Window]
    ) -> [WindowPlacement] {
        var allPlacements: [WindowPlacement] = []

        for entry in orderedEntries(screenSet, displays: displays) {
            let mine = windows.filter {
                display(containing: $0, in: displays)?.id == entry.display.id
            }

            let result = reconcileLayout(
                node: entry.node,
                frame: entry.display.frame,
                screenFrame: entry.display.frame,
                windows: mine,
                placedWindowIds: []
            )
            allPlacements.append(contentsOf: result.placements)

            // This display's own stack, or its full frame when it has none.
            let target = result.stackFrame ?? entry.display.frame
            for window in mine where !result.placedWindowIds.contains(window.id) {
                allPlacements.append(WindowPlacement(
                    window: window,
                    targetFrame: target,
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
            if let window = bestMatchingWindow(
                for: pinned, in: windows, excluding: placedWindowIds
            ) {
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
                    if let window = bestMatchingWindow(
                        for: pinnedConfig,
                        in: windows,
                        excluding: placedWindowIds.union(result.placedWindowIds)
                    ) {
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
                if let window = bestMatchingWindow(
                    for: pinnedConfig, in: windows, excluding: currentPlacedIds
                ) {
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
                if let window = bestMatchingWindow(
                    for: pinnedConfig, in: windows, excluding: currentPlacedIds
                ) {
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
    /// Whether a window is a candidate for a pinned config.
    ///
    /// Window titles are deliberately *not* part of this test. A title carries
    /// volatile detail — a zoom level, a document name, an unread count — so
    /// treating it as a requirement means a pin silently stops matching and its
    /// window falls through to the stack. Titles instead break ties, via
    /// `windowMatchScore`, so a pinned pane degrades to "some window of this
    /// app" rather than to nothing.
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

        // At least one criterion must be specified
        if pinned.bundleId == nil && pinned.application == nil {
            return false
        }

        return true
    }

    /// How well a window answers to a pin, best first:
    ///
    /// - 3 — it *is* the pinned window, by id. Unambiguous.
    /// - 2 — a title the pin recorded still matches.
    /// - 1 — some window of the right application.
    /// - 0 — not a candidate.
    ///
    /// The id is checked within an app match, never on its own: ids are reused
    /// once a window closes, so a stale one could otherwise name an unrelated
    /// window belonging to some other application.
    public static func windowMatchScore(_ window: Window, pinned: PinnedConfig) -> Int {
        guard windowMatches(window, pinned: pinned) else { return 0 }
        if let pinnedId = pinned.windowId, window.id == pinnedId { return 3 }
        guard let titles = pinned.windowTitles, !titles.isEmpty else { return 1 }
        return titles.contains(where: { window.title.contains($0) }) ? 2 : 1
    }

    /// The best candidate for a pinned config: the pinned window itself when it
    /// is still recognisable, otherwise any window of the same app.
    ///
    /// Ties are broken by window id, and that matters more than it looks. The
    /// candidate list comes from `CGWindowListCopyWindowInfo`, which is ordered
    /// by z-order, so it reshuffles whenever the user focuses a different
    /// window. Picking "the highest score" out of that with no tie-break meant
    /// two equally-good windows — two documents with the same name, say —
    /// traded places every time the front window changed, and whichever lost
    /// fell through to the stack. The layout appeared to flicker between two
    /// arrangements on its own.
    public static func bestMatchingWindow(
        for pinned: PinnedConfig,
        in windows: [Window],
        excluding placed: Set<UInt32> = []
    ) -> Window? {
        windows
            .filter { !placed.contains($0.id) && windowMatches($0, pinned: pinned) }
            .sorted { lhs, rhs in
                let lhsScore = windowMatchScore(lhs, pinned: pinned)
                let rhsScore = windowMatchScore(rhs, pinned: pinned)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.id < rhs.id
            }
            .first
    }

    /// Find a window matching the pinned config
    public static func findMatchingWindow(for pinned: PinnedConfig, in windows: [Window]) -> Window? {
        bestMatchingWindow(for: pinned, in: windows)
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
    public internal(set) var currentLayout: Layout? {  // Allow internal modification for dynamic layout changes
        didSet { notifyActiveLayoutChanged() }
    }

    /// The most recently applied layout. Persisted across app restarts via UserDefaults.
    public private(set) var lastUsedLayout: Layout? {
        didSet {
            // Only when this is what `activeLayout` resolves to. Applying a
            // layout sets `currentLayout` first, and that has already announced
            // the same layout by the time this runs.
            if currentLayout == nil { notifyActiveLayoutChanged() }
        }
    }

    /// The layout to present as the one in effect.
    ///
    /// `currentLayout` is only set by applying a layout, so it is nil for a
    /// freshly launched app however many times a layout has been applied
    /// before — nothing is re-applied at startup. `lastUsedLayout` is persisted
    /// for exactly that gap, and is what the layout surface already selects
    /// when it opens, so falling through to it keeps the menubar agreeing with
    /// the surface instead of showing nothing until something is applied.
    public var activeLayout: Layout? { currentLayout ?? lastUsedLayout }

    /// Called when the layout shown as active changes, so the menubar can
    /// follow it.
    ///
    /// Fires on re-assignment rather than only when the identity changes: a
    /// layout edited while it is applied keeps its id but not its shape, and
    /// the icon draws the shape.
    ///
    /// Always delivered on the main thread. `applyLayout` deliberately updates
    /// this on whatever thread called it, so leaving the hop to each consumer
    /// would mean an AppKit call off the main thread the first time one forgot.
    public var onActiveLayoutChange: ((Layout?) -> Void)?

    private func notifyActiveLayoutChanged() {
        guard let handler = onActiveLayoutChange else { return }
        let layout = activeLayout
        if Thread.isMainThread {
            handler(layout)
        } else {
            DispatchQueue.main.async { handler(layout) }
        }
    }

    private let windowManager: WindowManaging
    private let defaults: UserDefaults
    let applyQueue = DispatchQueue(label: "com.windowthing.layout-apply", qos: .userInitiated)
    private var currentApplyWorkItem: DispatchWorkItem?

    /// What each window can actually achieve. Only ever touched from
    /// `applyQueue`, inside the work item below.
    private let settleTracker = WindowSettleTracker()

    /// Block until any pending layout application completes. For testing only.
    public func waitForPendingApply() {
        applyQueue.sync {}
    }

    public init(windowManager: WindowManaging, userDefaults: UserDefaults = .standard) {
        self.windowManager = windowManager
        self.defaults = userDefaults
    }

    // MARK: - Layout Loading

    public func loadLayouts(from config: AppConfig) {
        // Two repairs on the way in.
        //
        // The one-stack-per-screen-set invariant: older versions could write a
        // second stack — notably when adding a display, which used to default
        // the new monitor to a full stack.
        //
        // A tree for the main display, so a layout always applies to something
        // — a config written by hand, or one whose only display was a secondary
        // that has since been removed, could otherwise describe no screen that
        // is present.
        //
        // And structure left behind by editing: containers holding a single
        // child, nested inside each other by repeated splitting and deleting.
        // They draw identically to the child they wrap, so nothing looks wrong
        // in the layout itself, but the tree carries layers that do nothing and
        // everything walking it has to cope with them. Normalising is
        // geometry-preserving, so this tidies a saved layout without moving any
        // of its dividers.
        layouts = config.layouts.map {
            $0.deduplicatingStacks().normalized().ensuringPrimaryDisplay().ensuringName()
        }

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

    /// Replace the whole list, keeping the current and last-used references
    /// pointing at their layouts if those still exist — and dropping them if
    /// they have just been deleted, rather than leaving a reference to a layout
    /// the list no longer contains.
    public func setLayouts(_ newLayouts: [Layout]) {
        layouts = newLayouts

        if let current = currentLayout {
            currentLayout = newLayouts.first { $0.id == current.id }
        }
        if let last = lastUsedLayout {
            lastUsedLayout = newLayouts.first { $0.id == last.id }
        }
    }

    public func applyLayout(_ layout: Layout) {
        let tEntry = CFAbsoluteTimeGetCurrent()
        let displays = windowManager.getDisplays()
        let tDisp = CFAbsoluteTimeGetCurrent()
        let windows = windowManager.getWindows()
        let tWin = CFAbsoluteTimeGetCurrent()

        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )
        let tCalc = CFAbsoluteTimeGetCurrent()
        defer {
            let d = String(format: "%.1f", (tDisp - tEntry) * 1000)
            let w = String(format: "%.1f", (tWin - tDisp) * 1000)
            let c = String(format: "%.1f", (tCalc - tWin) * 1000)
            let total = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - tEntry) * 1000)
            WindowManager.perfLog.info("applyLayout main-thread: displays \(d, privacy: .public)ms, windows \(w, privacy: .public)ms, calc \(c, privacy: .public)ms, total \(total, privacy: .public)ms")
        }

        // Update state immediately on calling thread
        currentLayout = layout
        lastUsedLayout = layout
        defaults.set(layout.id.uuidString, forKey: "lastUsedLayoutId")

        applyPlacements(placements, skippingUnchanged: false)
    }

    /// Push placements out to real windows.
    ///
    /// Always off the main thread: each frame is several Accessibility round
    /// trips into another process, and doing that inline froze the UI for the
    /// duration. Serialised on one queue so passes can't interleave, and
    /// cancellable so a newer layout supersedes one still being applied rather
    /// than fighting it.
    ///
    /// - Parameter skippingUnchanged: skip windows already at their target.
    ///   Right for the reconcile timer, where almost nothing has moved. Wrong
    ///   for an explicit apply, which should assert the layout even over a
    ///   window that merely looks correct.
    private func applyPlacements(_ placements: [WindowPlacement], skippingUnchanged: Bool) {
        currentApplyWorkItem?.cancel()

        let wm = windowManager
        let tracker = settleTracker
        var item: DispatchWorkItem!
        item = DispatchWorkItem {
            let t0 = CFAbsoluteTimeGetCurrent()
            var moved = 0

            wm.beginFrameBatch()
            defer {
                wm.endFrameBatch()
                // Debug level: useful when chasing a layout that won't settle,
                // invisible otherwise.
                let ms = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                WindowManager.perfLog.debug("applied \(moved, privacy: .public)/\(placements.count, privacy: .public) frames in \(ms, privacy: .public)ms, \(tracker.settledCount, privacy: .public) settled short of target")
            }

            // An explicit apply is the user asking for this layout, so every
            // window gets a clean slate rather than inheriting a conclusion
            // reached under some earlier one.
            if !skippingUnchanged { tracker.reset() }

            // Decide what to move first, on one thread: the tracker is shared
            // mutable state and this is cheap, unlike the writes below.
            let toMove: [WindowPlacement]
            if skippingUnchanged {
                // Ask about every window, including those that look correct:
                // arriving is what clears a window's record.
                toMove = placements.filter {
                    tracker.shouldMove(
                        windowID: $0.window.id,
                        current: $0.window.frame,
                        target: $0.targetFrame
                    )
                }
            } else {
                toMove = placements
            }
            moved = toMove.count
            tracker.prune(keeping: Set(placements.map(\.window.id)))

            guard !item.isCancelled, !toMove.isEmpty else { return }

            // Grouped by process so each app's windows are written together,
            // which lets the AX element cache resolve that app's window list
            // once instead of once per window.
            //
            // Deliberately sequential. Running processes in parallel was tried
            // and measured over repeated layout switches: it improved the median
            // but not the worst case, and both were dominated by how quickly
            // individual apps happened to answer rather than by scheduling. It
            // is not worth requiring every WindowManaging implementation to be
            // thread-safe for that.
            let byProcess = Dictionary(grouping: toMove, by: { $0.window.pid })

            for (_, group) in byProcess {
                guard !item.isCancelled else { return }
                for placement in group {
                    guard !item.isCancelled else { return }
                    _ = wm.setWindowFrame(
                        pid: placement.window.pid,
                        windowId: placement.window.id,
                        frame: placement.targetFrame
                    )
                }
            }
        }
        currentApplyWorkItem = item
        applyQueue.async(execute: item)
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
        let t0 = CFAbsoluteTimeGetCurrent()

        let displays = windowManager.getDisplays()
        let windows = windowManager.getWindows()

        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: windows
        )

        // Only move what actually needs moving. This runs on a timer, so in the
        // steady state nearly every window is already where the layout wants it,
        // and re-asserting those frames cost several Accessibility round trips
        // per window, twice a second, to change nothing.
        applyPlacements(placements, skippingUnchanged: true)
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
