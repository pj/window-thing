# window_thing Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-11

## Active Technologies

- **Language**: Swift 5.9, macOS 13+
- **Dependencies**: Yams 5.x (YAML parsing), HotKey 0.2.x (global shortcuts), ViewInspector 0.10.x (SwiftUI testing)
- **Storage**: YAML config file at `~/Library/Application Support/WindowThing/config.yaml`; UserDefaults for `lastUsedLayoutId`, `seenDisplayNames`, `hasCompletedOnboarding`
- **Build system**: Swift Package Manager
- **Permissions required**: Accessibility API (window control) + Screen Recording (thumbnail capture, optional with fallback)

## Project Structure

```text
Sources/
  WindowThingCore/        # Pure logic — no UI, no AppKit. Yams only.
  WindowThingViewModel/   # OverlayViewModel, WindowThumbnailCache. AppKit + Combine. No SwiftUI.
  WindowThingCanvas/      # Generic SwiftUI tile views. No domain dependencies.
  WindowThing/            # App entry point, menubar, hotkey registration. SwiftUI + HotKey.
  WindowThingCanvasDemo/  # Standalone canvas preview app.

Tests/
  WindowThingTests/             # Core logic tests (164 baseline + new)
  WindowThingViewModelTests/    # ViewModel tests (29 baseline + new)
  WindowThingCanvasTests/       # Canvas SwiftUI tests (ViewInspector)
```

## Commands

```bash
swift build                          # Build all targets
swift run WindowThing                # Run the menubar app
swift run WindowThingCanvasDemo      # Run canvas preview
swift test                           # Run all tests (193 baseline)
swift test --filter WindowThingTests # Run specific target tests
```

## Code Style

- Never import SwiftUI in `WindowThingCore` or `WindowThingViewModel`
- Never import `WindowThing` (app target) from library targets
- Core logic must be pure (no side effects) and fully testable without running the app
- Use `WTWindow` / `WTLayout` type aliases in app target to avoid SwiftUI name conflicts (see `TypeAliases.swift`)

## Key New Files (planned, not yet implemented)

- `Sources/WindowThingCore/Services/CellIndexer.swift` — global cell enumeration across displays
- `Sources/WindowThingCore/Services/DisplayRegistry.swift` — persists seen display names to UserDefaults
- `Sources/WindowThingViewModel/WindowThumbnailCache.swift` — background screenshot polling (3s default)
- `Sources/WindowThingCanvas/CellPickerView.swift` — interactive cell picker with ghost tiles
- `Sources/WindowThing/Views/OnboardingView.swift` — 3-step first-run flow

## Recent Changes

- 001-window-manager-app: Full app spec — layout editor completion, cell movement hotkeys, cell picker, ghost cells, DisplayRegistry, WindowThumbnailCache, onboarding, dynamic menubar icons

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
