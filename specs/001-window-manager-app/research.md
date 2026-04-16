# Research: WindowThing macOS Window Manager App

**Branch**: `001-window-manager-app` | **Date**: 2026-04-11 (updated)

---

## Decision 1: Global Cell Enumeration Algorithm

**Decision**: Enumerate leaf nodes of the active `LayoutNode` tree depth-first, left-to-right top-to-bottom. For multi-display layouts, process displays sorted ascending by their x-origin coordinate. Indices start at 1 and continue across displays without reset.

**Rationale**: Sorting by x-origin matches the user's visual left-to-right reading order of monitors. Depth-first traversal of a columns/rows tree naturally visits tiles in the visual order they appear on screen. Continuous numbering across displays avoids the "monitor 1 cell 1 vs monitor 2 cell 1" ambiguity and satisfies FR-029's single-hotkey-per-cell requirement.

**Alternatives considered**:
- Per-display reset (cell 1 always means "first cell on each monitor") — rejected because it requires a two-part address (monitor + cell) and breaks FR-029.
- Breadth-first enumeration — rejected because it doesn't match visual reading order for complex nested trees.

---

## Decision 2: Cell Index Overflow Scheme

**Decision**: Indices 1–35 use integers. Indices 36+ use lowercase letters a–z (up to 61 total). Represented as `CellAddress` enum with `.numeric(Int)` and `.alpha(Character)` cases.

**Rationale**: Practical layouts rarely exceed 9 cells. The 1–35 numeric range covers even unusual dense grids. Letter overflow is a safety valve, not a common path. Single-character representation keeps config YAML readable (`cell: "a"` vs `cell: 36`).

**Alternatives considered**:
- Always use strings ("1", "2", … "a", "b") — viable but loses type safety on numeric comparison.
- Two-digit numbers (10, 11, …) — rejected because single-character hotkeys are the primary UX; two-digit keys require two keypresses.

---

## Decision 3: Ghost Cell Positions

**Decision**: For each display section in the cell picker, show one ghost column appended to the right of the rightmost column node, and one ghost row appended below the bottommost row node at the root level. If the root is neither columns nor rows (e.g., a single stack), show one ghost column and one ghost row at the root.

**Rationale**: These two positions cover the two most common layout extension patterns: "I want to add another vertical strip" and "I want to add a horizontal band." Showing more ghost positions (e.g., inserting between existing cells) would require understanding sub-tree structure and dramatically increases UI complexity.

**Alternatives considered**:
- Ghost cells at every edge of every tile — too many targets; visually cluttered.
- Only trailing column (no trailing row) — insufficient; many workflows want horizontal splits (e.g., adding a bottom terminal strip).

---

## Decision 4: Cell Picker UX Trigger

**Decision**: Pressing a configured `cellHotKey` moves the window directly to that cell without showing the picker. Pressing the cell-picker hotkey (a separate configurable hotkey, default none) shows the interactive picker. If no `cellHotKey` is configured for a given cell, only the picker is available.

**Rationale**: Power users who have memorized their layout configure `cellHotKeys` and bypass the picker entirely. New users or complex operations use the picker. Both paths coexist cleanly. This mirrors how the existing layout hotkeys work: the overlay is optional.

**Alternatives considered**:
- Always show the picker first, even for configured hotkeys — slower for power users who have cell hotkeys memorized.
- Only the picker, no direct hotkeys — insufficient; doesn't satisfy FR-029.

---

## Decision 5: Last-Used Layout Persistence

**Decision**: Store `lastUsedLayoutId` as a `UUID` string in `UserDefaults` under key `"lastUsedLayoutId"`. Updated synchronously after every `applyLayout()` call in `LayoutManager`. On startup, `LayoutManager` reads this value and retains it as `var lastUsedLayout: Layout?` (resolved against the loaded layout array).

**Rationale**: UserDefaults is the standard lightweight macOS persistence for small preference values. No JSON/YAML complexity needed for a single UUID. Survives app restarts. If the referenced layout is deleted from config, the stored ID simply resolves to nil (graceful degradation).

**Alternatives considered**:
- Store in the YAML config file — would cause the config file to be modified at runtime, creating confusion about user-edited vs app-managed content.
- Store layout name instead of UUID — names are not guaranteed unique; UUID is the stable identity.

---

## Decision 6: Minimum Cell Size Enforcement for Ghost Cells

**Decision**: When appending a ghost column or row, enforce a minimum proportion of 15% per new cell. If adding a new column would reduce any existing column below 15% of display width, the ghost cell for that position is shown as disabled (greyed out) in the picker.

