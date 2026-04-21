# Tasks: WindowThing macOS Window Manager App

**Input**: Design documents from `/specs/001-window-manager-app/`  
**Branch**: `001-window-manager-app`  
**Generated**: 2026-04-11

**Format**: `- [ ] [TaskID] [P?] [Story?] Description — file path`  
- **[P]**: Parallelisable (no dependency on in-progress task, touches different file)  
- **[USn]**: User story ownership

---

## Phase 1: Setup

**Purpose**: Verify baseline compiles and runs; confirm 193-test baseline.

- [ ] T001 Verify `swift build` succeeds and all 193 baseline tests pass — run `swift test`
- [x] T002 [P] Create `Sources/WindowThingCore/Services/CellIndexer.swift` as empty enum stub to unblock parallel foundational work
- [x] T003 [P] Create `Sources/WindowThingCore/Services/DisplayRegistry.swift` as empty class stub to unblock parallel foundational work
- [-] T004 [P] Create `Sources/WindowThingViewModel/WindowThumbnailCache.swift` as empty class stub to unblock parallel foundational work

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: New types and services that multiple user story phases depend on. Must be complete before Phase 5+.

**⚠️ CRITICAL**: Phases 5, 6, 8, 9 cannot begin until this phase is complete.

### CellAddress & CellIndexer (required by Phases 8 + overlay labels)

- [ ] T005 Add `CellAddress` enum (`.numeric(Int)` 1–35, `.alpha(Character)` a–z) with `Hashable`, `CustomStringConvertible`, `Codable` conformances to `Sources/WindowThingCore/Models/Layout.swift`
- [ ] T006 Implement `CellIndexer.indexCells(layout:displays:) -> [IndexedCell]` — depth-first leaf enumeration, displays sorted by x-origin in `Sources/WindowThingCore/Services/CellIndexer.swift`
- [ ] T007 [P] Implement `CellIndexer.ghostPositions(layout:displays:) -> [GhostCellPosition]` — trailing column + trailing row per display section in `Sources/WindowThingCore/Services/CellIndexer.swift`
- [ ] T008 [P] Implement `CellIndexer.address(forIndex:) -> CellAddress?` — converts 1-based Int to `.numeric` or `.alpha` in `Sources/WindowThingCore/Services/CellIndexer.swift`
- [ ] T009 Add `IndexedCell` and `GhostCellPosition` value types to `Sources/WindowThingCore/Services/CellIndexer.swift`
- [ ] T010 [P] Write `CellIndexerTests` — single display, multi-display, nested columns/rows, index overflow to letters in `Tests/WindowThingTests/CellIndexerTests.swift`

### DisplayRegistry (required by Phase 6 screen set editor)

- [ ] T011 Implement `DisplayRegistry` — persists observed display names to UserDefaults key `"seenDisplayNames"`; exposes `record(displays:)` and `knownDisplayNames: [String]` in `Sources/WindowThingCore/Services/DisplayRegistry.swift`
- [ ] T012 Wire `DisplayRegistry.record(displays:)` into `WindowManager.startMonitoringDisplayChanges()` callback in `Sources/WindowThingCore/Services/WindowManager.swift`

### Ghost cell layout helpers (required by Phase 8)

- [ ] T013 [P] Implement `LayoutModification.appendTrailingColumn(to:newNode:) -> LayoutNode` in `Sources/WindowThingCore/Services/LayoutModification.swift`
- [ ] T014 [P] Implement `LayoutModification.appendTrailingRow(to:newNode:) -> LayoutNode` in `Sources/WindowThingCore/Services/LayoutModification.swift`
- [ ] T015 [P] Implement `LayoutModification.canAppendColumn(to:minPercentage:) -> Bool` and `canAppendRow` in `Sources/WindowThingCore/Services/LayoutModification.swift`
- [ ] T016 Write unit tests for all four `LayoutModification` ghost helpers in `Tests/WindowThingTests/LayoutModificationGhostTests.swift`

