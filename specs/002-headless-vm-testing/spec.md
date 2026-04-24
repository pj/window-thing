# Feature Specification: Headless VM Testing Environment

**Feature Branch**: `002-headless-vm-testing`  
**Created**: 2026-04-21  
**Status**: Draft  
**Input**: User description: "What are the options for running this in a VM and running the code on the VM in a headless way i.e. don't start the GUI, but test all the functionality in an actual environment."

## Context

WindowThing is a macOS menubar app that depends on system APIs not easily mocked: the Accessibility API (to enumerate and reposition real windows), the display enumeration API (to detect connected monitors), and optionally the Screen Recording API (for thumbnails). The existing `swift test` suite covers pure-logic targets in isolation. This feature addresses the gap between unit tests and a full integration test that exercises real system APIs in a reproducible, automated environment — without requiring a physical display or an interactive desktop session.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run Full Integration Tests in CI (Priority: P1)

A developer triggers the test pipeline (locally or in CI) and the suite runs against the real macOS Accessibility API, real display enumeration, and real window-frame setting — without a human sitting at a physical monitor.

**Why this priority**: Closes the gap between fast unit tests and the kind of bugs that only appear when real OS APIs are exercised. P1 because it directly answers the user's question and unblocks reproducible automated testing.

**Independent Test**: Can be fully tested by running the test suite in a macOS VM with SSH access and no attached display, and verifying that accessibility-API-dependent tests produce results (pass or fail with real AX errors, not mock stubs).

**Acceptance Scenarios**:

1. **Given** a macOS VM with SSH access and no physical display attached, **When** the test command is run over SSH, **Then** the Core logic tests and Accessibility API integration tests all execute and produce a result (pass/fail) without requiring a logged-in GUI session visible on a monitor.
2. **Given** a CI runner (e.g. GitHub Actions macOS runner or self-hosted VM), **When** the build-and-test pipeline runs, **Then** all existing tests pass and any new integration tests that call AX APIs also pass.
3. **Given** no Screen Recording permission is granted in the VM, **When** the thumbnail tests run, **Then** they degrade gracefully and do not fail the suite.

---

### User Story 2 - Test Window Layout Application Against Real APIs (Priority: P2)

A developer wants to verify that applying a layout actually moves real (or virtual) windows to the correct frames, using the real Accessibility API, with at least one virtual display available.

**Why this priority**: Layout application is the core value of the app. Testing it end-to-end against real APIs catches issues invisible to unit tests — AX permission errors, coordinate-system differences between virtual and physical displays, multi-display edge cases.

**Independent Test**: Can be tested by launching a known test window (e.g. a minimal AppKit window spawned by a test helper), applying a layout, and asserting the window's actual frame via the AX API matches the expected frame.

**Acceptance Scenarios**:

1. **Given** a macOS environment with at least one display (physical or virtual), **When** a layout is applied to a test window, **Then** the window's frame as reported by the AX API matches the expected frame from the layout calculation.
2. **Given** a two-display virtual configuration, **When** a multi-screen layout is applied, **Then** windows are placed on the correct display.
3. **Given** the focused application changes, **When** a cell movement command fires, **Then** the correct window moves to the target cell.

---

### User Story 3 - Reproduce Display Detection Scenarios in a Clean Environment (Priority: P3)

A developer wants to test how the app behaves when displays are added, removed, or renamed — without rearranging physical hardware.

**Why this priority**: Display topology changes are a common source of layout breakage in the field. A VM with configurable virtual displays lets developers reproduce and regression-test these scenarios reliably.

**Independent Test**: Can be tested by adding and removing virtual displays in the VM and asserting that display registry records the correct names and that screen-set matching selects the right config.

**Acceptance Scenarios**:

1. **Given** a VM with two virtual displays, **When** one is removed, **Then** the app falls back to the primary-display screen config without crashing.
2. **Given** a VM with a display name not previously seen, **When** the app starts, **Then** the display registry records the new name.
3. **Given** display parameters change mid-session, **When** the display-change notification fires, **Then** layout reconciliation runs and the layout remains consistent.

