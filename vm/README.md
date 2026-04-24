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
├── scripts/
│   ├── grant-tcc-access.sh       # TCC Accessibility grant script (run inside VM)
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
