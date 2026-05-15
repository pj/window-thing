# WindowThing - Development TODO

## Architecture

The project is split into two main components:
- **WindowThingCore** - Pure Swift library with all business logic, testable without UI
- **WindowThing** - SwiftUI app that imports Core and provides the UI

---

## Completed

- [x] Initialize jujutsu with git colocation
- [x] Set up Nix flake for Swift development
- [x] Create Swift project structure
- [x] Implement native window management (Accessibility API)
- [x] Create layout data model (YAML config)
- [x] Build SwiftUI interface (overlay window)
- [x] Implement global hotkey activation (Ctrl+Option+W)
- [x] Add menubar integration
- [x] Implement save/load screen setups
- [x] Create build script and .gitignore
- [x] Successful build with `swift build`
- [x] Add "Show Overlay" option to menubar
- [x] Refactor for testability (protocols, dependency injection)
- [x] Create unit test suite (LayoutCalculator, ScreenSetMatching, ConfigParsing, LayoutManager)
- [x] Rename types to match macOS conventions (Monitor→Display, WindowBounds→WindowFrame)
- [x] Integration tests for primary display layouts (fullscreen, split, switching, save/restore)
- [x] Multi-monitor core logic (CellIndexer, display reconciliation, cell movement)
- [x] Multi-monitor ViewModel integration tests (23 tests)
- [x] Display-to-layout-key resolution tests ($PRIMARY, named, case-sensitive)
- [x] Screen set modification (add/remove/rename display keys) with tests
- [x] App/Window selector overlay (Space to open, number keys, search, Shift toggle)
- [x] Sublayout data model (SublayoutConfig, SubCellAddress, nested cell addressing)
- [x] App driver protocol (AppDriver, SubPane, AppPaneState)
- [x] Tmux driver (TmuxDriver, TmuxOutputParser, layout string parsing, pane management)
- [x] Shell executor protocol (ShellExecutor, ProcessShellExecutor)
- [x] Multi-monitor editor UI (monitor tab bar, add/remove displays per screen set)
- [x] Layout editor with visual canvas, inline controls, drag handles
- [x] Drag-to-pin (RunningAppInfo: Transferable)
- [x] Undo/redo support in editor
- [x] Layout editing UI (visual editor)
- [x] CellIndexer coverage (ghostPositions, address mapping)
- [x] LayoutModification coverage (leafCount, leafIndex, withPercentage/Columns/Rows/Type, appendTrailing, canAppend, movingApplication)

---

## Testing

### Unit Tests (Core) — 400 tests passing
- [x] LayoutCalculator tests (column/row bounds, window matching, node placements)
- [x] Screen set matching tests (monitor configurations)
- [x] Config parsing tests (YAML encode/decode)
- [x] LayoutManager tests (with MockWindowManager)
- [x] Cell movement tests (cross-display addressing, moveWindow)
- [x] Display reconciliation tests (fallback, reconnection)
- [x] Display resolution tests ($PRIMARY, named keys, special characters)
- [x] Screen set modification tests (16 tests)
- [x] CellIndexer tests (ghostPositions, address mapping, sub-cells)
- [x] LayoutModification extended tests (leafCount, leafIndex, mutation helpers, append/canAppend)
- [x] Sublayout tests (SubCellAddress, SublayoutConfig, PinnedConfig backward compat, CellMap)
- [x] Tmux driver tests (parser, query, focus, apply, auto-detect, MockShellExecutor)
- [x] OverlayViewModel tests (29 baseline + multi-monitor)

### Integration Tests - Developer Machine
- [x] Compute expected positions from display sizes + running apps, compare to actual
- [x] Snapshot current state, apply layout, verify positions, restore snapshot
- [ ] Multi-monitor verification (detect monitors, apply layout, assert positions)
- [ ] Accessibility permission flow testing (requires user interaction)
- [ ] Performance profiling with developer's actual workload
- [ ] Hotkey conflict detection (test against apps currently running)

