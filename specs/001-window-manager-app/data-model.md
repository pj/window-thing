# Data Model: WindowThing macOS Window Manager App

**Branch**: `001-window-manager-app` | **Date**: 2026-04-11 (updated)

---

## Existing Entities (unchanged)

| Entity | Location | Description |
|--------|----------|-------------|
| `Layout` | `WindowThingCore/Models/Layout.swift` | Named layout with quickKey, screenSets |
| `LayoutNode` | same | Recursive tree: columns, rows, stack, pinned, empty, floatZoomed |
| `ScreenConfig` | same | Maps display name → LayoutNode for one monitor configuration |
| `PinnedConfig` | same | App/bundleId/windowTitle matcher for a pinned tile |
| `SavedSetup` | same | Snapshot of actual window positions |
| `Window` | `WindowThingCore/Models/Window.swift` | AX window with frame, pid, title |
| `Display` | `WindowThingCore/Models/Window.swift` | Monitor with name, frame |
| `Config` | `WindowThingCore/Models/Config.swift` | Root YAML config with layouts, hotkeys |

---

## New Entities

### `CellAddress`

**Location**: `Sources/WindowThingCore/Models/Layout.swift` (or new `CellAddress.swift`)

**Purpose**: Stable, user-facing identifier for a leaf cell in the globally-indexed active layout. Used as hotkey targets, picker labels, and cell-movement destinations.

```
CellAddress
├── .numeric(Int)   // values 1–35
└── .alpha(Character)  // values 'a'–'z' (overflow beyond 35)
```

**Constraints**:
- Numeric range: 1–35 inclusive
- Alpha range: 'a'–'z' (26 values, indices 36–61)
- Total maximum cells addressable: 61
- Equatable, Hashable, CustomStringConvertible (string form: "1", "2", … "a", "b")
- Codable: encoded/decoded as String in YAML config

**Validation rules**:
- Numeric value must be ≥ 1
- Alpha value must be lowercase ASCII letter
- Values outside these ranges are invalid at config parse time

---

### `IndexedCell`

**Location**: `Sources/WindowThingCore/Services/CellIndexer.swift`

**Purpose**: Pairing of a `CellAddress` with the concrete screen geometry of the cell, produced by `CellIndexer`. Ephemeral — computed on demand, not persisted.

```
IndexedCell
├── address: CellAddress
├── frame: WindowFrame      // pixel bounds of this cell on its display
└── displayName: String     // which monitor this cell lives on
```

---

### `GhostCellPosition`

**Location**: `Sources/WindowThingCore/Services/CellIndexer.swift`

**Purpose**: Describes where a new cell could be appended. Used by `CellPickerView` to render ghost tiles and by `LayoutModification` to know where to extend the tree.

```
GhostCellPosition
├── displayName: String
├── direction: GhostDirection   // .trailingColumn | .trailingRow
├── estimatedFrame: WindowFrame  // approximate bounds for rendering
└── isDisabled: Bool             // true if adding would violate minimum cell size
```

---

## Modified Entities

### `Config` — additions

**Location**: `Sources/WindowThingCore/Models/Config.swift`

New optional fields:

```
Config
├── ... (existing fields)
├── cellHotKeys: [String: HotKeyConfig]?
│     // key: CellAddress string ("1", "2", "a" …)
│     // value: same HotKeyConfig type used for activationHotKey
└── cellPickerHotKey: HotKeyConfig?
      // hotkey to open the interactive cell picker; nil = no hotkey
```

**YAML example**:
```yaml
cellHotKeys:
  "1":
    keyCode: 18      # key "1"
    modifiers: [command, option]
  "2":
    keyCode: 19
    modifiers: [command, option]
cellPickerHotKey:
  keyCode: 47        # key "."
  modifiers: [command, option]
```

---

### `LayoutManager` — state additions

**Location**: `Sources/WindowThingCore/Services/LayoutManager.swift`

New persistent state:

```
LayoutManager
├── ... (existing)
└── lastUsedLayout: Layout?   // set on every applyLayout(); persisted to UserDefaults
```

New methods:

```
func moveWindow(_ window: Window, toCellAt address: CellAddress, displays: [Display]) throws
  // Resolves CellAddress → IndexedCell → calls WindowManager.setFrame()
  // Throws if address not found in current layout

func cellAddresses(for layout: Layout, displays: [Display]) -> [IndexedCell]
  // Delegates to CellIndexer; returns current cell map
```

---

### `LayoutModification` — additions

**Location**: `Sources/WindowThingCore/Services/LayoutModification.swift`

New pure helpers:

