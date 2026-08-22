# WindowThing VM Testing Infrastructure

Headless integration testing for WindowThing using [Tart](https://tart.run/) (macOS-on-Apple-Silicon VM runner built on Virtualization.framework).

The VM provides:
- A real macOS environment with a virtual WindowServer and display
- Accessibility TCC permissions pre-granted (no interactive prompt needed)
- `swift test` running against real AX APIs and real window frames
- Optional virtual second display for multi-monitor layout tests

---

## Prerequisites

```bash
brew install cirruslabs/cli/tart         # VM runner
brew install packer                      # Image builder (one-time VM build only)
brew install hudochenkov/sshpass/sshpass # Non-interactive SSH
```

---

## Quick Start

### 1. Build the VM image (one-time, ~20-30 min)

```bash
cd vm/packer
packer init windowthing-test.pkr.hcl
packer build windowthing-test.pkr.hcl
```

This creates a local VM named `windowthing-test` with:
- macOS Sequoia + Xcode Command Line Tools (Swift 6.x)
- Accessibility TCC pre-granted for `/usr/bin/swift` and Terminal
- Sleep and Spotlight disabled for build performance

### 2. Run the tests

```bash
# All tests (unit + integration)
./vm/run-tests.sh

# Integration tests only
./vm/run-tests.sh --integration-only

# Multi-monitor layout tests (spins up a virtual 1920x1080 second display)
./vm/run-tests.sh --dual-display

# Keep the VM alive after tests for manual debugging
./vm/run-tests.sh --keep
```

`run-tests.sh` sequence:
1. Starts the VM headlessly (`tart run --no-graphics`)
2. rsyncs source to the VM (excludes `.build`, `.git`)
3. Runs `swift build --build-tests`
4. Grants Accessibility TCC to `/usr/bin/swift` and the compiled test bundle
5. (Optionally) starts a virtual second display via `CGVirtualDisplay`
6. Runs `swift test`
7. Stops the VM unless `--keep`

---

## UI Screenshots

```bash
./vm/capture-screenshots.sh                    # all scenes
./vm/capture-screenshots.sh --scene space      # just one
./vm/capture-screenshots.sh --dual-display     # two screens, one shot each
./vm/capture-screenshots.sh --skip-build       # reuse the VM's existing build
./vm/capture-screenshots.sh --keep             # leave the VM up afterwards
```

Output lands in `vm/screenshots/<scene>.png` at 3840x2400 (1920x1200 HiDPI).
Scenes: `space`, `quickmove`, `onboarding`, `settings`.

`space` is the activation surface — the window browser and the layout editor are
one screen now, so there is no separate editor scene. `overlay` is still accepted
as an alias for it so older invocations keep working.

With `--dual-display` a virtual second screen is added first (the same
`CGVirtualDisplay` helper `run-tests.sh --dual-display` uses) and each scene is
captured once per screen, as `<scene>-display1.png` and `<scene>-display2.png`.
That is the only way to check the per-screen overlays, since the surface puts a
separate window on every display.

The VM has a virtual WindowServer, so the app renders and `screencapture` works
even under `tart run --no-graphics`. Each scene is opened by launching the app
with `--screenshot <scene>`, which presents that screen 1.5s after launch and
suppresses first-run onboarding so it can't cover the requested scene.

To watch or click through anything by hand, start the VM with its display
attached first, then capture against the running VM:

```bash
tart run windowthing-test &                    # opens a VM window
./vm/capture-screenshots.sh --keep
```

## Interface tests

```sh
./vm/run-tests.sh --ui        # unit suite, then the interface
./vm/run-tests.sh --ui-only   # only the interface
```

Inside the VM, one file at a time:

```sh
~/Projects/window_thing/vm/scripts/ui-test.sh              # everything
~/Projects/window_thing/vm/scripts/ui-test.sh 03-panes     # one file
```

They run there rather than on a developer's machine because they open windows,
take focus and click things — on your own Mac they take over the screen while
they work.

```
vm/scripts/
├── ui-test.sh          runner: builds the bundle, isolates the config, runs the files
├── ui-lib.sh           assertions, app lifecycle, shared setup
├── ax-driver.swift     reads and drives the interface through Accessibility
└── ui-tests/
    ├── 01-surface.sh      opening, closing, reopening, escape
    ├── 02-layouts.sh      add, rename, delete with confirmation, cancel
    ├── 03-panes.sh        splitting, pane type, removal, the stack's exception
    ├── 04-keyboard.sh     text vs shortcuts, what each escape dismisses
    ├── 05-chooser.sh      the window chooser and its search
    └── 06-onboarding.sh   the first-run flow
```

### What belongs here

Behaviour that exists **only in the interface**: focus, keyboard interception,
dialogs, what a control is called. Layout arithmetic, window matching, exclusions
and the view model are covered far more cheaply and thoroughly by `swift test` —
duplicating that here would only make this slower and more brittle.

The delete confirmation is the clearest example. It exists to sit between a click
and the model, so a test that calls the model proves nothing about it.

### Not covered

- **Dragging**: resizing a pane by its divider, and dragging a pane to rearrange
  it. Both need synthesised mouse drags rather than a control to press.
- **Multi-monitor**: the surface puts a window on every display. Would need
  `--dual-display` and per-screen assertions.
- **The menubar**: status items live in the system's menu bar extras, not in the
  app's own Accessibility tree, so the driver cannot reach them.
- **Applying a layout to real windows**: covered by the integration suite, which
  moves actual windows and checks where they land.
- **Settings, quick move, the cell picker, Sparkle's update flow.**

### How it drives the app

Through the Accessibility API, not System Events, which could not see the layout
surface reliably: the window sits at the screen-saver level and came and went
between calls.

The driver is compiled once to `build/ax-driver` and run as a binary. It used to
be run as `swift ax-driver.swift` on the theory that only `/usr/bin/swift` held
the Accessibility grant, so a compiled copy would be a different client with no
permission. That was wrong: TCC grants are rows keyed on an absolute path, and
`grant-tcc-access.sh` authorises the driver's path the same way it authorises
`/usr/bin/swift`. Running it as a script re-compiled it on every call — 0.6s
against 0.03s, across more than a hundred calls a run.

Three things that took some finding, recorded so they don't have to be found
again:

- The app is launched with `open`, not by running its executable. Launching it
  directly leaves LaunchServices unaware it handles `com.windowthing.app`, and
  Apple events time out — which reads as missing Automation consent. `open` is
  also retried: for a moment after the app quits LaunchServices still thinks it
  is running and refuses with `-600`, starting nothing at all.
- Automation consent is checked against the *responsible* process, not the one
  that sends the event. Over SSH that is `sshd-keygen-wrapper`, so granting only
  `/usr/bin/osascript` leaves the real client denied — and it fails silently,
  with the test taking whatever fallback it has and appearing to pass.
- The assertions poll rather than sleeping. A fixed sleep is paid on every run
  whether it was needed or not, and is still occasionally too short.
- Setting a SwiftUI text field's accessibility *value* does not write through to
  its binding. The driver types real keystrokes, and focuses the field first:
  the surface deliberately does not reclaim key focus, so its field can be on
  screen and not first responder, with keystrokes going nowhere silently.
- The UI phase runs under `launchctl asuser … sudo -u`. `asuser` alone runs as
  root, which built the project as root and left hundreds of root-owned files in
  `.build` that no later build could overwrite.

**Toolchain note**: the VM ships Xcode 16.4 (macOS 15 SDK) while a current
developer machine has Xcode 26. Anything from a newer SDK — `glassEffect()`,
for instance — must sit behind `#if compiler(>=6.2)` or the VM will fail to
build the app target. The VM therefore renders the pre-macOS-26 fallback path,
not Liquid Glass.

---

## Accessibility TCC Permissions

macOS requires explicit permission for any process that reads or moves windows via the Accessibility API.

**Why direct TCC.db writes work here**: Cirruslabs base images ship with SIP disabled, allowing writes to `TCC.db` without a user prompt or MDM profile.

**Two-phase grant** (automatic):
1. **Image build time** — `/usr/bin/swift` and Terminal are granted in the image.
2. **Run time** — After building, `grant-tcc-access.sh` also grants the compiled `.xctest` bundle binary.

**Manual re-grant** (if needed):
```bash
sshpass -p admin ssh admin@$(tart ip windowthing-test)
bash ~/Projects/window_thing/vm/scripts/grant-tcc-access.sh ~/Projects/window_thing
```

---

## Virtual Second Display

`./vm/run-tests.sh --dual-display` launches `vm/scripts/create-virtual-display.swift` inside the VM. This uses the `CGVirtualDisplay` API (macOS 13+, no third-party tools or licenses) to add a software-only 1920x1080 display for the duration of the test run.

---

## Manual VM Usage

```bash
tart list
tart run windowthing-test                       # with GUI (debugging)
tart run windowthing-test --no-graphics &       # headless
tart ip windowthing-test                        # get IP
sshpass -p admin ssh admin@$(tart ip windowthing-test)
tart stop windowthing-test
```

---

## Directory Structure

```
vm/
├── README.md
├── run-tests.sh                  # Main test runner
├── capture-screenshots.sh        # UI screenshot capture
├── screenshots/                  # Captured PNGs (output)
├── scripts/
│   ├── grant-tcc-access.sh       # TCC Accessibility grant script (run inside VM)
│   ├── set-display-mode.swift    # Sets the guest's display resolution
│   └── create-virtual-display.swift  # CGVirtualDisplay second-monitor helper
└── packer/
    ├── windowthing-test.pkr.hcl  # Packer template
    └── scripts/
        └── setup.sh              # VM provisioning
```

---

## Troubleshooting

**SSH timeout** — VM takes 60-90 s to boot. `run-tests.sh` waits up to 90 s. If still failing, try `tart run windowthing-test` with GUI to confirm the VM is healthy.

**Integration tests skip** — If the tests print "Accessibility permissions not granted", the TCC grant didn't take effect. SSH in and re-run `grant-tcc-access.sh` manually, then re-run the tests.

**Rebuild the image**:
```bash
tart delete windowthing-test
cd vm/packer && packer build windowthing-test.pkr.hcl
```
