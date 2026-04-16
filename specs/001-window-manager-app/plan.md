# Implementation Plan: WindowThing macOS Window Manager App

**Branch**: `001-window-manager-app` | **Date**: 2026-04-11 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `/specs/001-window-manager-app/spec.md`

---

## Summary

WindowThing is a native macOS menubar window manager. The core layout engine, hotkey application, overlay UI, and visual layout editor scaffolding are already implemented (193 passing tests). This plan covers the delta work needed to reach a complete, shippable app: finishing the layout editor (hover controls, create/duplicate/delete/multi-screen-set), global cell-indexed window movement with an interactive cell picker and ghost cells, a background screenshot thumbnail cache powering live previews in the overlay, accurately-shaped dynamic menubar icons, a display name registry for the screen-set editor, and first-run onboarding.

---

## Technical Context

**Language/Version**: Swift 5.9, macOS 13+  
**Primary Dependencies**: Yams 5.x (YAML config), HotKey 0.2.x (global shortcuts), ViewInspector 0.10.x (SwiftUI tests)  
**Storage**: YAML config file at `~/Library/Application Support/WindowThing/config.yaml`; UserDefaults for lightweight runtime state (lastUsedLayoutId, seenDisplayNames, onboarding flag); no database  
**Testing**: XCTest + Swift Testing; ViewInspector for SwiftUI canvas components  
**Target Platform**: macOS 13+ menubar utility (no Dock icon; Accessibility API + Screen Recording permission required)  
**Project Type**: Native macOS desktop app — Swift Package Manager, 5-target structure  
**Performance Goals**: Layout apply < 1s; overlay open < 300ms; cell picker open < 150ms; thumbnail cache refresh default 3s  
**Constraints**: No App Store sandbox; Accessibility API requires explicit permission; Screen Recording API requires separate permission; graceful fallback to app icons when Screen Recording unavailable  
**Scale/Scope**: Single-user local app; ~10 layouts, ~10 cells per layout, 2–4 monitors

---

## Constitution Check

The project constitution is a blank template — no project-specific gates are defined. Proceeding under general engineering standards:

- **Testability**: Core logic must remain in `WindowThingCore` (pure, no UI); testable without running the app. ✅ Existing architecture enforces this; all new services (`CellIndexer`, `DisplayRegistry`, ghost-cell helpers) are pure.
- **Separation of concerns**: New cell-movement logic → `WindowThingCore`; hotkey registration → `WindowThing` app target; overlay state → `WindowThingViewModel`; thumbnail cache → `WindowThingViewModel`. ✅ No violations planned.
- **No new targets needed**: All new code fits the existing 5-target structure. ✅

---

## Project Structure

### Documentation (this feature)

```text
specs/001-window-manager-app/
├── plan.md              # This file
├── research.md          # Phase 0 — tech decisions
├── data-model.md        # Phase 1 — entities & state transitions
├── quickstart.md        # Phase 1 — build/run/test guide
├── contracts/
│   ├── config-schema.md     # YAML config schema (v2)
│   └── layout-manager.md    # Internal Swift API contracts
└── tasks.md             # Phase 2 — 82 tasks across 10 phases
```

### Source Code (repository root)

