# Feature Specification: WindowThing macOS Window Manager App

**Feature Branch**: `001-window-manager-app`  
**Created**: 2026-04-08  
**Status**: Draft  
**Input**: User description: "This repository contains an inprogress swift app for managing windows. I want to generate and iterate on a spec for it. You should use this repository, the code base at ~/modal-commander and previous chat transcripts at ~/.claude/projects."

## Overview

WindowThing is a lightweight, keyboard-driven window management utility for macOS that runs as a menubar app. It allows power users to define named layout configurations and instantly arrange all open windows on one or more monitors into those layouts using global hotkeys or a quick-access overlay. The app targets developers, designers, and other professionals who regularly work with multiple windows and monitors and want to eliminate the friction of manual window arrangement.

---

## Clarifications

### Session 2026-04-08 (movement hotkeys)

- Q: How should individual window movement hotkeys identify the destination — directional (left/right/up/down), named cell, or indexed position? → A: Indexed — hotkeys target a numbered cell or monitor by index.
- Q: Does cell numbering follow the active layout's leaf tiles or a fixed grid? → A: Active layout cells, numbered left-to-right, top-to-bottom.
- Q: When moving a window to a different monitor, does the user specify the monitor and cell separately, or is there a unified cell index? → A: Cells are globally indexed across all monitors in the active layout (left-to-right, top-to-bottom, monitor by monitor). Indices use numerals (1, 2, 3…) and overflow to letters (a, b, c…). A single hotkey moves the focused window to that global cell.
- Q: Should cell indices be displayed visually in the overlay and/or editor canvas? → A: Overlay canvas only — not in the editor.
- Q: What happens when a "move to cell" hotkey is pressed with no active layout, and how is the destination confirmed? → A: Pressing a move hotkey shows an interactive cell picker overlay displaying current cells plus "ghost" extension cells at the trailing edges (right of the last column, below the last row). The user selects a destination by clicking or by navigating with arrow keys and pressing Enter. Selecting a ghost cell extends the layout by adding a new region there.

### Session 2026-04-08 (live state & previews)

### Session 2026-04-08 (layout editor completion)

- Q: Should new layouts be created via the visual editor or the YAML config? → A: Editor-first — the overlay has an "Add Layout" button; YAML remains an advanced alternative.
- Q: Should the visual editor support managing multiple screen sets per layout? → A: Yes, full editor support — users can add, remove, and switch between screen sets; but available monitors are restricted to displays previously connected to this machine (no manual name entry).
- Q: Should tile inline controls be always visible or only on the selected tile? → A: Hover-triggered — controls fade in when the cursor is over a tile, regardless of click selection.
- Q: What starting structure should a new layout have, and are there other creation flows? → A: Single full-screen stack. Users can also duplicate any existing layout from within the overlay.
- Q: Where do layout management actions (Add, Duplicate, Delete) live in the overlay UI? → A: A persistent action bar below the carousel with ＋ Add, ⧉ Duplicate, and 🗑 Delete buttons always visible.

- Q: What should cell tiles display for current window representation — app icons, screenshot thumbnails, or colored blocks? → A: Live screenshot thumbnails — actual pixel captures of each window, scaled to fit the cell tile.
- Q: Should thumbnail captures happen once on overlay open, in real-time while open, or via a background process? → A: A background process periodically captures and caches window screenshots; the overlay and menubar icons read from this cache.
- Q: How frequently should the background thumbnail process poll? → A: Every 2–5 seconds, configurable, default 3 seconds; also refreshes immediately on window-change events.
- Q: When should menubar layout icons regenerate? → A: On every thumbnail cache refresh — same cadence as the background capture process. [superseded by Q5]
- Q: Should menubar icons composite window thumbnails or show layout shape only? → A: Shape-only — dynamically generated to match the layout tree proportions, no thumbnail compositing. Thumbnails are exclusive to the overlay canvas.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Apply a Layout with a Hotkey (Priority: P1)

A user has a "coding" layout defined (editor left, terminal right) and a "meeting" layout (browser full-screen). With a single keyboard shortcut they instantly rearrange all their windows without touching the mouse.

**Why this priority**: This is the core value proposition of the app. Everything else depends on layouts being applicable quickly. A user who can only do this has already received value.

**Independent Test**: Can be fully tested by configuring two layouts in the config file, opening several app windows, pressing the hotkeys, and verifying windows land in correct positions.

**Acceptance Scenarios**:

1. **Given** at least one named layout is configured, **When** the user presses the assigned hotkey for that layout, **Then** all open windows on the current display are arranged to match the layout within 1 second.
2. **Given** multiple layouts are configured, **When** the user presses different hotkeys, **Then** each hotkey applies the correct corresponding layout.
3. **Given** no windows are open for a pinned app in the layout, **When** the layout is applied, **Then** the remaining windows are placed correctly and no error is shown.
4. **Given** the app lacks accessibility permissions, **When** the user presses a layout hotkey, **Then** a clear prompt is shown requesting the necessary permission.

