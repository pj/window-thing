#!/bin/bash
set -euo pipefail

# Configuration
# One VM, shared across projects. Override to point at another.
VM_NAME="${VM_NAME:-macos-dev}"
SSH_USER="admin"
SSH_PASS="admin"
SSH_TIMEOUT=90
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Named after this project, so a shared VM can hold several side by side.
REMOTE_DIR="~/Projects/$(basename "$PROJECT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --------------------------------------------------------------------------- #
# Prerequisites                                                                 #
# --------------------------------------------------------------------------- #

check_tart() {
    if ! command -v tart &> /dev/null; then
        log_error "Tart is not installed.  Install with: brew install cirruslabs/cli/tart"
        exit 1
    fi
}

check_vm() {
    if ! tart list | grep -q "^local.*${VM_NAME}"; then
        log_error "VM '${VM_NAME}' not found."
        log_info  "Build it first with: cd vm/packer && packer build macos-dev.pkr.hcl"
        exit 1
    fi
}

check_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is not installed.  Install with: brew install hudochenkov/sshpass/sshpass"
        exit 1
    fi
}

# --------------------------------------------------------------------------- #
# VM control                                                                    #
# --------------------------------------------------------------------------- #

is_vm_running() {
    tart list | grep "^local.*${VM_NAME}" | grep -q "running"
}

get_vm_ip() {
    tart ip "$VM_NAME" 2>/dev/null || echo ""
}

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
    log_info "SSH available"
    sleep 2  # Let sshd fully initialise
    ensure_ssh_auth "$ip"
}

cleanup() {
    log_info "Stopping VM..."
    tart stop "$VM_NAME" 2>/dev/null || true
}

# --------------------------------------------------------------------------- #
# SSH helpers                                                                   #
# --------------------------------------------------------------------------- #

SSH_BASE="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# Password auth until a key is installed; see ensure_ssh_auth.
SSH_OPTS="$SSH_BASE -o IdentitiesOnly=yes -o PubkeyAuthentication=no"
SSH_MODE="password"

# Switch to key authentication, installing the key first if need be.
#
# macOS's sshd rejects correct passwords intermittently under the rapid
# connection rate this harness works at — measured at 3 failures in 25 on a
# macOS 26 guest, which across the ~20 connections of a run makes a spurious
# failure more likely than not. It surfaces as "Permission denied, please try
# again" followed by "Too many authentication failures", which reads as a wrong
# password rather than as flakiness. Key auth does not go through that path.
#
# The password is still how the key gets in, so that one connection retries.
ensure_ssh_auth() {
    local ip=$1

    key_auth_works() {
        [ -f "$SSH_KEY" ] && ssh $SSH_BASE -i "$SSH_KEY" -o IdentitiesOnly=yes \
            -o PasswordAuthentication=no -o BatchMode=yes \
            "${SSH_USER}@${ip}" true 2>/dev/null
    }

    if key_auth_works; then
        SSH_OPTS="$SSH_BASE -i $SSH_KEY -o IdentitiesOnly=yes -o PasswordAuthentication=no"
        SSH_MODE="key"
        return 0
    fi

    if [ ! -f "${SSH_KEY}.pub" ]; then
        log_warn "no key at ${SSH_KEY}.pub — staying on password auth, which flakes"
        return 0
    fi

    log_info "Installing SSH key in the VM (one time)"
    local pub attempt
    pub="$(cat "${SSH_KEY}.pub")"
    for attempt in 1 2 3 4 5; do
        if sshpass -p "$SSH_PASS" ssh $SSH_OPTS "${SSH_USER}@${ip}" \
             "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
              grep -qxF '$pub' ~/.ssh/authorized_keys 2>/dev/null || echo '$pub' >> ~/.ssh/authorized_keys; \
              chmod 600 ~/.ssh/authorized_keys" 2>/dev/null; then
            break
        fi
        sleep 2
    done

    if key_auth_works; then
        SSH_OPTS="$SSH_BASE -i $SSH_KEY -o IdentitiesOnly=yes -o PasswordAuthentication=no"
        SSH_MODE="key"
        log_info "SSH key authentication active"
    else
        log_warn "could not install an SSH key — staying on password auth"
    fi
}

