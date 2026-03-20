#!/bin/bash
set -euo pipefail

# Configuration
VM_NAME="windowthing-test"
SSH_USER="admin"
SSH_PASS="admin"
SSH_TIMEOUT=60
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if Tart is installed
check_tart() {
    if ! command -v tart &> /dev/null; then
        log_error "Tart is not installed. Install with: brew install cirruslabs/cli/tart"
        exit 1
    fi
}

# Check if VM exists
check_vm() {
    if ! tart list | grep -q "${VM_NAME}"; then
        log_error "VM '${VM_NAME}' not found."
        log_info "Build it first with: cd vm/packer && packer build windowthing-test.pkr.hcl"
        exit 1
    fi
}

# Check if VM is already running
is_vm_running() {
    tart list | grep "${VM_NAME}" | grep -q "running"
}

# Wait for SSH to be available
wait_for_ssh() {
    local ip=$1
    local timeout=$SSH_TIMEOUT
    local elapsed=0

    log_info "Waiting for SSH on $ip..."
    while ! nc -z "$ip" 22 2>/dev/null; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [ $elapsed -ge $timeout ]; then
            log_error "SSH timeout after ${timeout}s"
            return 1
        fi
    done
    log_info "SSH is available"
    sleep 2  # Give sshd a moment to fully start
}

# Get VM IP address
get_vm_ip() {
    tart ip "$VM_NAME" 2>/dev/null || echo ""
}

# Run command via SSH
ssh_run() {
    local ip=$1
    shift
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${SSH_USER}@${ip}" "$@"
}

# Cleanup function - just stop VM, don't delete
cleanup() {
    log_info "Stopping VM..."
    tart stop "$VM_NAME" 2>/dev/null || true
}

# Main test execution
run_tests() {
    local keep_vm=false
    local test_filter=""
    local skip_unit=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep)
                keep_vm=true
                shift
                ;;
            --filter)
                test_filter="$2"
                shift 2
                ;;
            --integration-only)
                test_filter="PrimaryDisplayLayoutTests"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: $0 [--keep] [--filter <test-name>] [--integration-only]"
                exit 1
                ;;
        esac
    done

    check_tart
    check_vm

    # Set up cleanup trap
    if [ "$keep_vm" = false ]; then
        trap cleanup EXIT
    fi

    # Start VM if not running
    if is_vm_running; then
        log_info "VM already running"
    else
        log_info "Starting VM..."
        tart run "$VM_NAME" --no-graphics &
        sleep 5
    fi

    # Get IP and wait for SSH
    local ip=""
    for i in {1..30}; do
        ip=$(get_vm_ip)
        if [ -n "$ip" ]; then
            break
        fi
        sleep 2
    done

    if [ -z "$ip" ]; then
        log_error "Could not get VM IP address"
        exit 1
    fi

    log_info "VM IP: $ip"
    wait_for_ssh "$ip"

    # Sync project to VM using rsync (faster than scp, incremental)
    log_info "Syncing project to VM..."
    ssh_run "$ip" "mkdir -p ~/Projects/window_thing"
    sshpass -p "$SSH_PASS" rsync -az --delete \
        --exclude '.build' --exclude '.git' --exclude 'vm' \
        -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
        "$PROJECT_DIR/" "${SSH_USER}@${ip}:~/Projects/window_thing/"

    # Build project in VM
    log_info "Building project in VM..."
    ssh_run "$ip" "cd ~/Projects/window_thing && swift build 2>&1" || {
        log_error "Build failed"
        exit 1
    }

    # Run tests
    log_info "Running tests..."
    local test_cmd="cd ~/Projects/window_thing && swift test"
    if [ -n "$test_filter" ]; then
        test_cmd="$test_cmd --filter '$test_filter'"
    fi

    if ssh_run "$ip" "$test_cmd 2>&1"; then
        log_info "All tests passed!"
        exit_code=0
    else
        log_error "Some tests failed"
        exit_code=1
    fi

    if [ "$keep_vm" = true ]; then
        log_info "VM kept running at $ip (--keep flag)"
        log_info "SSH: sshpass -p '$SSH_PASS' ssh ${SSH_USER}@${ip}"
        log_info "Stop with: tart stop $VM_NAME"
        trap - EXIT  # Remove cleanup trap
    fi

    return $exit_code
}

# Run with arguments
run_tests "$@"