### Integration Tests - VM/CI (Automated)
- [ ] Create integration test target (`WindowThingIntegrationTests`)
- [ ] Spawn test windows programmatically (simple Cocoa NSWindow instances)
- [ ] Apply layouts and verify positions via CGWindowListCopyWindowInfo
- [ ] Test window positioning accuracy (compare actual vs expected bounds)
- [ ] Test rapid layout switching (stress test)
- [ ] Test config file loading/saving from disk
- [ ] Test saved setups persistence (write, quit, relaunch, verify)
- [ ] Test with simulated multi-monitor (virtual displays if possible)
- [ ] Measure and assert performance benchmarks (layout application < Xms)

### CI/Infrastructure
- [ ] Set up Mac VM for automated testing (Tart, Anka, or GitHub Actions macOS runners)
- [ ] Configure CI pipeline to run unit tests on every commit
- [ ] Configure CI pipeline to run integration tests on merge to main
- [ ] Add test coverage reporting (lcov/codecov)
- [ ] Automated screenshot capture on test failure

---

## In Progress

- [ ] Test overlay UI functionality
- [ ] Verify Accessibility permissions flow

---

## Todo - Core Features

### Core (WindowThingCore)
- [ ] Add visual feedback callback when layout is applied (return placement results)
- [ ] Support regex matching for window titles in pinned layouts
- [ ] Add layout validation (detect invalid configs before applying)
- [ ] Implement layout diffing (only move windows that need to move)

### UI (WindowThing)
- [ ] Show visual feedback when layout is applied (animation, flash)
- [ ] Animate window transitions

---

## Todo - UI/UX

### Core
- [ ] Generate layout preview data structures for UI consumption

### UI
- [ ] Improve overlay visual design
- [ ] Add dark/light mode support
- [ ] **Live window previews/thumbnails in overlay** (show actual window content via CGWindowListCreateImage)
- [ ] Show current window positions in overlay preview
- [ ] Add keyboard navigation in overlay (arrow keys)

---

## Todo - Configuration

### Core
- [ ] Config file watcher (auto-reload on change)
- [ ] Config validation with helpful error messages
- [ ] Support per-app layout rules
- [ ] Import/export configurations (serialize to shareable format)
- [ ] Config migration for version upgrades

### UI
- [ ] Add hotkey recorder in settings (visual key capture)
- [ ] Add "Launch at Login" toggle (with SMAppService)

---

## Todo - Advanced Features

### Core
- [ ] Spaces/desktop support (detect and switch spaces)
- [ ] Window gaps/margins configuration
- [ ] AppleScript/CLI interface for automation
- [ ] Additional app drivers (vim splits, IDE editors)
- [ ] Cross-monitor sublayout sync (tmux panes matching WindowThing cells)

### UI
- [ ] Window snapping UI (drag to edge)
- [ ] Menu bar layout quick-switch submenu with previews
- [ ] Drag-and-drop layout reordering
- [ ] Layout favorites/pinning

---

## Todo - Polish

### Core
- [ ] Comprehensive error handling with typed errors
- [ ] Logging framework integration (os.log categories)
- [ ] Performance profiling for large window counts

### UI
- [ ] Add app icon
- [ ] Code signing for distribution
- [ ] Notarization for Gatekeeper
- [ ] Crash reporting (Sentry or similar)
- [ ] Analytics (opt-in, privacy-respecting)
- [ ] First-run onboarding flow
- [ ] Accessibility permission request flow

---

## Known Issues

- [ ] Accessibility permission prompt may not appear on first run
- [ ] Config file created in Application Support (may need first-run setup)
- [ ] Some apps (e.g., Electron apps) may have window positioning quirks
- [ ] One pre-existing flaky integration test ("Switch between layouts moves windows")

---

## Notes

- Based on window management from modal-commander (Electron app)
- Uses macOS Accessibility API for window control
- Configuration in YAML at `~/Library/Application Support/WindowThing/config.yaml`
- Default hotkey: `Ctrl+Option+W`
- Tests require Xcode installation (XCTest/Swift Testing frameworks)