```
static func appendTrailingColumn(to node: LayoutNode, newNode: LayoutNode) -> LayoutNode
  // If node is .columns: appends newNode as last column
  // If node is a leaf: wraps both in .columns([node, newNode])

static func appendTrailingRow(to node: LayoutNode, newNode: LayoutNode) -> LayoutNode
  // Same for .rows

static func canAppendColumn(to node: LayoutNode) -> Bool
  // Returns false if all existing columns are at minimum percentage

static func canAppendRow(to node: LayoutNode) -> Bool
```

---

## State Transitions

### Layout Application Flow (existing + extended)

```
User presses layout hotkey
  → AppDelegate.applyLayout()
    → LayoutManager.applyLayout(layout)
      → LayoutCalculator.calculatePlacements(layout, displays, windows)
      → WindowManager.setFrames(placements)
      → LayoutManager.lastUsedLayout = layout          ← NEW
      → UserDefaults["lastUsedLayoutId"] = layout.id  ← NEW
```

### Cell Movement Flow (new)

```
User presses cell hotkey "2"
  → AppDelegate cell hotkey handler
    → if layoutManager.currentLayout == nil:
        layoutManager.applyLayout(lastUsedLayout)      ← auto-apply
    → layoutManager.moveWindow(focusedWindow, toCellAt: .numeric(2), displays)
      → CellIndexer.index(layout, displays) → [IndexedCell]
      → find IndexedCell where address == .numeric(2)
      → WindowManager.setFrame(window, frame: cell.frame)
```

### Ghost Cell Extension Flow (new)

```
User selects ghost cell in picker
  → CellPickerViewModel.selectGhost(position)
    → LayoutModification.appendTrailingColumn/Row(currentNode, .stackAll())
    → OverlayViewModel.commitEdit(modifiedLayout)       ← uses existing undo
    → CellIndexer re-enumerates → new IndexedCell for the added cell
    → LayoutManager.moveWindow(focusedWindow, toCellAt: newAddress, displays)
```

---

## Additional New Entities (from sessions 2 & 3 clarifications)

### `DisplayRegistry`

**Location**: `Sources/WindowThingCore/Services/DisplayRegistry.swift`

**Purpose**: Persistent record of all display names the machine has ever connected. Feeds the screen set editor's monitor picker so users can create screen sets for monitors not currently plugged in.

```
DisplayRegistry
├── knownDisplayNames: [String]   // sorted, deduplicated
└── record(displays: [Display])   // called on every display-change event and at launch
```

**Persistence**: `UserDefaults["seenDisplayNames"]` as JSON-encoded `[String]`.

**Invariants**:
- Names are appended, never removed (user might reconnect a display).
- `$PRIMARY` is never stored (it's a virtual key, not a real display name).

---

### `WindowThumbnailCache`

**Location**: `Sources/WindowThingViewModel/WindowThumbnailCache.swift`

**Purpose**: Background service that periodically captures and caches screenshot thumbnails for all visible windows. Consumed by the overlay canvas and carousel cards.

```
WindowThumbnailCache
├── thumbnails: [CGWindowID: CGImage]   // current cache snapshot
├── captureInterval: TimeInterval        // from Config, default 3.0s, range 2–5s
├── onUpdate: (() -> Void)?             // called after each refresh
└── start() / stop()
```

**Permissions**: Requires Screen Recording permission (`CGPreflightScreenCaptureAccess()`). When unavailable, `thumbnails` is empty and callers fall back to app icons.

**Refresh triggers**:
1. Polling timer fires (every `captureInterval` seconds)
2. `WindowManager.onCacheRefresh` fires (window open/close/move)

**State transitions**:
```
.stopped → start() → .polling
.polling → stop()  → .stopped
.polling → Screen Recording revoked → .degraded (thumbnails cleared, timer suspended)
.degraded → Screen Recording granted → .polling (timer resumed)
```

---

### `ActiveLayoutState`

**Location**: `Sources/WindowThingViewModel/OverlayViewModel.swift` (computed, ephemeral)

**Purpose**: Snapshot of which windows are currently in which cells of the active layout. Used to look up thumbnail `CGWindowID`s for rendering.

```
ActiveLayoutState
└── cellMap: [CellAddress: [Window]]
```

Computed on demand from `LayoutManager.currentLayout` + `CellIndexer.indexCells` + `WindowManager.getWindows()`. Not persisted.

---

## Modified Entities (session 3 additions)

### `Config` — additional fields

```
Config
├── ... (existing)
├── cellHotKeys: [String: HotKeyConfig]?      // "1" → hotkey def
├── cellPickerHotKey: HotKeyConfig?
└── thumbnailCaptureInterval: TimeInterval?   // default 3.0, range 2–5
```

### `OverlayViewModel` — layout management state additions

```
OverlayViewModel
├── ... (existing)
├── selectedScreenSetIndex: Int              // which screen set tab is active in editor
├── isCellPickerVisible: Bool
├── pendingMoveWindow: Window?
├── pickerCells: [IndexedCell]
└── pickerGhostPositions: [GhostCellPosition]
```

