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
./vm/run-tests.sh --ui        # unit suite, then drive the interface
./vm/run-tests.sh --ui-only   # only the interface tests
```

`vm/scripts/ui-test.sh` runs inside the VM and exercises the layout lifecycle:
create one, rename it, cancel a delete, then confirm one. It runs there rather
than on a developer's machine because it opens windows, takes focus and clicks
things — on your own Mac it takes over the screen while it works.

It drives the app through the Accessibility API (`vm/scripts/ax-driver.swift`)
rather than System Events, which could not see the layout surface reliably: the
window sits at the screen-saver level and came and went between calls. The VM
already grants `/usr/bin/swift` Accessibility, so a script run that way needs no
further approval.

The rename step uses the AppleScript interface and needs Automation consent for
`osascript` → `com.windowthing.app`; `grant-tcc-access.sh` inserts it. Without
it that one step reports as skipped and the rest still runs.

The delete confirmation is the part that can only be checked this way. It exists
to sit between a click and the model, so a test calling the model directly
proves nothing about it.

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