---

### User Story 2 - Browse and Apply Layouts via Overlay (Priority: P2)

A user who doesn't remember hotkeys (or has more than 9 layouts) opens the overlay window to see all their layouts visually, browse them with arrow keys, and apply one by pressing Enter or clicking.

**Why this priority**: Makes the app accessible beyond power-user hotkey recall. Also serves as a discoverability tool when onboarding.

**Independent Test**: Can be fully tested by triggering the overlay, navigating the carousel with keyboard and mouse, and applying a layout.

**Acceptance Scenarios**:

1. **Given** the app is running, **When** the user presses the global activation hotkey (default: Cmd+Shift+Space), **Then** the overlay appears centered on the current display within 300ms.
2. **Given** the overlay is open, **When** the user presses arrow keys, **Then** the carousel scrolls through layouts and the canvas updates to show the selected layout's structure.
3. **Given** the overlay is open, **When** the user presses Enter or clicks a layout card, **Then** the layout is applied and the overlay closes.
4. **Given** the overlay is open, **When** the user presses Escape, **Then** the overlay closes without applying any layout.

---

### User Story 3 - Edit a Layout Visually (Priority: P3)

A user wants to adjust an existing layout — split a tile into columns, change which app is pinned to a region, or rename the layout — without editing YAML by hand.

**Why this priority**: Lowers the barrier to entry significantly. YAML editing requires knowing the config schema; the visual editor makes layout creation accessible to non-technical users.

**Independent Test**: Can be fully tested by opening the overlay, selecting a layout, making a structural change (split/merge/rename), saving, and verifying the change persists and is applied correctly.

**Acceptance Scenarios**:

1. **Given** the overlay is open with a layout selected, **When** the user clicks a tile and uses the inline controls to split it into columns, **Then** the canvas immediately reflects the new structure.
2. **Given** the user has made changes to a layout, **When** they click Save, **Then** the layout is persisted and available for future use.
3. **Given** the user has made changes they want to discard, **When** they click Cancel, **Then** the layout reverts to its previous state.
4. **Given** the user has made a change, **When** they use undo, **Then** the previous state of the layout is restored.
5. **Given** a tile is selected, **When** the user drags a running app from the app list onto the tile, **Then** that app is pinned to that tile.

---

### User Story 4 - Multi-Monitor Layout Assignment (Priority: P4)

A user who docks their laptop to an external monitor (or works at a desk with two displays) wants different layout behavior per-monitor configuration — a "desk" layout when docked and a "laptop" layout when undocked.

**Why this priority**: Multi-monitor use is common for the target audience, and without this, the app degrades to single-display usefulness for a significant user segment.

**Independent Test**: Can be tested by configuring screen sets for two different display configurations, plugging/unplugging a monitor, and verifying the correct layout is auto-selected.

**Acceptance Scenarios**:

1. **Given** a layout is configured with screen sets for multiple display configurations, **When** the user's monitor setup matches one of the screen sets, **Then** that screen set is automatically selected when the layout is applied.
2. **Given** no screen set matches the current monitor configuration, **When** a layout is applied, **Then** the layout falls back to applying all windows to the primary display.
3. **Given** the user plugs in or unplugs a monitor, **When** the display configuration changes, **Then** the previously active layout is automatically reapplied using the best matching screen set.

---

### User Story 5 - First-Run Setup and Onboarding (Priority: P5)

A new user downloads and opens the app for the first time. They are guided through granting accessibility permissions, understanding how to configure layouts, and activating the app.

**Why this priority**: Without onboarding, new users will be confused by the blank state or inability to control windows (missing accessibility permission). Needed before any public release.

**Independent Test**: Can be tested by running the app on a fresh macOS user account, confirming the onboarding flow is presented, and verifying the user can complete setup and apply their first layout.

**Acceptance Scenarios**:

1. **Given** the app is launched for the first time, **When** accessibility permission has not been granted, **Then** the app presents a clear explanation of why the permission is needed and directs the user to System Settings.
2. **Given** no config file exists, **When** the app is launched, **Then** a default configuration with sample layouts is created so the user can see a working example immediately.
3. **Given** the user has granted permissions and a default config exists, **When** they press the global hotkey, **Then** a layout is applied successfully.

---

### Edge Cases