```text
Sources/
├── WindowThingCore/
│   ├── Models/
│   │   ├── Layout.swift           # + CellAddress enum
│   │   ├── Config.swift           # + cellHotKeys, cellPickerHotKey, thumbnailCaptureInterval
│   │   └── Window.swift
│   └── Services/
│       ├── LayoutManager.swift    # + moveWindow(toCellAt:), lastUsedLayout
│       ├── LayoutModification.swift  # + appendTrailingColumn/Row, canAppend*
│       ├── CellIndexer.swift      # NEW — global cell enumeration
│       ├── DisplayRegistry.swift  # NEW — persists seen display names
│       ├── WindowManager.swift
│       ├── ConfigManager.swift    # + saveLayouts(), default config creation
│       └── Protocols.swift
├── WindowThingViewModel/
│   ├── OverlayViewModel.swift     # + cell picker state, screenset editing, add/dup/del layouts
│   ├── WindowThumbnailCache.swift # NEW — background screenshot polling
│   └── RunningAppInfo.swift
├── WindowThingCanvas/
│   ├── LayoutCanvasView.swift     # + showCellIndexLabels style flag
│   ├── CanvasTileView.swift       # + cell index label overlay, thumbnail rendering
│   ├── CellPickerView.swift       # NEW — interactive cell picker with ghost tiles
│   ├── CanvasStyle.swift          # + showCellIndexLabels flag
│   ├── TileControlBar.swift       # (existing, used by canvas demo)
│   ├── DragHandles.swift
│   └── CellSplitOverlay.swift
└── WindowThing/
    ├── WindowThingApp.swift        # + cell HotKey dict, Screen Recording permission
    ├── MenuBarIcon.swift           # + accurate proportional layoutIcon renderer
    ├── TypeAliases.swift
    └── Views/
        ├── OverlayWindow.swift    # + CarouselActionBar, cell picker presentation
        ├── LayoutEditorView.swift # + hover controls, ScreenSetTabBar, screenset sheet
        ├── OnboardingView.swift   # NEW — 3-step permission + hotkey intro
        └── SettingsView.swift

Tests/
├── WindowThingTests/
│   ├── CellIndexerTests.swift           # NEW
│   ├── LayoutManagerLastUsedTests.swift  # NEW
│   ├── LayoutManagerCellMovementTests.swift  # NEW
│   ├── LayoutModificationGhostTests.swift    # NEW
│   ├── DisplayRegistryTests.swift        # NEW
│   ├── ConfigManagerSaveTests.swift      # NEW
│   ├── DisplayChangeReconcileTests.swift  # NEW
│   └── MenuBarIconTests.swift            # NEW
├── WindowThingViewModelTests/
│   ├── OverlayViewModelLayoutCRUDTests.swift  # NEW
│   ├── ScreenSetEditorTests.swift             # NEW
│   └── CellPickerViewModelTests.swift         # NEW
└── WindowThingCanvasTests/
    ├── CanvasCellLabelTests.swift  # NEW
    └── (existing tests)
```

**Structure Decision**: Single-project (Swift Package Manager). All new code fits the existing 5-target structure. `WindowThingCore` stays pure logic; no SwiftUI leaks into it.

---

## Complexity Tracking

No constitution violations. No justification required.

---

## Work Breakdown

### Already Implemented (baseline — do not re-implement)

| Area | Spec refs | Status |
|------|-----------|--------|
| Layout model (Layout, LayoutNode, ScreenConfig) | FR-001 | ✅ Complete |
| Layout calculation engine (LayoutCalculator) | FR-003, FR-004, FR-005 | ✅ Complete |
| Layout application via hotkey | FR-002, FR-003 | ✅ Complete |
| Overlay window — carousel, layout picker cards | FR-006, FR-007, FR-008, FR-009 | ✅ Complete (minus cell labels) |
| **Visual layout editor** — tile split/merge, drag-resize | FR-010, FR-013 | ⚠️ Partial |
| TileInlineControls — type cycler, app picker, window picker | FR-011, FR-012 | ⚠️ Partial (always-on, needs hover) |
| Editor bottom bar — hotkey cap, name, save/cancel, undo | FR-014, FR-015, FR-016 | ✅ Complete |
| Drag-to-pin running app onto tile | FR-012 | ✅ Complete |
| Multi-monitor screen set matching + auto-reapply | FR-017 through FR-020 | ✅ Complete |
| YAML config loading + malformed-config error | FR-021, FR-023 | ✅ Complete |
| Menubar utility (no Dock icon, layout list, quit) | FR-026, FR-027, FR-028 | ✅ Complete |
| Accessibility permission request | FR-024, FR-025 | ✅ Complete |
| Basic menubar layout icon (`NSImage.layoutIcon`) | FR-027 | ⚠️ Partial (shape approximate, not proportional) |

### New Work Required

#### Group 0 — Layout Editor Completion

*Spec: FR-010, FR-011, FR-044 through FR-048*

