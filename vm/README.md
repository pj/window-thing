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
packer init macos-dev.pkr.hcl
packer build macos-dev.pkr.hcl
```

This creates a local VM named `macos-dev` with:

The name is deliberately not project-specific: one VM is shared across projects,
each syncing into its own `~/Projects/<name>`. Point another project at it by
setting `VM_NAME`, or copy `vm/` across unchanged — the scripts derive both the
VM name and the remote directory rather than hard-coding this project.

- macOS Tahoe (26.x) + full Xcode
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
1. Builds and signs `WindowThing.app` and `ax-driver` **on the host**
2. Starts the VM headlessly (`tart run --no-graphics`)
3. rsyncs source to the VM (excludes `.build`, `.git`, `build`)
4. Copies the two built artifacts into the VM's `build/`
5. Writes the TCC rows it still can (Apple events, user-level)
6. (Optionally) starts a virtual second display via `CGVirtualDisplay`
7. Runs the unit suites **on the host**, skipping the window-moving ones
8. Runs the interface tests in the VM
9. Stops the VM unless `--keep`

### Nothing is built inside the VM

The image carries no Swift toolchain — no Xcode, no Command Line Tools — so
everything is compiled on the host and copied in. The VM is a place to run a
GUI, not a build machine. This is also faster: the guest build used to be the
slowest part of a run.

Two consequences:

- **`swift test` cannot run in the VM.** The pure suites run on the host
  instead, with `IntegrationTests` and `PrimaryDisplayLayoutTests` skipped —
  those move real windows and should not take over a developer's screen.
- **`--integration-only` is unavailable.** Those suites need both a toolchain
  and this VM. `xcode-select --install` inside the VM brings them back.

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
tart run macos-dev &                    # opens a VM window
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

**Toolchain note**: there is no toolchain in the VM at all, so the app it runs
is built against whatever SDK the host has. The old note here warned that the
VM's older Xcode would fail on newer SDK symbols; that no longer applies, since
nothing is compiled there.

---

## Accessibility TCC Permissions

macOS requires explicit permission for any process that reads or moves windows via the Accessibility API.

**Accessibility must be approved by hand on the current image.** Writing
Accessibility grants directly into the system `TCC.db` needs SIP off; this image
has SIP on, so the file is read-only even to root and the script cannot grant
it. `run-tests.sh` checks before running and prints what to switch on rather
than letting every assertion fail on a timeout.

Approve once, on the VM's screen, under **System Settings > Privacy & Security >
Accessibility**: `WindowThing` and `ax-driver`. An entry showing `auth_value 0`
is listed but refused — switch it on rather than adding it again.

It only needs doing once. Both are signed with a Developer ID on the host, so
they keep one identity across rebuilds; an ad-hoc signature would be a new
identity every build and the approval would lapse immediately.

The other grants — Apple events, and the user-level rows — are still written by
`grant-tcc-access.sh`, because those databases are writable.

**Two-phase grant** (automatic):
1. **Image build time** — `/usr/bin/swift` and Terminal are granted in the image.
2. **Run time** — After building, `grant-tcc-access.sh` also grants the compiled `.xctest` bundle binary.

**Manual re-grant** (if needed):
```bash
sshpass -p admin ssh admin@$(tart ip macos-dev)
bash ~/Projects/window_thing/vm/scripts/grant-tcc-access.sh ~/Projects/window_thing
```

---

## Virtual Second Display

`./vm/run-tests.sh --dual-display` launches `vm/scripts/create-virtual-display.swift` inside the VM. This uses the `CGVirtualDisplay` API (macOS 13+, no third-party tools or licenses) to add a software-only 1920x1080 display for the duration of the test run.

---

## Manual VM Usage

```bash
tart list
tart run macos-dev                       # with GUI (debugging)
tart run macos-dev --no-graphics &       # headless
tart ip macos-dev                        # get IP
sshpass -p admin ssh admin@$(tart ip macos-dev)
tart stop macos-dev
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
    ├── macos-dev.pkr.hcl        # Packer template
    └── scripts/
        └── setup.sh              # VM provisioning
```

---

## Troubleshooting

**SSH timeout** — VM takes 60-90 s to boot. `run-tests.sh` waits up to 90 s. If still failing, try `tart run macos-dev` with GUI to confirm the VM is healthy.

**Integration tests skip** — If the tests print "Accessibility permissions not granted", the TCC grant didn't take effect. SSH in and re-run `grant-tcc-access.sh` manually, then re-run the tests.

**Rebuild the image**:
```bash
tart delete macos-dev
cd vm/packer && packer build macos-dev.pkr.hcl
```