---

### Edge Cases

- What happens if the macOS VM does not grant Accessibility permission automatically? Most VMs require this to be pre-configured before running tests — undocumented setup will cause silent failures.
- How does the app behave if no WindowServer is running? Some headless macOS setups lack a WindowServer entirely; AX API calls will fail with a specific error that should be surfaced clearly.
- What if the virtual display resolution does not match any saved screen config? Should fall back to the primary-display layout.
- How are hotkey registrations verified headlessly? Carbon-level hotkeys require a running event loop; a test harness may need to verify registration state rather than simulate keystrokes.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The test environment MUST be able to run the full test suite via SSH or non-interactive shell without requiring a GUI desktop session visible on a physical display.
- **FR-002**: The environment MUST provide at least one virtual or software-only display so that display-enumeration APIs return a non-empty display list.
- **FR-003**: The test environment MUST have Accessibility permissions pre-granted to the test process so that AX API calls succeed without a user prompt.
- **FR-004**: Integration tests MUST be able to create and move real AppKit windows to verify layout application end-to-end.
- **FR-005**: The CI/VM setup MUST be reproducible from a documented configuration so any developer can recreate it from scratch.
- **FR-006**: The test run MUST produce a clear pass/fail exit code suitable for CI automation.
- **FR-007**: The environment MUST degrade gracefully when Screen Recording permission is absent — thumbnail-related tests MUST skip or assert degraded behavior rather than hard-fail the suite.
- **FR-008**: The documentation MUST describe the three primary environment options (see Assumptions) and their trade-offs so a developer can choose without additional research.

### Key Entities

- **Virtual Display**: A software-only display recognized by macOS display APIs, not backed by physical hardware. Needed for display-enumeration and multi-monitor tests.
- **Accessibility Permission Grant**: A pre-configured system privacy database entry or management profile that allows the test process to use the AX API without an interactive prompt.
- **Integration Test Harness**: A thin executable or test target that spawns real AppKit windows and invokes layout application and window movement against those windows.
- **CI Runner**: A macOS machine (cloud-hosted or self-hosted VM) capable of running Swift builds and tests non-interactively.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All existing tests continue to pass in the VM environment, and at least 5 new integration tests that call real AX APIs also pass.
- **SC-002**: A developer with no prior VM setup can bring up the test environment and get a green test run within 30 minutes using only the documented configuration.
- **SC-003**: The CI pipeline produces a definitive pass/fail result with no flaky failures attributable to missing display or permission setup.
- **SC-004**: For every layout application test case, the measured window frame (via AX API) differs from the expected frame by no more than 1 point in any dimension.
- **SC-005**: The three environment options are each documented with enough detail that a developer can evaluate trade-offs without consulting external sources.

---

## Assumptions

- Target macOS version is 13+ (Ventura), consistent with the rest of the project.
- The three primary options under evaluation are: (A) a cloud-hosted macOS CI runner such as GitHub Actions `macos-latest`, (B) a local macOS VM using Apple-supported virtualization on Apple Silicon, and (C) a remote bare-metal Mac accessible via SSH with display output suppressed by a virtual display adapter.
- Option A already has a virtual WindowServer and can run AppKit tests; the main gap is pre-granting Accessibility permission, which requires either MDM-level configuration or direct privacy database manipulation.
- Option B requires macOS 13+ as a guest on Apple Silicon and supports virtual display creation; this is the most isolated option but adds VM management overhead.
- Option C is the simplest to configure for permissions but depends on always-on hardware and a physical or electronic virtual-display dongle.
- True "no WindowServer at all" headless mode is not supported by macOS for apps that use AppKit or AX APIs; the spec assumes at minimum a background session with a virtual display.
- Hotkey simulation (synthesizing Carbon key events) is out of scope; verifying hotkey registration state is in scope.
- Changes to production app code to improve testability (e.g. dependency injection already in place) are in scope; changes to end-user OS security policy are out of scope.