0a. **Hover-triggered tile controls** (FR-011): `TileInlineControls` transitions from always-on to appearing on `.onHover`. Each `LayoutTileView` leaf gets local `@State var isHovering` — controls fade in/out with a 150ms easeInOut. Existing `selectedPath` plumbing can be dropped or repurposed as hover state.

0b. **New layout creation & duplication** (FR-044, FR-044b): Persistent `CarouselActionBar` below the carousel with ＋ Add, ⧉ Duplicate, 🗑 Delete buttons. Add → creates a `Layout` with one `.stackAll()` root, opens immediately in editor. Duplicate → deep copies selected layout with `"\(name) copy"` name, opens in editor.

0c. **Layout deletion** (FR-045): Delete button in `CarouselActionBar` presents `NSAlert` confirmation; blocked when `layouts.count == 1`.

0d. **Multi-screenset editing** (FR-047, FR-048): `ScreenSetTabBar` above the editor canvas (tab per screen set + ＋ button). Add screen set → sheet listing `DisplayRegistry.knownDisplayNames` (multi-select, previously-seen displays only); creates new `ScreenConfig` keyed to chosen displays + `$PRIMARY`. Delete tab with guard (≥1 screen set). `OverlayViewModel.selectedScreenSetIndex` drives which root node the canvas edits.

0e. **Save persists to YAML** (FR-016, FR-046): `ConfigManager.saveLayouts(_:)` serialises the updated layout array back to `config.yaml` using Yams encoder. Called from `OverlayViewModel.saveEdits()`.

0f. **Wire editor entry point**: confirm "Edit" tap on carousel card calls `viewModel.startEditing(layout)`; add/duplicate actions call it on the new layout.

#### Group A — Cell Indexing

*Spec: FR-029, FR-008*

1. **`CellAddress`** in `Layout.swift`: `.numeric(Int)` 1–35, `.alpha(Character)` a–z. `Hashable`, `Codable` (as String), `CustomStringConvertible`.
2. **`CellIndexer`** new file: `indexCells(layout:displays:) -> [IndexedCell]`, `ghostPositions(layout:displays:) -> [GhostCellPosition]`, `address(forIndex:) -> CellAddress?`. Displays sorted by x-origin; leaf nodes enumerated depth-first.
3. **`IndexedCell`**, **`GhostCellPosition`** value types in same file.
4. Unit tests in `CellIndexerTests.swift`.

#### Group B — Per-Cell Movement Hotkeys

*Spec: FR-029, FR-030, FR-034*

5. **Config additions**: `cellHotKeys: [String: HotKeyConfig]?`, `cellPickerHotKey: HotKeyConfig?`, `thumbnailCaptureInterval: TimeInterval` (default 3.0) in `Config.swift`.
6. **`LayoutManager.moveWindow(_:toCellAt:displays:) throws`**: resolves address via `CellIndexer`, calls `WindowManager.setFrame`. Auto-applies `lastUsedLayout` if no layout is active.
7. **`lastUsedLayout`** tracking: set in `applyLayout()`, persisted to `UserDefaults["lastUsedLayoutId"]`, restored on init.
8. **Hotkey registration** in `AppDelegate`: `[CellAddress: HotKey]` dictionary, rebuilt on config reload.

#### Group C — Cell Picker Overlay

*Spec: FR-031, FR-032, FR-033*

9. **`OverlayViewModel` picker state**: `isCellPickerVisible`, `pendingMoveWindow`, `pickerCells`, `pickerGhostPositions`; actions `showCellPicker(for:)`, `confirmCellSelection(_:)`, `confirmGhostSelection(_:)`, `dismissCellPicker()`.
10. **`confirmGhostSelection`**: calls `LayoutModification.appendTrailingColumn/Row`, `commitEdit`, then `moveWindow`.
11. **`CellPickerView`**: grid of labelled cell tiles + dimmed ghost tiles; click and arrow-key + Enter navigation; Escape dismisses.
12. **Presentation** from `OverlayWindow` as a small floating panel.

#### Group D — Ghost Cell Layout Modification

*Spec: FR-033*

13. `LayoutModification.appendTrailingColumn(to:newNode:)`, `appendTrailingRow(to:newNode:)`, `canAppendColumn(to:minPercentage:)`, `canAppendRow(to:minPercentage:)` — pure helpers, all in `LayoutModification.swift`. Minimum percentage default 15%.