**Rationale**: Windows narrower than ~150px on a 1440px display are unreadable. 15% is a reasonable floor. Disabled ghost cells communicate the constraint without hiding the option.

**Alternatives considered**:
- Hard error / discard the action silently — bad UX; user doesn't understand why the ghost cell didn't work.
- No minimum — leads to unusably thin regions, especially on 4+ column layouts.

---

## HotKey Library Notes

The existing `HotKey` library (soffes/HotKey 0.2.x) registers Carbon-based global hotkeys. Key points relevant to cell hotkeys:

- Numeric keys 1–9 map to `.one` through `.nine` in the `Key` enum.
- Letter keys a–z map to `.a` through `.z`.
- There is no built-in conflict detection; if another app has claimed the key, `HotKey` silently fails to fire.
- All `HotKey` objects must be retained (stored as properties); releasing them deregisters the hotkey.
- Recommendation: store cell hotkeys in `AppDelegate` as `[CellAddress: HotKey]` dictionary; rebuild on config reload.

---

## macOS Accessibility API Notes

`AXUIElementRef`-based window movement (already implemented in `WindowManager`) is the correct approach. No new API surface needed for cell movement — `layoutManager.moveWindow(toCellAt:)` reuses the existing `WindowManager.setFrame()` path.

---

## Decision 7: Tile Controls Visibility Model

**Decision**: `TileInlineControls` in the layout editor appear on hover (fade in via `.onHover`), not always-on and not click-to-select.

**Rationale**: Always-on controls clutter small tiles. Click-to-select requires an extra interaction step. Hover is the standard macOS pattern for reveal-on-proximity (e.g., window close/minimise buttons) and matches what the code already has for drag handles.

**Alternatives considered**:
- Always-on (current state) — rejected because it obscures tile content and becomes illegible in 4+ column layouts.
- Click-to-select — rejected because it adds a tap before any action can be taken.

---

## Decision 8: Screen Set Editor Monitor Source

**Decision**: The screen set editor only shows monitors from `DisplayRegistry.knownDisplayNames` — displays the machine has previously connected. No free-text entry.

**Rationale**: Free-text entry invites typos and creates screen sets that can never match any real display. The registry approach ensures every option in the picker corresponds to a real display the user owns, while still supporting monitors that aren't currently plugged in.

**Alternatives considered**:
- Only show currently connected monitors — rejected because users often configure "docked" layouts while undocked.
- Free-text entry — rejected; prone to silent mismatches.

---

## Decision 9: Window Thumbnail Capture API

**Decision**: Use `CGWindowListCreateImage` (Core Graphics) for per-window captures. Fall back to app icons (`NSWorkspace.shared.icon(forFile:)`) when Screen Recording permission is not granted.

**Rationale**: `CGWindowListCreateImage` is available since macOS 10.5, well-understood, and does not require ScreenCaptureKit (macOS 12.3+). For this app's target of macOS 13+, ScreenCaptureKit would also work but adds complexity. `CGWindowListCreateImage` with `kCGWindowImageBoundsIgnoreFraming` gives clean window-only captures.

**Alternatives considered**:
- `SCScreenshotManager` (ScreenCaptureKit) — viable on macOS 13+, but more complex permission flow and async API adds implementation overhead for marginal benefit at thumbnail sizes.
- Always app icons — rejected; user explicitly requested screenshot thumbnails.

---

## Decision 10: New Layout Starting Structure

**Decision**: New layouts created via the UI start as a single full-screen `.stackAll()` node.

**Rationale**: Fastest path to a usable layout. The user can immediately apply it (all windows stacked in one region) and then use edge-insert handles to split into columns/rows. A template picker would add a modal step for the common case.

**Alternatives considered**:
- Template picker (2-col, 3-col, etc.) — user can still get there in two clicks from the single-stack start using insert handles; not worth the picker complexity.
- Copy of last layout — could confuse users who expect a blank slate.

---

## Decision 11: Menubar Icon Content

**Decision**: Menubar layout icons are shape-only — proportional layout tree rendering with correct column/row ratios, no thumbnail compositing.

**Rationale**: At 22pt (44pt @2x) the icon is too small for thumbnail content to be recognisable. Shape-only icons are sufficient to distinguish between layouts (e.g., "2-col" vs "3-col" vs "sidebar"). Thumbnail compositing at this size would add render cost every 3 seconds for no visible benefit.

**Alternatives considered**:
- Full thumbnail compositing on all icons — rejected (CPU cost, illegible at icon size).
- Thumbnails on active layout only — rejected by user in favour of shape-only for all.