**Checkpoint**: `swift test` passes; `CellIndexer`, `DisplayRegistry`, and ghost-cell helpers are all exercised by tests.

---

## Phase 3: User Story 1 — Apply a Layout with a Hotkey (P1) 🎯 MVP

**Goal**: Core layout application via hotkey — already implemented; verify complete and add `lastUsedLayout` tracking needed by Phase 8.

**Independent Test**: Configure two layouts in `~/Library/Application Support/WindowThing/config.yaml`, press their hotkeys, verify all windows reposition within 1 second.

- [ ] T017 [US1] Add `var lastUsedLayout: Layout?` property to `LayoutManager`; set it in `applyLayout()` and persist UUID to `UserDefaults["lastUsedLayoutId"]` in `Sources/WindowThingCore/Services/LayoutManager.swift`
- [ ] T018 [US1] On `LayoutManager` init, resolve `UserDefaults["lastUsedLayoutId"]` against loaded layouts to restore `lastUsedLayout` in `Sources/WindowThingCore/Services/LayoutManager.swift`
- [ ] T019 [P] [US1] Write `LayoutManagerLastUsedTests` — apply layout, quit app, relaunch, verify `lastUsedLayout` restored in `Tests/WindowThingTests/LayoutManagerLastUsedTests.swift`
- [ ] T020 [US1] Verify hotkey conflict warning: log warning if a `quickKey` cannot be registered and surface it via `debugLog` in `Sources/WindowThing/WindowThingApp.swift`

**Checkpoint**: Hotkey layout apply works end-to-end; `lastUsedLayout` persists across launches.

---

## Phase 4: User Story 2 — Browse and Apply via Overlay (P2)

**Goal**: Overlay opens, carousel navigates, layout applies — already implemented; add cell index labels and connect thumbnail cache reads.

**Independent Test**: Open overlay, navigate carousel with arrow keys, press Enter — verify correct layout applies and overlay closes within 300ms.

- [ ] T021 [US2] Add `showCellIndexLabels: Bool` style flag to `CanvasStyle` and thread it through `LayoutCanvasView` → `CanvasTileView` in `Sources/WindowThingCanvas/CanvasStyle.swift` and `Sources/WindowThingCanvas/CanvasTileView.swift`
- [ ] T022 [US2] Compute global cell index for each leaf tile in `CanvasTileView` using `CellIndexer.indexCells` (passed in as pre-computed array) and overlay the address label when `showCellIndexLabels == true` in `Sources/WindowThingCanvas/CanvasTileView.swift`
- [ ] T023 [US2] Pass `showCellIndexLabels: true` style when instantiating the overlay's (non-editor) canvas in `Sources/WindowThing/Views/OverlayWindow.swift`; pass `false` for the editor canvas in `Sources/WindowThing/Views/LayoutEditorView.swift`
- [ ] T024 [P] [US2] Write `CanvasCellLabelTests` — verify label appears at correct tile position for a 3-column layout in `Tests/WindowThingCanvasTests/CanvasCellLabelTests.swift`

**Checkpoint**: Overlay carousel shows cell index labels on tiles; editor does not.

---

## Phase 5: User Story 3 — Visual Layout Editor (P3)

**Goal**: Complete the partially-implemented layout editor — hover controls, action bar, new/duplicate/delete layouts, multi-screenset editing.

**Independent Test**: Open overlay → create a new layout → split into two columns → pin an app to one tile → add a screen set for a previously-seen monitor → save → verify config file updated and layout applies correctly.

### 5a — Tile hover controls (replaces always-on behaviour)

