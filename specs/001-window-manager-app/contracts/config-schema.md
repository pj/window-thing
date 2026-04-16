# Contract: YAML Config Schema

**Version**: 2.0 (adds cellHotKeys, cellPickerHotKey)  
**File location**: `~/Library/Application Support/WindowThing/config.yaml`

---

## Full Schema

```yaml
# Activation hotkey for the main overlay (required)
activationHotKey:
  keyCode: <Int>          # Carbon key code
  modifiers: [<String>]   # "command" | "option" | "control" | "shift"

# Per-cell movement hotkeys (optional)
# Keys are cell address strings: "1"–"35" for numeric, "a"–"z" for overflow
cellHotKeys:
  "<address>":
    keyCode: <Int>
    modifiers: [<String>]

# Hotkey to open the interactive cell picker (optional)
cellPickerHotKey:
  keyCode: <Int>
  modifiers: [<String>]

# Named layouts
layouts:
  - name: <String>             # required, must be non-empty
    quickKey: <String>?        # single character, optional
    screenSets:
      - layouts:
          "$PRIMARY": <LayoutNode>           # required in each screen set
          "<Display Name>": <LayoutNode>?    # optional per-monitor overrides

# Saved window position snapshots (optional)
savedSetups:
  - id: <UUID String>
    name: <String>
    createdAt: <ISO8601 Date String>
    windows:
      - application: <String>
        bundleId: <String>?
        windowTitle: <String>?
        frame:
          x: <Double>
          y: <Double>
          width: <Double>
          height: <Double>
        displayName: <String>
```

## LayoutNode Schema

```yaml
# Branch nodes
type: columns
columns: [<LayoutNode>]
percentage: <Double>?   # proportion of parent (0.0–1.0 or 0–100 — normalized on load)

type: rows
rows: [<LayoutNode>]
percentage: <Double>?

# Leaf nodes
type: stack
stackRemaining: true     # collects all windows not pinned elsewhere
percentage: <Double>?

type: stack
windows:                 # explicit list (mutually exclusive with stackRemaining)
  - application: <String>?
    bundleId: <String>?
    windowTitles: [<String>]?

type: pinned
pinned:
  application: <String>?
  bundleId: <String>?
  windowTitles: [<String>]?
percentage: <Double>?

type: empty
percentage: <Double>?
```

## Validation Rules

- `layouts` array must be non-empty for the app to display any layouts.
- Each layout must have at least one `screenSet` with a `$PRIMARY` key.
- `quickKey` values must be unique across all layouts if specified.
- `cellHotKeys` address strings must be valid `CellAddress` values ("1"–"35", "a"–"z").
- `percentage` values, if present, should sum to approximately 100 within their sibling group; the app normalizes them if they don't.
- An unknown `type` value causes that node to be treated as `empty` with a warning logged.

## Backward Compatibility

- The `cellHotKeys` and `cellPickerHotKey` keys are optional; existing configs without them remain valid.
- `windowTitle` (singular, old format) is accepted in `PinnedConfig` and normalized to `windowTitles: [value]`.