# Retries only transport failures, never the remote command's own exit status:
# ssh reports its own errors as 255, and sshpass reports a rejected password as
# 5. Retrying anything else would silently re-run a failing build.
ssh_run() {
    local ip=$1
    shift
    local attempt rc
    for attempt in 1 2 3 4 5; do
        if [ "$SSH_MODE" = "key" ]; then
            ssh $SSH_OPTS "${SSH_USER}@${ip}" "$@"
            rc=$?
            [ "$rc" -ne 255 ] && return "$rc"
        else
            sshpass -p "$SSH_PASS" ssh $SSH_OPTS "${SSH_USER}@${ip}" "$@"
            rc=$?
            [ "$rc" -ne 255 ] && [ "$rc" -ne 5 ] && return "$rc"
        fi
        sleep 2
    done
    return "$rc"
}

# vm/ is excluded from the project sync, so the interface tests are sent
# separately. Same auth mode and retry as rsync_to_vm.
rsync_scripts_to_vm() {
    local ip=$1
    local attempt
    for attempt in 1 2 3; do
        if [ "$SSH_MODE" = "key" ]; then
            rsync -az -e "ssh $SSH_OPTS" \
                "$PROJECT_DIR/vm/scripts/" "${SSH_USER}@${ip}:$REMOTE_DIR/vm/scripts/" && return 0
        else
            sshpass -p "$SSH_PASS" rsync -az -e "ssh $SSH_OPTS" \
                "$PROJECT_DIR/vm/scripts/" "${SSH_USER}@${ip}:$REMOTE_DIR/vm/scripts/" && return 0
        fi
        sleep 2
    done
    return 1
}

ssh_run_bg() {
    local ip=$1
    shift
    if [ "$SSH_MODE" = "key" ]; then
        ssh $SSH_OPTS "${SSH_USER}@${ip}" "nohup $* </dev/null >/tmp/bg.log 2>&1 & echo \$!"
    else
        sshpass -p "$SSH_PASS" ssh $SSH_OPTS \
            "${SSH_USER}@${ip}" "nohup $* </dev/null >/tmp/bg.log 2>&1 & echo \$!"
    fi
}

rsync_to_vm() {
    local ip=$1
    local src=$2
    local dst=$3
    local attempt
    for attempt in 1 2 3; do
        if [ "$SSH_MODE" = "key" ]; then
            rsync -az --delete \
                --exclude '.build' --exclude '.git' --exclude 'vm' --exclude 'build' \
                -e "ssh $SSH_OPTS" "$src" "${SSH_USER}@${ip}:${dst}" && return 0
        else
            sshpass -p "$SSH_PASS" rsync -az --delete \
                --exclude '.build' --exclude '.git' --exclude 'vm' --exclude 'build' \
                -e "ssh $SSH_OPTS" "$src" "${SSH_USER}@${ip}:${dst}" && return 0
        fi
        sleep 2
    done
    return 1
}

# --------------------------------------------------------------------------- #
# TCC / Accessibility                                                           #
# --------------------------------------------------------------------------- #

# Grant Accessibility TCC permissions inside the VM.
# Cirruslabs base images ship with SIP disabled so we can write to TCC.db.
# Two-pass: build first so the test bundle path is known, then grant access
# to both /usr/bin/swift and the compiled test binary.
grant_tcc_access() {
    local ip=$1
    local proj="$REMOTE_DIR"

    log_info "Granting Accessibility TCC permissions..."

    # Upload and run the grant script
    rsync_to_vm "$ip" "$PROJECT_DIR/vm/scripts/grant-tcc-access.sh" "/tmp/grant-tcc-access.sh"
    ssh_run "$ip" "bash /tmp/grant-tcc-access.sh $proj" || \
        log_warn "TCC grant had warnings — integration tests may be skipped"
}

# --------------------------------------------------------------------------- #
# Virtual second display (optional)                                             #
# --------------------------------------------------------------------------- #

start_virtual_display() {
    local ip=$1
    log_info "Starting virtual second display (1920x1080)..."

    # Upload the helper script
    rsync_to_vm "$ip" "$PROJECT_DIR/vm/scripts/create-virtual-display.swift" \
        "/tmp/create-virtual-display.swift"

    # Launch in background; the display persists until the script exits
    ssh_run "$ip" \
        "nohup swift /tmp/create-virtual-display.swift 1920 1080 60 \
         </dev/null >/tmp/virtual-display.log 2>&1 &" || true

    sleep 3  # Give the display time to register with the WindowServer

    # Confirm it appeared
    local disp_count
    disp_count=$(ssh_run "$ip" \
        "swift -e 'import CoreGraphics; var c = UInt32(0); CGGetActiveDisplayList(32, nil, &c); print(c)'" \
        2>/dev/null || echo "?")
    log_info "Active displays in VM: $disp_count"
}