- [ ] T025 [US3] Add `@State private var isHovering = false` to `LayoutTileView.leafTile` and wrap `TileInlineControls` in `.opacity(isHovering ? 1 : 0).animation(.easeInOut(duration: 0.15))` with `.onHover { isHovering = $0 }` in `Sources/WindowThing/Views/LayoutEditorView.swift`
- [ ] T026 [US3] Add subtle hover highlight (background tint) to leaf tiles when `isHovering && !showingControls` so the tile is still responsive-feeling in `Sources/WindowThing/Views/LayoutEditorView.swift`

### 5b — Layout management action bar

- [ ] T027 [US3] Add `CarouselActionBar` view below the carousel with ＋ Add, ⧉ Duplicate, 🗑 Delete buttons bound to `OverlayViewModel` actions in `Sources/WindowThing/Views/OverlayWindow.swift`
- [ ] T028 [US3] Implement `OverlayViewModel.addNewLayout()` — creates a `Layout` with a single `.stackAll()` root node, appends to `layouts`, sets `editingLayout` to the new layout in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T029 [US3] Implement `OverlayViewModel.duplicateSelectedLayout()` — deep copies selected layout with name `"\(original.name) copy"`, appends, opens in editor in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T030 [US3] Implement `OverlayViewModel.deleteSelectedLayout()` — guarded by `layouts.count > 1`; presents confirmation alert before removal in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T031 [US3] Disable the Delete button in `CarouselActionBar` when `viewModel.layouts.count == 1` in `Sources/WindowThing/Views/OverlayWindow.swift`
- [ ] T032 [P] [US3] Write `OverlayViewModelLayoutCRUDTests` — add, duplicate, delete (including guard), in `Tests/WindowThingViewModelTests/OverlayViewModelLayoutCRUDTests.swift`

### 5c — Wire editor entry point

- [ ] T033 [US3] Confirm "Edit" tap on a layout card transitions the overlay into editor mode (`viewModel.startEditing(layout)`); add if missing in `Sources/WindowThing/Views/OverlayWindow.swift`
- [ ] T034 [US3] Ensure `addNewLayout()` and `duplicateSelectedLayout()` immediately call `startEditing` on the new layout in `Sources/WindowThingViewModel/OverlayViewModel.swift`

### 5d — Multi-screenset editing in the editor

- [ ] T035 [US3] Add `ScreenSetTabBar` above the editor canvas showing one tab per screen set in the editing layout, plus a ＋ button to add a new one in `Sources/WindowThing/Views/LayoutEditorView.swift`
- [ ] T036 [US3] Implement `OverlayViewModel.selectedScreenSetIndex: Int` and `addScreenSet(for displays: [String])` — creates a new `ScreenConfig` and appends to `editingLayout.screenSets` in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T037 [US3] Implement the "Add screen set" sheet: a picker listing `DisplayRegistry.knownDisplayNames` (multi-select), confirming creates a new screen set keyed to the chosen displays plus `$PRIMARY` in `Sources/WindowThing/Views/LayoutEditorView.swift`
- [ ] T038 [US3] Implement `OverlayViewModel.removeScreenSet(at:)` — guarded so at least one screen set remains; bound to a delete button on each tab in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T039 [US3] Connect `ScreenSetTabBar` selection to update `editingRootNode` to the root node of the selected screen set's `$PRIMARY` layout in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T040 [P] [US3] Write `ScreenSetEditorTests` — add screen set, switch tabs, delete screen set (including guard) in `Tests/WindowThingViewModelTests/ScreenSetEditorTests.swift`

### 5e — Save persists to YAML config

- [ ] T041 [US3] Verify `OverlayViewModel.saveEdits()` → `ConfigManager.saveLayouts()` writes the updated layout array back to `config.yaml`; implement `ConfigManager.saveLayouts` if not present in `Sources/WindowThingCore/Services/ConfigManager.swift`
- [ ] T042 [P] [US3] Write round-trip test: create layout in VM → save → reload `ConfigManager` → verify layout present in `Tests/WindowThingTests/ConfigManagerSaveTests.swift`

**Checkpoint**: User can create, duplicate, delete, and edit layouts entirely within the UI; multi-screenset tabs work; YAML persists correctly.