- What happens when the user selects a ghost cell that would create an extremely small region (e.g., already 5+ columns)?
- What happens when an app specified in a pinned tile is not currently running?
- What happens when two layouts share the same hotkey key?
- How does the overlay behave when the user has zero layouts configured?
- What happens when window arrangement fails because an app resists being moved (e.g., system dialogs)?
- How does the app behave during macOS Spaces transitions or Mission Control?
- What happens when the config file is malformed YAML?
- What happens if accessibility permission is revoked while the app is running?
- What happens if Screen Recording permission is granted, then revoked mid-session?
- How does the app handle a window that no longer exists by the time its thumbnail is requested?
- How are windows assigned when multiple windows of the same app are open and only one is pinned?

---

## Requirements *(mandatory)*

### Functional Requirements

**Layout Application**

- **FR-001**: Users MUST be able to define named layouts that specify how windows are divided across the screen using a combination of columns, rows, stacked regions, and pinned-app regions.
- **FR-002**: Users MUST be able to assign a single-key hotkey to each layout for instant application.
- **FR-003**: The app MUST apply a layout by repositioning and resizing all eligible windows within 1 second of activation.
- **FR-004**: When a layout is applied, windows of pinned apps MUST be placed in their designated regions; all other windows MUST be placed in the designated stack region.
- **FR-005**: When a pinned app has no open window at apply time, the layout MUST still be applied to all other windows without error.

**Overlay Interface**

- **FR-006**: The app MUST provide a global overlay window triggered by a configurable hotkey that displays all defined layouts.
- **FR-007**: The overlay MUST allow keyboard navigation (arrow keys to browse, Enter to apply, Escape to dismiss).
- **FR-008**: The overlay MUST display a visual representation of each layout's tile structure, with each leaf cell labelled by its global index (1, 2, 3… a, b, c…) so users can identify which hotkey corresponds to which region.
- **FR-009**: The overlay MUST show the hotkey shortcut associated with each layout.

**Visual Layout Editor**

- **FR-010**: Users MUST be able to split any layout tile into columns or rows from within the overlay.
- **FR-011**: Users MUST be able to change the type of a tile (stack, pinned, empty) using inline controls that appear when the cursor hovers over the tile. Controls MUST fade out when the cursor leaves the tile.
- **FR-012**: Users MUST be able to pin a specific running app to a tile by dragging the app onto the tile.
- **FR-013**: Users MUST be able to resize tile proportions by dragging the dividers between tiles.
- **FR-014**: Users MUST be able to rename a layout from the overlay.
- **FR-015**: The app MUST support undo for layout edits within an editing session.
- **FR-016**: Layout changes MUST be explicitly saved by the user; unsaved changes MUST be discardable.
- **FR-044**: Users MUST be able to create a new layout via an ＋ Add button in a persistent action bar below the overlay carousel. A new layout starts as a single full-screen stack region and opens immediately in the editor.
- **FR-044b**: Users MUST be able to duplicate the currently selected layout via a ⧉ Duplicate button in the same action bar. The duplicate opens immediately in the editor with a default name derived from the original (e.g., "Coding copy").
- **FR-045**: Users MUST be able to delete the currently selected layout via a 🗑 Delete button in the action bar. Deletion MUST be confirmed before taking effect. Deleting the last remaining layout MUST be blocked.
- **FR-046**: The YAML config file remains a supported alternative for creating and editing layouts for power users.
- **FR-047**: The visual editor MUST allow users to add, switch between, and remove screen sets for a layout. The set of selectable monitors MUST be restricted to displays the machine has previously connected; users cannot enter monitor names manually.
- **FR-048**: The app MUST maintain a persistent registry of all display names it has ever observed, so previously connected monitors remain available as screen set targets even when not currently plugged in.

**Multi-Monitor Support**

- **FR-017**: Layouts MUST support multiple screen sets, each matching a specific named display configuration.
- **FR-018**: When a layout is applied, the app MUST automatically select the screen set that best matches the current monitor configuration.
- **FR-019**: When no screen set matches, the app MUST fall back to placing all windows on the primary display.
- **FR-020**: The app MUST automatically reapply the current layout when the display configuration changes.

**Configuration**

- **FR-021**: The app MUST load layout configuration from a human-readable file in the user's application support directory.
- **FR-022**: The app MUST create a default configuration with sample layouts on first launch if no config file exists.
- **FR-023**: The app MUST surface a clear, actionable error when the config file cannot be parsed.

**Permissions & Accessibility**

- **FR-024**: The app MUST request accessibility permission on first use and explain its purpose.
- **FR-025**: The app MUST gracefully handle accessibility permission being unavailable, displaying an explanation rather than crashing or silently failing.
- **FR-041**: The app MUST request Screen Recording permission to capture window thumbnails, and MUST explain its purpose separately from the accessibility permission request.
- **FR-042**: When Screen Recording permission is unavailable, the app MUST fall back to displaying app icons in place of screenshot thumbnails; all other functionality MUST remain unaffected.

**Individual Window Movement**