#### Group E — Overlay Cell Labels

*Spec: FR-008 updated*

14. `CanvasStyle.showCellIndexLabels: Bool` flag; threaded to `CanvasTileView` leaf renderer to overlay global cell address. Enabled in overlay canvas (non-editor), disabled in editor canvas.

#### Group F — First-Run Onboarding

*Spec: FR-022, FR-024, FR-041, US5*

15. **Default config**: `ConfigManager` creates `config.yaml` with two sample layouts on first launch if file absent.
16. **`OnboardingView`**: 3 steps — (1) Accessibility permission + "Open System Settings" + 1s poll; (2) Screen Recording permission + "Open System Settings" + "Skip" + 1s poll; (3) hotkey intro + "Done". Gate: show if `!AXIsProcessTrusted()` or `!UserDefaults["hasCompletedOnboarding"]`.

#### Group G — Window Thumbnail Cache & Live Previews

*Spec: FR-035 through FR-038, FR-041, FR-042, FR-043*

17. **`WindowThumbnailCache`** in `WindowThingViewModel`: `DispatchSourceTimer` at configurable interval (default 3s, range 2–5s from config); captures `CGWindowListCreateImage` per visible window; `[CGWindowID: CGImage]` in-memory store; `PassthroughSubject` for observers. Also triggers on `WindowManager.onCacheRefresh`.
18. **Screen Recording permission** request at launch after accessibility; graceful fallback to app-icon placeholder when `CGPreflightScreenCaptureAccess()` returns false (FR-042).
19. **`ActiveLayoutState`**: `[CellAddress: [Window]]` computed from current layout + displays + window list; exposed from `OverlayViewModel`.
20. **Thumbnail rendering** in `CanvasTileView`: `CGImage?` parameter, rendered as `Image(cgImage)` scaled to fill behind label.
21. **Wiring in `OverlayWindow`**: resolve each cell's windows, look up `CGWindowID` in cache, pass thumbnail (or nil) to tile.

#### Group H — Dynamic Menubar Icons

*Spec: FR-039, FR-040*

22. **Rewrite `NSImage.layoutIcon`**: render the actual layout tree proportions — correct column/row widths from `percentage` values, correct nesting depth. Shape-only (no thumbnail compositing per FR-040). Regenerates on config reload and layout save.

---

## Key Design Decisions (from Research)

See `research.md` for full rationale. Summary:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Cell enumeration order | Depth-first, left-to-right top-to-bottom; displays sorted by x-origin | Matches reading order; predictable |
| Index overflow | 1–35 numeric, a–z alpha | 61 addressable cells; single-char hotkeys |
| Ghost cell positions | Trailing column + trailing row per display section | Covers two most common extension patterns |
| Cell picker trigger | Picker always shown; direct hotkeys skip it | Power users bypass picker; new users use it |
| Last-used layout persistence | UserDefaults | Lightweight; no YAML pollution |
| Thumbnail rendering | Background poll at 3s + event-driven | Balances freshness vs CPU; always-current on overlay open |
| Menubar icon content | Shape-only (no thumbnails) | 22pt icon too small for useful thumbnails |
| Tile controls visibility | Hover-triggered | Standard macOS pattern; keeps small tiles readable |
| Screen set editor monitors | Previously-seen displays only (DisplayRegistry) | No manual name entry; avoids typos and invalid configs |
| New layout starting structure | Single full-screen stack | Zero friction; user splits from there |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Cell indices shift when layout changes | Document: indices are live; hotkeys target role (cell 1 = leftmost), not fixed position |
| Ghost cell creates very narrow regions | `canAppendColumn/Row` enforces 15% minimum; disabled ghost tiles show tooltip |
| HotKey conflicts for numeric keys | Log warning at startup; skip conflicting keys gracefully |
| Screen Recording permission revoked mid-session | Observe change notification; stop capture timer; resume on re-grant |
| CGWindowListCreateImage races with window close | Catch `kCGErrorIllegalArgument`; skip that window ID |
| YAML save corrupts config | Write to temp file, then atomic rename |