---

## Phase 6: User Story 4 — Multi-Monitor Layout Assignment (P4)

**Goal**: Layouts auto-select correct screen set; display changes trigger reapply — largely implemented; `DisplayRegistry` integration is the new work.

**Independent Test**: Configure a layout with two screen sets; plug in a second monitor; verify the correct screen set is used automatically.

- [ ] T043 [US4] Call `DisplayRegistry.record(displays:)` in `WindowManager` display-change handler to keep the registry current in `Sources/WindowThingCore/Services/WindowManager.swift`
- [ ] T044 [P] [US4] Call `DisplayRegistry.record(displays:)` at app launch with `windowManager.getDisplays()` in `Sources/WindowThing/WindowThingApp.swift`
- [ ] T045 [P] [US4] Write `DisplayRegistryTests` — record displays, verify persistence, verify re-loading from UserDefaults in `Tests/WindowThingTests/DisplayRegistryTests.swift`
- [ ] T046 [US4] Add integration smoke-test: configure two screen sets, simulate display change via `NSApplication.didChangeScreenParametersNotification`, verify `LayoutManager.reconcileCurrentLayout()` fires in `Tests/WindowThingTests/DisplayChangeReconcileTests.swift`

**Checkpoint**: `DisplayRegistry.knownDisplayNames` grows as displays are connected; screen set picker in the editor shows previously-seen monitors.

---

## Phase 7: User Story 5 — First-Run Onboarding (P5)

**Goal**: New users are guided through accessibility + screen recording permissions and see sample layouts immediately.

**Independent Test**: Delete `~/Library/Application Support/WindowThing/config.yaml`, revoke accessibility permission, launch app — verify onboarding appears and walking through it results in a working app.

- [ ] T047 [US5] Verify `ConfigManager` creates a default `config.yaml` with two sample layouts on first launch (implement if missing) in `Sources/WindowThingCore/Services/ConfigManager.swift`
- [ ] T048 [US5] Create `OnboardingView` — step 1: explains Accessibility permission with "Open System Settings" button; polls `AXIsProcessTrusted()` every 1s and advances when granted in `Sources/WindowThing/Views/OnboardingView.swift`
- [ ] T049 [US5] Add step 2 to `OnboardingView` — explains Screen Recording permission with "Open System Settings" button; polls `CGPreflightScreenCaptureAccess()` every 1s; has "Skip" option since Screen Recording is optional in `Sources/WindowThing/Views/OnboardingView.swift`
- [ ] T050 [US5] Add step 3 to `OnboardingView` — shows the global hotkey and prompts user to try it; a "Done" button dismisses onboarding in `Sources/WindowThing/Views/OnboardingView.swift`
- [ ] T051 [US5] Gate `OnboardingView` presentation in `AppDelegate.applicationDidFinishLaunching` — show if `!AXIsProcessTrusted()` or first-ever launch (UserDefaults flag `"hasCompletedOnboarding"`) in `Sources/WindowThing/WindowThingApp.swift`

**Checkpoint**: Fresh-install simulation shows onboarding, granting permissions dismisses relevant steps, default layouts are present.

---

## Phase 8: Individual Window Movement

**Goal**: Per-cell hotkeys move the focused window to that cell globally across all monitors; cell picker overlay for interactive selection.

**Independent Test**: Apply a 3-cell layout, press the configured hotkey for cell 2, verify the focused window repositions to the cell 2 bounds.

### 8a — Config schema and hotkey registration

- [ ] T052 [US2] Add `cellHotKeys: [String: HotKeyConfig]?` and `cellPickerHotKey: HotKeyConfig?` fields to `Config` struct and YAML decoder in `Sources/WindowThingCore/Models/Config.swift`
- [ ] T053 [US2] Register `[CellAddress: HotKey]` dictionary in `AppDelegate.loadConfiguration()` — iterate `config.cellHotKeys`, create one `HotKey` per entry, store in `AppDelegate` property in `Sources/WindowThing/WindowThingApp.swift`
- [ ] T054 [US2] Register `cellPickerHotKey` as a separate `HotKey` that calls `showCellPicker()` in `Sources/WindowThing/WindowThingApp.swift`

