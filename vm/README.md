# WindowThing VM Testing Infrastructure

This directory contains infrastructure for running integration tests in a macOS VM using [Tart](https://tart.run/).

## Prerequisites

```bash
# Install Tart
brew install cirruslabs/cli/tart

# Install Packer
brew install packer

# Install sshpass (for automated SSH)
brew install hudochenkov/sshpass/sshpass
```

## Quick Start

### 1. Build the VM Image (one-time, ~30 mins)

```bash
cd vm/packer

# Initialize Packer plugins
packer init windowthing-test.pkr.hcl

# Build the VM image
packer build windowthing-test.pkr.hcl
```

This creates a VM named `windowthing-test` with:
- macOS Sequoia + Xcode
- BetterDisplay for virtual monitors
- Helper scripts for testing

### 2. Run Tests

```bash
# Run all tests in a fresh VM clone
./vm/run-tests.sh

# Run specific test suite
./vm/run-tests.sh --filter IntegrationTests

# Keep VM running after tests (for debugging)
./vm/run-tests.sh --keep
```

## Manual VM Usage

```bash
# List available VMs
tart list

# Start VM with GUI
tart run windowthing-test

# Start VM headless
tart run windowthing-test --no-graphics

# Get VM IP address
tart ip windowthing-test

# SSH into VM (password: admin)
ssh admin@$(tart ip windowthing-test)

# Stop VM
tart stop windowthing-test

# Clone for testing (preserves base image)
tart clone windowthing-test my-test-run
```

## Multi-Monitor Testing

The VM includes BetterDisplay for creating virtual monitors:

```bash
# SSH into the VM
ssh admin@$(tart ip windowthing-test)

# Create a virtual display
~/Projects/windowthing-helpers/setup-virtual-displays.sh

# Or manually with BetterDisplay CLI
betterdisplaycli create \
    -devicetype=virtualscreen \
    -virtualscreenname="Virtual Monitor 2" \
    -aspectWidth=16 \
    -aspectHeight=9
```

## Accessibility Permissions

WindowThing requires Accessibility permissions. In the VM:

1. Open System Settings > Privacy & Security > Accessibility
2. Add Terminal (for running tests via SSH)
3. Add WindowThing (after first build)

For automated CI, you'd need to deploy a TCC profile via MDM.

## Creating Test Windows

A helper script creates test windows for integration tests:

```bash
# In the VM
swift ~/Projects/windowthing-helpers/create-test-windows.swift
```

## Troubleshooting

### VM won't start
```bash
# Check if another instance is running
tart list
tart stop windowthing-test

# Delete and rebuild
tart delete windowthing-test
cd vm/packer && packer build windowthing-test.pkr.hcl
```

### SSH connection refused
- Wait 30-60 seconds after VM starts
- Ensure VM has booted fully: `tart run windowthing-test` (with GUI)

### Tests fail with accessibility errors
- Grant permissions manually in System Settings
- Ensure WindowThing binary has been run once with GUI

## Directory Structure

```
vm/
├── README.md                 # This file
├── run-tests.sh             # Test runner script
└── packer/
    ├── windowthing-test.pkr.hcl  # Packer template
    └── scripts/
        └── setup.sh         # VM setup script
```

## CI Integration

For GitHub Actions or other CI:

```yaml
jobs:
  integration-tests:
    runs-on: macos-14  # Apple Silicon
    steps:
      - uses: actions/checkout@v4

      - name: Install Tart
        run: brew install cirruslabs/cli/tart

      - name: Pull VM image
        run: tart clone ghcr.io/your-org/windowthing-test:latest test-vm

      - name: Run tests
        run: ./vm/run-tests.sh
```
