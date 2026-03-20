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
- Accessibility permissions (required for window management)

## Installation

### Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/window-thing.git
cd window-thing

# Build with Swift
swift build -c release

# Create app bundle
./scripts/build.sh

# Copy to Applications
cp -R .build/WindowThing.app /Applications/
```

### Using Nix Flakes

```bash
# Enter development shell
nix develop

# Build
swift build -c release
```

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
Sources/WindowThing/
├── WindowThingApp.swift    # Main app entry point & AppDelegate
├── Models/
│   ├── Config.swift        # Configuration types
│   ├── Layout.swift        # Layout data model
│   └── Window.swift        # Window/Monitor types
├── Services/
│   ├── ConfigManager.swift # YAML config handling
│   ├── LayoutManager.swift # Layout application logic
│   └── WindowManager.swift # macOS window control (Accessibility API)
└── Views/
    ├── OverlayWindow.swift # Main overlay UI
    └── SettingsView.swift  # Settings panel
```

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