### 8b — LayoutManager cell movement

- [ ] T055 [US2] Implement `LayoutManager.moveWindow(_:toCellAt:displays:) throws` — resolves address via `CellIndexer.indexCells`, calls `WindowManager.setFrame` in `Sources/WindowThingCore/Services/LayoutManager.swift`
- [ ] T056 [US2] Auto-apply `lastUsedLayout` in `moveWindow` if `currentLayout == nil` before resolving cell address in `Sources/WindowThingCore/Services/LayoutManager.swift`
- [ ] T057 [P] [US2] Write `LayoutManagerCellMovementTests` — move to cell 1, cell 2, unknown address (expect `.addressNotFound`), no active layout falls back to lastUsed in `Tests/WindowThingTests/LayoutManagerCellMovementTests.swift`

### 8c — Cell picker overlay

- [ ] T058 [US2] Add cell picker state to `OverlayViewModel`: `isCellPickerVisible`, `pendingMoveWindow`, `pickerCells`, `pickerGhostPositions`, plus actions `showCellPicker(for:)`, `confirmCellSelection(_:)`, `confirmGhostSelection(_:)`, `dismissCellPicker()` in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T059 [US2] Implement `OverlayViewModel.confirmGhostSelection(_:)` — calls `LayoutModification.appendTrailingColumn/Row`, commits the edit via `commitEdit`, then calls `moveWindow` to the new cell in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T060 [US2] Create `CellPickerView` — grid of `IndexedCell` tiles labelled by address plus ghost tiles (dimmed, dashed border); supports click and arrow-key + Enter navigation; Escape calls `dismissCellPicker()` in `Sources/WindowThingCanvas/CellPickerView.swift`
- [ ] T061 [US2] Present `CellPickerView` as a small floating panel from `OverlayWindow` when `viewModel.isCellPickerVisible` becomes true in `Sources/WindowThing/Views/OverlayWindow.swift`
- [ ] T062 [P] [US2] Write `CellPickerViewModelTests` — show picker, confirm cell, confirm ghost (verifies layout extension + move), dismiss in `Tests/WindowThingViewModelTests/CellPickerViewModelTests.swift`
- [ ] T063 [US2] Disable ghost cell tiles in `CellPickerView` when `ghost.isDisabled == true` (minimum cell size violation from `canAppendColumn/Row`) in `Sources/WindowThingCanvas/CellPickerView.swift`

**Checkpoint**: Pressing a configured cell hotkey moves the focused window to the correct cell; picker shows on the picker hotkey; selecting a ghost cell extends the layout.

---

## Phase 9: Live Window Previews

**Goal**: Background thumbnail cache feeds screenshot previews into the overlay canvas cells and carousel cards.

**Independent Test**: Grant Screen Recording permission, open overlay — verify each occupied cell shows a recognisable screenshot thumbnail; thumbnails refresh within ~3 seconds of window content changing.

### 9a — Thumbnail cache service

- [ ] T064 [US2] Implement `WindowThumbnailCache` — background `DispatchSourceTimer` polling at configurable interval (default 3s); captures `CGWindowListCreateImage` per visible window ID; stores `[CGWindowID: CGImage]`; publishes updates via `PassthroughSubject` in `Sources/WindowThingViewModel/WindowThumbnailCache.swift`
- [ ] T065 [US2] Request Screen Recording permission in `AppDelegate` using `CGRequestScreenCaptureAccess()` at launch, after accessibility permission is resolved in `Sources/WindowThing/WindowThingApp.swift`
- [ ] T066 [US2] Hook `WindowThumbnailCache` refresh into `WindowManager.onCacheRefresh` so window-change events trigger an immediate re-capture (in addition to the polling timer) in `Sources/WindowThingViewModel/WindowThumbnailCache.swift`
- [ ] T067 [US2] Add `thumbnailCache: WindowThumbnailCache` to `OverlayViewModel`; subscribe to its publisher and store latest `[CGWindowID: CGImage]` snapshot in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T068 [US2] Add `thumbnailCaptureInterval: TimeInterval` (default `3.0`, range 2–5) to `Config` and YAML decoder in `Sources/WindowThingCore/Models/Config.swift`

