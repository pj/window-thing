# Quickstart: WindowThing Development Guide

**Branch**: `001-window-manager-app` | **Date**: 2026-04-08

---

## Building & Running

```bash
# Build all targets
swift build

# Run the app (opens as menubar icon)
swift run WindowThing

# Run the canvas demo (useful for UI iteration without the full app)
swift run WindowThingCanvasDemo
```

## Running Tests

```bash
# All tests
swift test

# Specific test targets
swift test --filter WindowThingTests
swift test --filter WindowThingViewModelTests
swift test --filter WindowThingCanvasTests
```

Current baseline: 193 passing tests. One known flaky integration test ("Switch between layouts") — pre-existing, not a regression signal.

---

## Project Structure at a Glance

| Target | What it is | Can depend on |
|--------|-----------|---------------|
| `WindowThingCore` | Pure logic, no UI | Yams only |
| `WindowThingViewModel` | Overlay state, AppKit+Combine | WindowThingCore |
| `WindowThingCanvas` | SwiftUI tile views | Nothing (no domain deps) |
| `WindowThing` | App entry, menubar, hotkeys | All three above + HotKey |
| `WindowThingCanvasDemo` | Canvas preview app | WindowThingCanvas |

**Rule**: Never import `WindowThing` from lower targets. Never import `SwiftUI` in `WindowThingCore` or `WindowThingViewModel`.

---

## Key Files for New Work

### Cell Indexing (Group A)
- Create: `Sources/WindowThingCore/Services/CellIndexer.swift`
- Create: `Tests/WindowThingTests/CellIndexerTests.swift`
- Modify: `Sources/WindowThingCore/Models/Layout.swift` — add `CellAddress` type

### Per-Cell Hotkeys (Group B)
- Modify: `Sources/WindowThingCore/Models/Config.swift` — add `cellHotKeys`, `cellPickerHotKey`
- Modify: `Sources/WindowThingCore/Services/LayoutManager.swift` — add `moveWindow`, `lastUsedLayout`
- Modify: `Sources/WindowThing/WindowThingApp.swift` — register cell HotKey objects

### Cell Picker Overlay (Group C)
- Create: `Sources/WindowThingCanvas/CellPickerView.swift`
- Modify: `Sources/WindowThingViewModel/OverlayViewModel.swift` — add picker state
- Modify: `Sources/WindowThing/Views/OverlayWindow.swift` — present picker

### Ghost Cells (Group D)
- Modify: `Sources/WindowThingCore/Services/LayoutModification.swift` — append helpers

### Canvas Cell Labels (Group E)
- Modify: `Sources/WindowThingCanvas/LayoutCanvasView.swift` — show index labels in overlay mode

### Onboarding (Group F)
- Create: `Sources/WindowThing/Views/OnboardingView.swift`
- Modify: `Sources/WindowThingCore/Services/ConfigManager.swift` — verify default config creation

---

## Config File Location

```
~/Library/Application Support/WindowThing/config.yaml
```

Sample config with cell hotkeys:

```yaml
activationHotKey:
  keyCode: 49    # Space
  modifiers: [command, shift]

cellHotKeys:
  "1":
    keyCode: 18  # 1
    modifiers: [command, option]
  "2":
    keyCode: 19  # 2
    modifiers: [command, option]
  "3":
    keyCode: 20  # 3
    modifiers: [command, option]

layouts:
  - name: "Code"
    quickKey: "c"
    screenSets:
      - layouts:
          "$PRIMARY":
            type: columns
            columns:
              - type: pinned
                percentage: 60
                pinned:
                  application: "Xcode"
              - type: stack
                percentage: 40
                stackRemaining: true
```

---

## Testing New Code

### CellIndexer tests pattern

```swift
func testSingleDisplayTwoCells() {
    let layout = Layout(name: "Test", screenSets: [
        ScreenConfig(layouts: ["$PRIMARY": .columns([.stackAll(percentage: 50), .stackAll(percentage: 50)])])
    ])
    let displays = [Display(name: "Built-in", frame: WindowFrame(x: 0, y: 0, width: 1440, height: 900))]
    let cells = CellIndexer.indexCells(layout: layout, displays: displays)
    XCTAssertEqual(cells.count, 2)
    XCTAssertEqual(cells[0].address, .numeric(1))
    XCTAssertEqual(cells[1].address, .numeric(2))
}
```

### LayoutModification ghost cell tests pattern

```swift
func testAppendTrailingColumn() {
    let node = LayoutNode.columns([.stackAll(percentage: 50), .stackAll(percentage: 50)])
    let result = LayoutModification.appendTrailingColumn(to: node)
    XCTAssertEqual(result.columns?.count, 3)
}
```