# --------------------------------------------------------------------------- #
# Main test execution                                                           #
# --------------------------------------------------------------------------- #

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --keep              Keep VM running after tests (for debugging)"
    echo "  --filter NAME       Run only tests matching NAME"
    echo "  --integration-only  Run only PrimaryDisplayLayoutTests"
    echo "  --dual-display      Spin up a virtual second display before testing"
    echo "  --ui                Also drive the interface (add/rename/delete a layout)"
    echo "  --ui-only           Run only the interface tests"
    echo "  --no-tcc            Skip TCC permission setup"
  echo "  --force-tcc         Re-run TCC grants even if already granted (use after VM rebuild)"
    echo ""
}

run_tests() {
    local keep_vm=false
    local test_filter=""
    local dual_display=false
    local skip_tcc=false
    local run_ui=false
    local ui_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep)             keep_vm=true;                       shift ;;
            --filter)           test_filter="$2";                   shift 2 ;;
            --integration-only) test_filter="PrimaryDisplayLayoutTests"; shift ;;
            --dual-display)     dual_display=true;                  shift ;;
            --ui)               run_ui=true;                        shift ;;
            --ui-only)          run_ui=true; ui_only=true;          shift ;;
            --no-tcc)           skip_tcc=true;                      shift ;;
            --force-tcc)        export FORCE_TCC=true;              shift ;;
            --help|-h)          usage; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    check_tart
    check_vm
    check_sshpass

    if [ "$keep_vm" = false ]; then
        trap cleanup EXIT
    fi

    # ------------------------------------------------------------------ #
    # Boot VM                                                               #
    # ------------------------------------------------------------------ #
    if is_vm_running; then
        log_info "VM already running"
    else
        log_info "Starting VM headlessly..."
        tart run "$VM_NAME" --no-graphics &
        sleep 5
    fi

    local ip=""
    for i in {1..30}; do
        ip=$(get_vm_ip)
        [ -n "$ip" ] && break
        sleep 2
    done

    if [ -z "$ip" ]; then
        log_error "Could not get VM IP address"
        exit 1
    fi

    log_info "VM IP: $ip"
    wait_for_ssh "$ip"

    # ------------------------------------------------------------------ #
    # Sync source                                                           #
    # ------------------------------------------------------------------ #
    log_info "Syncing project to VM..."
    ssh_run "$ip" "mkdir -p $REMOTE_DIR"
    rsync_to_vm "$ip" "$PROJECT_DIR/" "$REMOTE_DIR/"

    # ------------------------------------------------------------------ #
    # Build                                                                 #
    # ------------------------------------------------------------------ #
    # Clean any stale build artefacts (e.g. corrupted DB from a prior failed run)
    ssh_run "$ip" "cd $REMOTE_DIR && swift package clean 2>/dev/null || rm -rf .build/build.db" || true

    log_info "Building project in VM..."
    if ! ssh_run "$ip" "cd $REMOTE_DIR && swift build --build-tests 2>&1"; then
        log_error "Build failed"
        exit 1
    fi

    # ------------------------------------------------------------------ #
    # TCC permissions                                                       #
    # Only run TCC grants if the sentinel file is absent. Grants persist   #
    # in the VM's TCC.db between runs; re-running them while the test      #
    # binary starts causes a database lock race that crashes tests.        #
    # Use --force-tcc to re-grant explicitly (e.g. after VM rebuild).     #
    # ------------------------------------------------------------------ #
    if [ "$skip_tcc" = false ]; then
        TCC_SENTINEL_CHECK=$(ssh_run "$ip" "test -f ~/.tcc_granted && echo yes || echo no" 2>/dev/null)
        if [ "$TCC_SENTINEL_CHECK" != "yes" ] || [ "${FORCE_TCC:-false}" = "true" ]; then
            grant_tcc_access "$ip"
            ssh_run "$ip" "touch ~/.tcc_granted" 2>/dev/null || true
        else
            log_info "TCC already granted (use FORCE_TCC=true to re-run)"
        fi
    fi

    # ------------------------------------------------------------------ #
    # Virtual second display (optional)                                    #
    # ------------------------------------------------------------------ #
    if [ "$dual_display" = true ]; then
        start_virtual_display "$ip"
    fi

    # ------------------------------------------------------------------ #
    # Open test windows                                                     #
    # Integration tests need at least one real app window to move.         #
    # Open three TextEdit documents in the user's Quartz session.          #
    # ------------------------------------------------------------------ #
    # Open test windows in the user's Quartz/GUI session.
    # SSH connections don't inherit the Aqua session, so we use
    # `launchctl asuser 501` to inject commands into the logged-in user's
    # session (UID 501 is the default for the first admin user on macOS).
    log_info "Opening test windows in GUI session..."
    ssh_run "$ip" "
        # Open TextEdit with three new windows
        sudo launchctl asuser 501 /usr/bin/open -na TextEdit --args --new-document
        sleep 2
        sudo launchctl asuser 501 /usr/bin/open -na TextEdit --args --new-document
        sleep 2
        sudo launchctl asuser 501 /usr/bin/open -na TextEdit --args --new-document
        sleep 3
    " || log_warn "Could not open test windows — integration tests may skip"

    # ------------------------------------------------------------------ #
    # Run tests                                                             #
    # ------------------------------------------------------------------ #
    log_info "Running tests..."
    # --no-parallel prevents Swift Testing from running test suites concurrently
    # across targets. Without this, global singletons (WindowManager, LayoutManager)
    # get accessed from multiple threads simultaneously, causing intermittent SIGSEGVs.
    local test_cmd="cd $REMOTE_DIR && swift test --no-parallel"
    if [ -n "$test_filter" ]; then
        test_cmd="$test_cmd --filter '$test_filter'"
    fi

    local exit_code=0
    if [ "$ui_only" = true ]; then
        log_info "Skipping the unit suite (--ui-only)"
    elif ssh_run "$ip" "$test_cmd 2>&1"; then
        log_info "All tests passed."
    else
        log_error "Some tests failed."
        exit_code=1
    fi

    # ------------------------------------------------------------------ #
    # Interface tests                                                       #
    # These click things and take focus, which is exactly why they run in  #
    # here rather than on whoever's machine is driving the VM.             #
    # ------------------------------------------------------------------ #
    if [ "$run_ui" = true ]; then
        # The project sync excludes vm/ — the guest has no use for the harness,
        # and vm/screenshots would be pointless traffic. The interface test does
        # live in there, though, so send that directory across on its own.
        log_info "Syncing interface test scripts..."
        ssh_run "$ip" "mkdir -p $REMOTE_DIR/vm/scripts"
        rsync_scripts_to_vm "$ip"

        log_info "Running interface tests..."
        # Two layers here, and both are needed.
        #
        # `launchctl asuser` puts the command in the logged-in user's Aqua
        # session: an SSH session has none of its own, and nothing that draws a
        # window or reads the Accessibility tree works without one.
        #
        # `sudo -u` then drops back to that user. asuser runs its command as
        # *root*, which built the project as root and left 500-odd root-owned
        # files in .build that no later build could overwrite — and ran the app
        # under test as root, which is not how anyone runs it.
        if ssh_run "$ip" "sudo launchctl asuser 501 sudo -u ${SSH_USER} /bin/bash -lc \
            'PROJECT_DIR=$REMOTE_DIR $REMOTE_DIR/vm/scripts/ui-test.sh' 2>&1"; then
            log_info "Interface tests passed."
        else
            log_error "Interface tests failed."
            exit_code=1
        fi
    fi

    # Close TextEdit
    ssh_run "$ip" "sudo launchctl asuser 501 /usr/bin/osascript -e 'tell application \"TextEdit\" to quit saving no'" 2>/dev/null || true

    # ------------------------------------------------------------------ #
    # Post-run                                                              #
    # ------------------------------------------------------------------ #
    if [ "$keep_vm" = true ]; then
        log_info "VM kept running (--keep).  Connect with:"
        log_info "  sshpass -p '$SSH_PASS' ssh ${SSH_USER}@${ip}"
        log_info "  tart stop $VM_NAME  # to shut down"
        trap - EXIT
    fi

    return $exit_code
}

run_tests "$@"
