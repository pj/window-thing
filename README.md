# WindowThing

A lightweight, keyboard-driven window management app for macOS, built with Swift and SwiftUI.

Inspired by the window management functionality from [modal-commander](https://github.com/modal-commander), this standalone app runs in the background and provides quick access to window layouts via hotkeys and menubar.

## Features

- **Global Hotkey Activation** - Press `Cmd+Shift+Space` (configurable) to show the layout selector
- **YAML Configuration** - Human-readable config file for all settings and layouts
- **Multiple Layout Presets** - Define layouts with columns, rows, and pinned apps
- **Quick Keys** - Assign single-key shortcuts to your favorite layouts
- **Menubar Integration** - Quick access to layouts and saved setups from the menubar
- **Save/Load Setups** - Save your current window arrangement and restore it later
- **Multi-Monitor Support** - Different layouts for different monitor configurations

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission — required; the app cannot move windows without it
- Screen Recording permission — optional, for live window thumbnails (falls back to app icons)

## Installation

Releases are Developer ID signed, notarized and stapled, so they run on any Mac without a
Gatekeeper prompt.

### Download (recommended)

Grab `WindowThing.zip` from the [latest release](https://github.com/pj/window-thing/releases/latest),
unzip it, and drag `WindowThing.app` to `/Applications`. Enable **Launch at Login** in
Preferences if you want it to start with your Mac.

It keeps itself up to date from there: there's a **Check for Updates…** item in the menubar menu,
and it checks once a day in the background. Updates are cryptographically signed, and installing
one always asks first.

### Nix flake

```nix
{
  inputs.window_thing.url = "github:pj/window-thing?ref=v0.4.0";
}
```

Then add it to your packages:

```nix
window_thing.packages.${pkgs.stdenv.hostPlatform.system}.default
```

This installs the prebuilt, signed app — not a source build. That matters: macOS keys the
Accessibility grant to the code signature, so an unsigned build would lose its permission on
every upgrade. See [RELEASE.md](RELEASE.md) for the details.

**Nix installs do not self-update.** `/nix/store` is read-only, so Sparkle cannot replace the
bundle; the app detects this and shows "Updates managed by nix" rather than offering a check that
could only fail. Updating means bumping the flake input, and starting it at login means writing
your own launchd agent — "Launch at Login" is disabled for the same reason, since nix owns the
process. If you'd rather the app manage both itself, use the download above.

### Building from source

```bash
git clone https://github.com/pj/window-thing.git
cd window-thing

nix develop            # or ensure Xcode is installed
swift build -c release

scripts/package.sh --no-sign     # → build/WindowThing.app
```

A source build is fine for development, but it is ad-hoc signed, so macOS will make you
re-grant Accessibility after every rebuild.

## Scripting

WindowThing is scriptable, so layouts can be applied from other tools:

```applescript
tell application "WindowThing"
    list layouts                          --> {"Fullscreen", "Half Split", …}
    current layout                        --> "Half Split"
    apply layout "Thirds"

    add layout                            --> "Layout 6"
    rename layout "Layout 6" to "Coding"
    delete layout "Coding"

    show layout editor
    hide layout editor
    layout editor is open                 --> true
end tell
```

`delete layout` deliberately bypasses the confirmation the interface shows — a
script has already said what it wants. `show layout editor with pinned` keeps
the editor up when the app loses focus, which is what screenshot and test
tooling needs.

## Usage

### Quick Start

1. Launch WindowThing - it will appear in your menubar
2. Grant Accessibility permissions when prompted
3. Press `Cmd+Shift+Space` to open the layout selector
4. Click a layout or press its quick key to apply

### Configuration

Configuration is stored in `~/Library/Application Support/WindowThing/config.yaml`.

Click the menubar icon and select "Open Config File" to edit.

Example configuration:

```yaml
# Global hotkey to activate WindowThing
activationHotKey:
  keyCode: 49  # Space
  modifiers:
    - command
    - shift

# Visual settings
overlayOpacity: 0.95
overlayBackgroundColor: "#1a1a2e"
highlightColor: "#4a9eff"

# Layout definitions
layouts:
  - name: "Half Split"
    quickKey: "1"
    screenSets:
      - layouts:
          $PRIMARY:
            type: columns
            columns:
              - type: empty
                percentage: 50
              - type: empty
                percentage: 50

  - name: "Coding Layout"
    quickKey: "c"
    screenSets:
      - layouts:
          $PRIMARY:
            type: columns
            columns:
              - type: pinned
                percentage: 60
                pinned:
                  application: "Code"
                  bundleId: "com.microsoft.VSCode"
              - type: rows
                percentage: 40
                rows:
                  - type: pinned
                    percentage: 60
                    pinned:
                      application: "Terminal"
                  - type: pinned
                    percentage: 40
                    pinned:
                      application: "Safari"
```

### Layout Types

| Type | Description |
|------|-------------|
| `empty` | Placeholder space for any window |
| `pinned` | Pin a specific app to this location |
| `columns` | Horizontal split |
| `rows` | Vertical split |
| `stack` | Multiple windows overlapping |
| `float_zoomed` | Combination of floating and zoomed windows |

### Key Codes

Common key codes for hotkey configuration:

| Key | Code | Key | Code |
|-----|------|-----|------|
| Space | 49 | Return | 36 |
| A-Z | 0-45 | 1-0 | 18-29 |
| F1-F12 | 122-111 | Escape | 53 |

Full list: https://eastmanreference.com/complete-list-of-applescript-key-codes

## Keyboard Shortcuts

- `Cmd+Shift+Space` - Open layout selector (default, configurable)
- `1-9` / Quick keys - Apply layout directly from selector
- `Escape` - Close layout selector

## Project Structure

```
Sources/
├── WindowThingCore/        # Layout model and placement. No UI, no AppKit views.
│   ├── Models/             #   Layout, Config, Window, exclusions
│   └── Services/           #   LayoutManager, WindowManager, ConfigManager
├── WindowThingViewModel/   # OverlayViewModel, thumbnail and icon caches
├── WindowThingCanvas/      # Generic tile views, no domain knowledge
└── WindowThing/            # The app: menubar, layout surface, scripting
    ├── WindowThingApp.swift
    ├── ScriptingCommands.swift
    └── Views/
        ├── SpaceOverlayWindow.swift   # The layout surface
        └── SettingsView.swift
```

The layout surface is one screen: browsing windows and editing layouts happen in
the same place, with one window per display sharing a single view model.

## Development

```bash
# Enter nix development environment
nix develop

# Build for debugging
swift build

# Run
swift run

# Format code
swift-format -i -r Sources/
```

## License

MIT License
