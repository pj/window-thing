# Contract: Internal Service Interfaces

**Scope**: New and modified public APIs in `WindowThingCore` and `WindowThingViewModel` for the cell movement and picker features.

---

## `CellIndexer` (new — `WindowThingCore`)

Pure, stateless enum with static methods. No side effects. Fully testable.

```swift
public enum CellIndexer {

    /// Enumerate all leaf cells in the active layout for the given display configuration.
    /// Returns cells ordered: displays sorted by x-origin, then left-to-right top-to-bottom
    /// within each display's layout tree.
    public static func indexCells(
        layout: Layout,
        displays: [Display]
    ) -> [IndexedCell]

    /// Return ghost cell positions available for layout extension.
    /// A ghost column is appended after the rightmost column at the root level per display.
    /// A ghost row is appended below the bottommost row at the root level per display.
    public static func ghostPositions(
        layout: Layout,
        displays: [Display]
    ) -> [GhostCellPosition]

    /// Convert a sequential 1-based index to a CellAddress.
    /// 1–35 → .numeric, 36–61 → .alpha('a'–'z'), >61 → nil
    public static func address(forIndex index: Int) -> CellAddress?
}
```

**Invariants**:
- `indexCells` returns exactly one `IndexedCell` per leaf node in the matched `ScreenConfig`.
- Indices are stable for a given (layout, displays) pair — repeated calls return the same order.
- If no layout is active (no matched `ScreenConfig`), returns empty array.

---

## `LayoutManager` additions (existing service — `WindowThingCore`)

```swift
extension LayoutManager {

    /// The most recently applied layout. Persisted across launches via UserDefaults.
    public var lastUsedLayout: Layout? { get }

    /// Move the focused window to the cell identified by `address` in the current layout.
    /// If no layout is currently active, auto-applies `lastUsedLayout` first.
    /// Throws `CellMovementError.addressNotFound` if address has no corresponding cell.
    /// Throws `CellMovementError.noActiveLayout` if `lastUsedLayout` is also nil.
    public func moveWindow(
        _ window: Window,
        toCellAt address: CellAddress,
        displays: [Display]
    ) throws

    public enum CellMovementError: Error {
        case addressNotFound(CellAddress)
        case noActiveLayout
        case windowMoveFailed(underlying: Error)
    }
}
```

---

## `LayoutModification` additions (existing — `WindowThingCore`)

```swift
extension LayoutModification {

    /// Append a new trailing column to `node`.
    /// If node is `.columns`: appends newNode as last child.
    /// If node is a leaf: wraps both in `.columns([node, newNode])`.
    /// Returns the modified tree. Pure function.
    public static func appendTrailingColumn(
        to node: LayoutNode,
        newNode: LayoutNode = .stackAll()
    ) -> LayoutNode

    /// Append a new trailing row. Same semantics as appendTrailingColumn.
    public static func appendTrailingRow(
        to node: LayoutNode,
        newNode: LayoutNode = .stackAll()
    ) -> LayoutNode

    /// Returns false if appending a column would reduce any sibling below minPercentage (default 15.0).
    public static func canAppendColumn(to node: LayoutNode, minPercentage: Double = 15.0) -> Bool

    /// Returns false if appending a row would reduce any sibling below minPercentage.
    public static func canAppendRow(to node: LayoutNode, minPercentage: Double = 15.0) -> Bool
}
```

---

## `OverlayViewModel` additions (existing — `WindowThingViewModel`)

```swift
extension OverlayViewModel {

    // MARK: - Cell Picker State

    /// True when the cell picker is being presented.
    public var isCellPickerVisible: Bool { get }

    /// The window to be moved when the picker confirms. Nil if picker is not active.
    public var pendingMoveWindow: Window? { get }

    /// Available indexed cells for the picker (from CellIndexer).
    public var pickerCells: [IndexedCell] { get }

    /// Ghost positions available for layout extension.
    public var pickerGhostPositions: [GhostCellPosition] { get }

    // MARK: - Cell Picker Actions

    /// Show the cell picker for moving `window`.
    public func showCellPicker(for window: Window)

    /// Confirm movement to an existing cell.
    public func confirmCellSelection(_ cell: IndexedCell)

    /// Confirm extension via a ghost cell. Modifies the layout tree and then moves the window.
    public func confirmGhostSelection(_ ghost: GhostCellPosition)

    /// Dismiss the picker without action.
    public func dismissCellPicker()
}
```

---

## Error Handling Summary

| Scenario | Behaviour |
|----------|-----------|
| Cell address not in active layout | Log warning; no-op (silent per FR-031) |
| No active layout and no last-used layout | Log warning; show brief HUD message "No layout active" |
| Ghost cell would violate minimum size | Ghost rendered as disabled; action blocked with `canAppend` check |
| Accessibility permission missing | Existing error path in `WindowManager`; no new handling needed |
| Config parse error on new `cellHotKeys` field | Log warning; skip invalid entries; load remaining config normally |
