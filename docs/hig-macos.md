# Apple macOS Human Interface Guidelines — Reference for WindowThing

_Updated for macOS 26 Tahoe / Liquid Glass. Sources: [developer.apple.com/design/human-interface-guidelines](https://developer.apple.com/design/human-interface-guidelines), WWDC25 sessions 323, 256, 310, Apple developer documentation._

---

## macOS 26 Tahoe — What Changed

macOS 26 is the largest visual redesign since Big Sur (2020). Key changes affecting WindowThing directly:

- **Liquid Glass material** — replaces the old vibrancy/blur system. Not a simple blur: it simulates real glass (refraction, edge reflection, ambient tinting). More transparent than Sequoia. Two variants: `.regular` (default) and `.clear` (media-rich backgrounds only — don't mix in the same view).
- **Translucent sidebar** — much more see-through; wallpaper bleeds through. Floating aesthetic with depth.
- **Rounder window corners** — contextual corner radius (not a single constant). Use `containerConcentric()` for nested shapes.
- **Left-aligned window titles** — previously centered.
- **Glass toolbar** — toolbar items share a single glass backing element; the toolbar "floats" and adapts as content scrolls under it.
- **`buttonStyle(.glass)` / `.glassProminent`** — new button styles replacing `.bordered` / `.borderedProminent` for controls that sit on glass backgrounds.

**Free upgrades on recompile with Xcode 26:** Toolbar, Sidebar (`NavigationSplitView`), NSPopover, window controls — all get Liquid Glass automatically. No code changes needed for those.

---

## 1. Window Structure

### What the HIG says (macOS 26)
- Standard app: `NavigationSplitView` gives full-height Liquid Glass sidebar automatically.
- Floating panels (like WindowThing's overlay): not a `NavigationSplitView`. Glass must be applied more deliberately.
- Window corners are significantly rounder — use `containerConcentric()` for custom rounded rects inside windows.
- Title bar is transparent; toolbar floats with glass backing.

### How it applies to WindowThing
The overlay is a `.floating` level fixed-size panel (960×640). It does not use `NavigationSplitView` so it will not automatically get a glass sidebar. We need to apply glass to the sidebar explicitly.

The window uses `.titled` + `.closable` style mask. In macOS 26 the title bar is translucent — this works with our existing window setup.

---

## 2. Sidebar

### What the HIG says (macOS 26)
- Sidebars use Liquid Glass material — translucent, reflects surrounding content.
- `List` with `.listStyle(.sidebar)` in a `NavigationSplitView` gets the glass automatically.
- Outside `NavigationSplitView` (custom panels), you need to apply glass manually using `NSVisualEffectView` with `.sidebar` material or the new `glassEffect()` modifier.
- Selection: still accent color, but renders against glass background.
- Labels adapt automatically: `labelColor` → white on selected accent rows.
- `backgroundExtensionEffect` modifier: allows sidebar background to bleed past view boundaries for seamless edge treatment.

### How it applies to WindowThing
`List` with `.listStyle(.sidebar)` is correct and gets the glass material on macOS 26 automatically via the framework. Since our `LayoutSidebarView` embeds a `List` inside a plain `VStack` inside a fixed-width column (not a `NavigationSplitView`), the glass may not extend to the full sidebar height. The bottom toolbar area needs its own background treatment.

---

## 3. Controls — New macOS 26 Button Styles

### What the HIG says
Two new button styles replace the old bordered system for controls on glass surfaces:

| Style | Use | Replaces |
|-------|-----|---------|
| `.glass` | Standard interactive button on glass | `.bordered` |
| `.glassProminent` | Primary CTA on glass | `.borderedProminent` |
| `.glass.interactive()` | Touch-like feedback (shimmer on press) | — |
| `.glass.tint(.blue)` | Tinted glass button | — |

For AppKit: `button.bezelStyle = .glass`.

**`GlassEffectContainer`** — when you have multiple glass buttons near each other, wrap them in `GlassEffectContainer`. Glass cannot correctly sample through other glass; the container groups them so they share one sampling region and can morph between states.

```swift
GlassEffectContainer(spacing: 16) {
    HStack {
        Button("Cancel") { }.buttonStyle(.glass)
        Button("Save") { }.buttonStyle(.glassProminent).tint(.blue)
    }
}
```

**`glassEffectID`** — pairs with `glassEffectContainer` namespace for morphing transitions between two states (e.g., a button expanding into a sheet).

### How it applies to WindowThing
The `EditorTopBar` Cancel / Save buttons should use `.glass` / `.glassProminent` when running on macOS 26. The sidebar `+` / `−` / duplicate toolbar buttons should use `.glass` or remain `.borderless` (borderless is still valid for icon-only controls in source lists).

For maximum correctness: wrap Cancel + Save in a `GlassEffectContainer`.

---

## 4. Glass Effect Modifier

### API
```swift
// Basic glass background
view.glassEffect()

// With explicit shape
view.glassEffect(in: .rect(cornerRadius: 10))

// Container concentric — matches containing window's corner radius
view.glassEffect(in: .rect(corner: .containerConcentric()))

// Interactive (shimmer feedback on press)
button.glassEffect(.regular.interactive())

// Tinted
button.glassEffect(.regular.tint(.blue))
```

### Rules
- Apply to **navigation chrome and floating controls** (toolbars, headers, sidebars, buttons).
- **Do not** apply to content layers (the layout tile canvas, window lists, editor areas).
- Accessibility (Reduce Transparency, Increase Contrast) is handled automatically — no guards needed.
- `.clear` variant for media-rich contexts only; never mix `.clear` and `.regular` in one view.

### How it applies to WindowThing
- `EditorTopBar` background: replace `Color(nsColor: .windowBackgroundColor)` with `.glassEffect()`
- Sidebar bottom toolbar: `.glassEffect()` or keep solid (it's below the glass `List`)
- Layout tile canvas: leave as `Color(nsColor: .controlBackgroundColor)` — this is content, not chrome

---

## 5. Corner Concentricity

macOS 26 windows have larger, contextual corner radii. Custom rounded rects inside a window should match the window's curvature rather than using a hardcoded value.

```swift
// Instead of hardcoded cornerRadius:
RoundedRectangle(cornerRadius: 8)

// Use container-concentric:
.clipShape(.rect(cornerRadius: .containerConcentric()))
// or for the shape itself:
UnevenRoundedRectangle(cornerRadii: .init(
    topLeading: .containerConcentric(),
    // ...
))
```

### How it applies to WindowThing
The selection highlight in `LayoutSidebarRow` uses `RoundedRectangle(cornerRadius: 8)`. This should become `containerConcentric()` for correct nesting. Similarly for tile backgrounds in `LayoutEditorView`.

---

## 6. Typography (unchanged from pre-26)

| Style | Size | Weight | Use for |
|-------|------|--------|---------|
| Title 3 | 15 pt | Regular | Panel/page headings |
| Headline | 13 pt | Semibold | Section labels |
| Body | 13 pt | Regular | Sidebar items, body text |
| Callout | 12 pt | Regular | Secondary info |
| Subheadline | 11 pt | Regular | Section headers, helper text |
| Footnote | 10 pt | Regular | Captions, badges |

WindowThing's current typography is correct. No changes needed.

---

## 7. Color (updated for macOS 26)

Semantic colors still apply. Use `Color(.labelColor)`, `Color(.separatorColor)`, etc. — these adapt correctly inside glass surfaces.

**Important for glass surfaces:** colors inside a glass view are rendered with vibrancy. Semantic colors like `labelColor` and `secondaryLabelColor` automatically get the correct vibrancy treatment. Avoid hardcoded hex/RGB values inside glass areas.

**Selection colors:** Still `selectedContentBackgroundColor` (accent, focused) and `unemphasizedSelectedContentBackgroundColor` (gray, unfocused). `List` handles this automatically.

---

## 8. Priority Changes for WindowThing (macOS 26)

### Already correct
- `List` + `.listStyle(.sidebar)` — gets Liquid Glass automatically ✓
- Semantic colors (`Color(.labelColor)`, `Color(.separatorColor)`, etc.) ✓
- No hardcoded selection color ✓

### Should update
1. **`EditorTopBar` background** — replace solid `Color(nsColor: .windowBackgroundColor)` with `.glassEffect()` 
2. **Cancel / Save buttons** — use `.glass` / `.glassProminent` wrapped in `GlassEffectContainer`
3. **Sidebar bottom toolbar** — use `.glassEffect()` instead of solid background
4. **Tile/row corner radii** — use `.containerConcentric()` instead of hardcoded values where appropriate

---

## Quick Reference Cheatsheet (macOS 26)

```swift
// Sidebar — .listStyle(.sidebar) gets Liquid Glass automatically
List(layouts, id: \.id, selection: $selected) { layout in
    LayoutSidebarRow(layout: layout)
}
.listStyle(.sidebar)

// Glass background on chrome areas (toolbar, header bar)
someView
    .padding(.horizontal, 16).padding(.vertical, 10)
    .glassEffect()

// Buttons on glass surfaces
GlassEffectContainer {
    HStack {
        Button("Cancel") { }.buttonStyle(.glass)
        Button("Save") { }.buttonStyle(.glassProminent).tint(Color.accentColor)
    }
}

// Corner concentricity — matches window corner radius
.clipShape(.rect(cornerRadius: .containerConcentric()))

// Semantic colors — always, never hardcode
Color(.labelColor)             // primary text
Color(.secondaryLabelColor)    // secondary/icons
Color(.separatorColor)         // dividers, borders
Color(.controlBackgroundColor) // content areas (canvas)
Color(.windowBackgroundColor)  // fallback for solid areas

// Only on non-glass content areas (canvas, editor)
.background(Color(nsColor: .controlBackgroundColor))
```