### 9b — Thumbnail rendering in overlay

- [ ] T069 [US2] Add `thumbnail: CGImage?` parameter to `CanvasTileView` leaf rendering; if non-nil, render as `Image(cgImage)` scaled to fill tile bounds behind the label overlay in `Sources/WindowThingCanvas/CanvasTileView.swift`
- [ ] T070 [US2] In `OverlayViewModel`, compute `ActiveLayoutState` — a `[CellAddress: [Window]]` map from the current layout + display + window list — and expose it for binding to the canvas in `Sources/WindowThingViewModel/OverlayViewModel.swift`
- [ ] T071 [US2] Wire `ActiveLayoutState` + `thumbnailCache` into the overlay canvas: resolve each cell's windows, look up their `CGWindowID`s in the cache, pass the first thumbnail (or nil) to the tile in `Sources/WindowThing/Views/OverlayWindow.swift`
- [ ] T072 [US2] Implement Screen Recording permission fallback: when `CGPreflightScreenCaptureAccess()` returns false, pass `nil` thumbnails (tiles show app icon placeholder) — add `appIconFallback(for window:) -> NSImage?` helper in `Sources/WindowThing/Views/OverlayWindow.swift`

**Checkpoint**: Overlay tiles show live screenshots when permission is granted; app icons when permission is denied; content refreshes within the configured interval.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Menubar icon improvements, config reload, edge case hardening.

### Menubar icons

- [ ] T073 Rewrite `NSImage.layoutIcon(for:displays:)` to render the actual layout tree proportions (column/row widths from `percentage` values, correct nesting) rather than a generic shape in `Sources/WindowThing/MenuBarIcon.swift`
- [ ] T074 [P] Write snapshot tests for `layoutIcon` across: single cell, 2-col equal, 3-col unequal, nested rows-in-columns in `Tests/WindowThingTests/MenuBarIconTests.swift`
- [ ] T075 Trigger `updateStatusMenu()` from `AppDelegate` on config reload and layout save so icons reflect structural changes immediately in `Sources/WindowThing/WindowThingApp.swift`

### Config resilience

- [ ] T076 [P] Add human-readable error alert (via `NSAlert`) when `ConfigManager` fails to parse YAML, listing the parse error message — satisfying FR-023 in `Sources/WindowThing/WindowThingApp.swift`
- [ ] T077 [P] Add duplicate-quickKey detection at config load time: log a warning listing conflicting layouts in `Sources/WindowThingCore/Services/ConfigManager.swift`

### Edge case hardening

- [ ] T078 [P] Handle Screen Recording permission revocation mid-session: observe `CGScreenCaptureAccess` change notification and stop the capture timer; resume on re-grant in `Sources/WindowThingViewModel/WindowThumbnailCache.swift`
- [ ] T079 [P] Guard `WindowThumbnailCache` against capturing a window that closes between enumeration and capture (catch `kCGErrorIllegalArgument`) in `Sources/WindowThingViewModel/WindowThumbnailCache.swift`
- [ ] T080 [P] Handle ghost cell minimum-size violation gracefully in `CellPickerView` — disabled tiles show a tooltip "Too small to split further" in `Sources/WindowThingCanvas/CellPickerView.swift`

### Final validation