- **FR-029**: Users MUST be able to assign a hotkey per cell that moves the currently focused window into that cell, where cells are globally indexed across all monitors using the active layout's leaf tiles ordered left-to-right, top-to-bottom per monitor, then continuing across monitors. Indices use numerals (1, 2, 3…) overflowing to letters (a, b, c…).
- **FR-030**: Moving a window to a cell on a different monitor via its global cell index MUST reposition and resize the window to fill that cell's bounds on the appropriate monitor.
- **FR-031**: When a movement hotkey is triggered, the app MUST display a cell picker overlay showing all current layout cells labelled by their global index, plus "ghost" cells at the trailing edges (after the last column, below the last row) indicating where new regions can be added.
- **FR-032**: Within the cell picker overlay, the user MUST be able to select a destination by clicking a cell or by navigating with arrow keys and pressing Enter.
- **FR-033**: Selecting a ghost cell in the picker MUST extend the active layout by inserting a new region at that position, then move the focused window into it.
- **FR-034**: If no layout is currently active when a movement hotkey is pressed, the app MUST auto-apply the most recently used layout before showing the cell picker.

**Window Previews & Live State**

- **FR-035**: The overlay canvas MUST display a visual representation of the currently active window arrangement within each cell — showing which windows or apps are present in each region at the time the overlay opens.
- **FR-036**: The overlay layout picker cards (carousel) MUST reflect the current window state, not just the abstract layout structure, so users can see at a glance what is in each layout region right now.
- **FR-037**: Each cell tile in the overlay canvas MUST render a live screenshot thumbnail of the window(s) currently occupying that cell, scaled to fit the tile bounds.
- **FR-038**: The app MUST run a background process that periodically captures and caches screenshot thumbnails for all visible windows. The overlay and menubar icons MUST read from this cache, not capture on demand. The capture interval MUST default to 3 seconds and be configurable between 2 and 5 seconds.
- **FR-043**: The thumbnail cache MUST also refresh immediately when window-change events occur (app launch, quit, focus change), not only on the polling interval.

**Menubar**

- **FR-026**: The app MUST run as a menubar utility (no Dock icon) and remain running in the background.
- **FR-027**: The menubar menu MUST list all defined layouts and allow direct application by clicking.
- **FR-028**: The menubar menu MUST include access to settings and the option to quit the app.
- **FR-039**: The menubar layout icons MUST be dynamically generated to match the actual shape and proportions of each layout (correct column/row structure and relative tile sizes, not a generic icon). Icons regenerate when layout structure or config changes.
- **FR-040**: Menubar layout icons display layout shape only — no window thumbnail compositing. Screenshot thumbnails are used exclusively within the overlay canvas.

---

### Key Entities

- **Layout**: A named, saveable window arrangement. Has a name, an optional hotkey, and one or more screen sets.
- **ScreenSet**: A mapping of display configurations to layout trees. Identifies which set of monitors it applies to.
- **LayoutNode**: A recursive tree node representing a screen region. Can be split into columns or rows, or be a leaf (pinned app, stack of apps, or empty).
- **SavedSetup**: A snapshot of the actual window positions at a point in time, distinct from a layout definition.
- **RunningApp**: A currently active application that can be pinned to a layout tile.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from zero to having their first layout applied within 5 minutes of installing the app, using only the default config and onboarding flow.
- **SC-002**: Pressing a layout hotkey arranges all open windows to match the layout in under 1 second on typical hardware.
- **SC-003**: Users can create a new two-region layout and assign an app to one region using only the visual editor (no config file editing) in under 3 minutes.
- **SC-004**: The overlay opens and is ready for interaction within 300 milliseconds of the activation hotkey being pressed.
- **SC-005**: When plugging in or unplugging a monitor, the correct screen set is selected and the layout reapplied automatically with no manual intervention required.
- **SC-006**: 90% of new users successfully apply a layout on their first session without needing external documentation.
- **SC-007**: A user can move the focused window to any cell across all connected monitors in under 3 keystrokes from the movement hotkey trigger.

---

## Assumptions

- The target user is a macOS power user (developer, designer, or similar) who works with many windows and multiple monitors.
- The app targets macOS 13 (Ventura) and later; older macOS versions are out of scope.
- Distribution is outside the Mac App Store (direct download or Homebrew) so Accessibility API usage is not sandboxed.
- The config file format is YAML; a GUI settings panel for non-layout preferences (launch at login, global hotkey) is in scope but a lower priority than the core layout features.
- "Windows" refers to standard application windows controllable via the macOS Accessibility API; system UI elements (Dock, menubar, control center) are not managed.
- The app manages windows on the current Space only; cross-Space window movement is out of scope for v1.
- Hotkey conflicts with other apps are the user's responsibility to avoid; the app will warn on startup if a registered hotkey cannot be claimed.
- Saving a layout from the visual editor writes back to the YAML config file; no separate database is needed.