- [ ] T081 Run full test suite (`swift test`) and confirm zero regressions against 193 baseline in CI or locally
- [ ] T082 [P] Update `quickstart.md` with sample `cellHotKeys` YAML and note Screen Recording permission requirement in `specs/001-window-manager-app/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
  └─► Phase 2 (Foundational) — BLOCKS Phase 5, 6, 8, 9
        ├─► Phase 3 (US1 - Layout apply)       ← independent, can start after Phase 2
        ├─► Phase 4 (US2 - Overlay)            ← independent, can start after Phase 2
        ├─► Phase 5 (US3 - Editor)             ← needs Phase 2 (ghost helpers, DisplayRegistry)
        ├─► Phase 6 (US4 - Multi-monitor)      ← needs Phase 2 (DisplayRegistry)
        ├─► Phase 7 (US5 - Onboarding)         ← independent, can start after Phase 1
        ├─► Phase 8 (Cell movement)            ← needs Phase 2 (CellIndexer, ghost helpers) + Phase 3 (lastUsedLayout)
        └─► Phase 9 (Thumbnails)               ← needs Phase 4 (overlay wiring)
Phase 10 (Polish) — needs Phases 3–9
```

### Key Within-Phase Dependencies

- T006 → T007, T008, T009 (CellIndexer base before extensions)
- T013 → T016 (ghost helpers before tests)
- T028 → T033, T034 (addNewLayout VM action before wiring)
- T055 → T056 (move before auto-apply fallback)
- T058 → T059, T060, T061 (picker VM state before view and ghost action)
- T064 → T066, T067 (cache service before hooks and VM)
- T070 → T071 (ActiveLayoutState before overlay wiring)

### Parallel Opportunities per Phase

**Phase 2**: T005 → T006; then T007, T008, T009, T010 in parallel; T013 + T014 + T015 in parallel  
**Phase 5**: T025+T026 ∥ T027 ∥ (T028→T029→T030→T031→T032) ∥ T041  
**Phase 8**: T052+T053+T054 ∥ T057; T060+T062+T063 after T058  
**Phase 9**: T064 → T065+T066+T067+T068 in parallel; T069+T072 in parallel after T070→T071  
**Phase 10**: T073 → T074+T075; T076+T077+T078+T079+T080 all in parallel

---

## Implementation Strategy

### MVP (Phase 1 + 2 + 3 only)

1. Complete Phase 1 — confirm baseline
2. Complete Phase 2 — foundational types and services
3. Complete Phase 3 — `lastUsedLayout` persistence
4. **Stop and validate**: layout hotkeys work, `lastUsedLayout` persists
5. Already shippable to anyone who configures YAML by hand

### Incremental Delivery

| Milestone | Phases | What users get |
|-----------|--------|---------------|
| M1 — Core complete | 1–3 | Hotkey layout apply, lastUsedLayout |
| M2 — Overlay + labels | 4 | Cell index labels in overlay canvas |
| M3 — Editor complete | 5 | Full visual editor: create/duplicate/delete/multi-screen |
| M4 — Multi-monitor | 6 | DisplayRegistry, screen set editor |
| M5 — Onboarding | 7 | First-run guidance, default config |
| M6 — Cell movement | 8 | Per-cell hotkeys, picker, ghost cells |
| M7 — Live previews | 9 | Screenshot thumbnails in overlay |
| M8 — Polish | 10 | Accurate menubar icons, resilience |

---

## Notes

- No tests were explicitly requested in the spec; tests included here are structural (unit/integration) to validate correctness of new pure-logic code. Skip test tasks if moving fast.
- `[P]` tasks touch different files with no in-progress dependencies — safe to run as parallel agent subtasks.
- All user story tasks include `[USn]` labels for traceability back to spec.md user stories.
- Commit after each phase checkpoint to maintain a clean rollback point.
- The existing 193-test baseline must not regress; run `swift test` after Phase 2 and after Phase 5 as mandatory checkpoints.
