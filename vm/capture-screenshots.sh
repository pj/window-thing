#!/bin/bash
set -euo pipefail

# Capture screenshots of the WindowThing UI from inside the headless test VM.
#
# The VM has a virtual WindowServer, so the app renders and `screencapture`
# works even with `tart run --no-graphics`. Screens are opened non-interactively
# via the app's `--screenshot <scene>` launch flag.

VM_NAME="windowthing-test"
SSH_USER="admin"
SSH_PASS="admin"
SSH_TIMEOUT=90
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/vm/screenshots"
REMOTE_PROJ="~/Projects/window_thing"

# Default scenes to capture
SCENES=(overlay quickmove onboarding settings)
RESOLUTION="1920x1200"
KEEP_VM=false
SKIP_BUILD=false
TEST_WINDOWS=3

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --scene NAME        Capture only this scene (repeatable).
                      One of: overlay, quickmove, onboarding, settings
  --resolution WxH    VM display resolution (default: $RESOLUTION).
                      Applied with 'tart set' — requires the VM to be stopped.
  --windows N         Number of TextEdit test windows to open (default: $TEST_WINDOWS)
  --skip-build        Reuse the existing build in the VM
  --keep              Leave the VM running afterwards
  --help              Show this help

Screenshots are written to vm/screenshots/<scene>.png
EOF
}

SCENE_OVERRIDE=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --scene)      SCENE_OVERRIDE+=("$2"); shift 2 ;;
        --resolution) RESOLUTION="$2";        shift 2 ;;
        --windows)    TEST_WINDOWS="$2";      shift 2 ;;
        --skip-build) SKIP_BUILD=true;        shift ;;
        --keep)       KEEP_VM=true;           shift ;;
        --help|-h)    usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done
[ ${#SCENE_OVERRIDE[@]} -gt 0 ] && SCENES=("${SCENE_OVERRIDE[@]}")

# --------------------------------------------------------------------------- #
# SSH helpers                                                                   #
# --------------------------------------------------------------------------- #

# A shared control connection keeps sshd from rate-limiting the many short
# commands this script issues (repeated password auth trips MaxAuthTries).
SSH_CONTROL="/tmp/windowthing-capture-ssh-$$"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=10 -o IdentitiesOnly=yes -o PubkeyAuthentication=no
          -o NumberOfPasswordPrompts=1 -o LogLevel=ERROR
          -o ControlMaster=auto -o "ControlPath=$SSH_CONTROL" -o ControlPersist=300)

ssh_run() { sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${VM_IP}" "$@"; }

# Run a command inside the logged-in Aqua session (UID 501). SSH sessions are
# not part of the GUI session, so anything that must draw needs this.
gui_run() { ssh_run "sudo launchctl asuser 501 $*"; }

# --------------------------------------------------------------------------- #
# Prerequisites and VM boot                                                     #
# --------------------------------------------------------------------------- #

for tool in tart sshpass rsync; do
    command -v "$tool" &>/dev/null || { log_error "$tool is not installed"; exit 1; }
done

tart list | grep -q "${VM_NAME}" || {
    log_error "VM '${VM_NAME}' not found. Build it with: cd vm/packer && packer build windowthing-test.pkr.hcl"
    exit 1
}

close_ssh() { rm -f "$SSH_CONTROL" 2>/dev/null || true; }
cleanup() { close_ssh; log_info "Stopping VM..."; tart stop "$VM_NAME" 2>/dev/null || true; }
if [ "$KEEP_VM" = false ]; then trap cleanup EXIT; else trap close_ssh EXIT; fi

if tart list | grep "${VM_NAME}" | grep -q running; then
    log_info "VM already running (display resolution left as-is)"
else
    log_info "Setting VM display to ${RESOLUTION}..."
    tart set "$VM_NAME" --display "$RESOLUTION"
    log_info "Starting VM headlessly..."
    tart run "$VM_NAME" --no-graphics &>/dev/null &
    sleep 5
fi

VM_IP=""
for _ in {1..30}; do
    VM_IP=$(tart ip "$VM_NAME" 2>/dev/null || echo "")
    [ -n "$VM_IP" ] && break
    sleep 2
done
[ -n "$VM_IP" ] || { log_error "Could not get VM IP"; exit 1; }
log_info "VM IP: $VM_IP"

log_info "Waiting for SSH..."
elapsed=0
while ! nc -z "$VM_IP" 22 2>/dev/null; do
    sleep 2; elapsed=$((elapsed + 2))
    [ $elapsed -ge $SSH_TIMEOUT ] && { log_error "SSH timeout after ${SSH_TIMEOUT}s"; exit 1; }
done
sleep 2

# --------------------------------------------------------------------------- #
# Sync and build                                                                #
# --------------------------------------------------------------------------- #

if [ "$SKIP_BUILD" = false ]; then
    log_info "Syncing project to VM..."
    ssh_run "mkdir -p $REMOTE_PROJ"
    sshpass -p "$SSH_PASS" rsync -az --delete \
        --exclude '.build' --exclude '.git' --exclude 'vm' \
        -e "ssh ${SSH_OPTS[*]}" \
        "$PROJECT_DIR/" "${SSH_USER}@${VM_IP}:${REMOTE_PROJ}/"

    log_info "Building WindowThing in VM..."
    # No pipe here: piping to tail would mask the build's exit status and the
    # script would go on to screenshot a stale binary.
    if ! ssh_run "cd $REMOTE_PROJ && swift build --product WindowThing 2>&1"; then
        log_error "Build failed in VM (toolchain there is older than the host's — check SDK availability)"
        exit 1
    fi
fi

APP_BIN="$REMOTE_PROJ/.build/debug/WindowThing"

# --------------------------------------------------------------------------- #
# Display mode                                                                  #
# --------------------------------------------------------------------------- #
# `tart set --display` sizes the virtual display but the guest keeps its own
# mode, so switch it from inside too. HiDPI is preferred for crisp captures.

log_info "Setting guest display mode to ${RESOLUTION}..."
sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" \
    "$PROJECT_DIR/vm/scripts/set-display-mode.swift" \
    "${SSH_USER}@${VM_IP}:/tmp/set-display-mode.swift" >/dev/null
ssh_run "swift /tmp/set-display-mode.swift ${RESOLUTION%x*} ${RESOLUTION#*x}" \
    || log_warn "Could not change display mode — continuing at current resolution"

# --------------------------------------------------------------------------- #
# TCC grants                                                                    #
# --------------------------------------------------------------------------- #
# Accessibility: the app reads and moves windows.
# ScreenCapture: the app's thumbnail cache calls CGRequestScreenCaptureAccess on
# launch, and an ungranted request puts a modal dialog on top of every capture.

log_info "Granting Accessibility and Screen Recording to the app binary..."
ssh_run "TS=\$(date +%s); BIN=\$(eval echo $APP_BIN)
for db in '/Library/Application Support/com.apple.TCC/TCC.db' \"\$HOME/Library/Application Support/com.apple.TCC/TCC.db\"; do
  for svc in kTCCServiceAccessibility kTCCServiceScreenCapture; do
    for client in \"\$BIN\" /usr/bin/sudo /bin/launchctl /usr/sbin/screencapture; do
      sudo sqlite3 \"\$db\" \"INSERT OR REPLACE INTO access(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,flags,last_modified) VALUES('\$svc','\$client',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,\$TS);\" 2>/dev/null
    done
  done
done" || log_warn "TCC grant failed — the overlay may render without live window data"

# --------------------------------------------------------------------------- #
# Test windows — give the overlay something to show                             #
# --------------------------------------------------------------------------- #

if [ "$TEST_WINDOWS" -gt 0 ]; then
    log_info "Opening $TEST_WINDOWS TextEdit test window(s)..."
    # One SSH round-trip for all of them; the loop lives in the remote shell.
    gui_run "/bin/sh -c 'for i in \$(seq 1 $TEST_WINDOWS); do /usr/bin/open -na TextEdit --args --new-document; sleep 2; done'" \
        || log_warn "Could not open test windows — the overlay will show empty cells"
    sleep 2
fi

# --------------------------------------------------------------------------- #
# Capture                                                                       #
# --------------------------------------------------------------------------- #

mkdir -p "$OUT_DIR"

capture_scene() {
    local scene=$1
    log_info "Capturing '$scene'..."

    # The app suppresses its own first-run onboarding under --screenshot, so no
    # defaults juggling is needed here — the scene name is the only input.
    gui_run "$APP_BIN --screenshot $scene >/tmp/windowthing-$scene.log 2>&1 &" || true
    sleep 6   # launch + the app's 1.5s present delay + window animation

    # Dismiss any stray system prompt so it doesn't sit on top of the shot.
    ssh_run "sudo killall -9 UserNotificationCenter 2>/dev/null; true" || true

    # Run screencapture directly rather than through sudo: sudo as the
    # responsible process triggers the macOS 15 screen-recording prompt.
    # Capture under $HOME so a stale root-owned /tmp file can't block the write.
    local remote_shot="\$HOME/windowthing-shots/$scene.png"
    if ! ssh_run "mkdir -p \$HOME/windowthing-shots && rm -f $remote_shot && \
                  /usr/sbin/screencapture -x $remote_shot && test -s $remote_shot"; then
        log_warn "screencapture failed for '$scene'"
        return 1
    fi

    sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" \
        "${SSH_USER}@${VM_IP}:windowthing-shots/$scene.png" "$OUT_DIR/$scene.png" >/dev/null

    # One app instance per scene — kill it so the next launch starts clean.
    ssh_run "pkill -f 'WindowThing --screenshot' || true" 2>/dev/null || true
    sleep 1

    log_info "  -> vm/screenshots/$scene.png"
}

failed=0
for scene in "${SCENES[@]}"; do
    capture_scene "$scene" || failed=1
done

# --------------------------------------------------------------------------- #
# Teardown                                                                      #
# --------------------------------------------------------------------------- #

ssh_run "sudo launchctl asuser 501 /usr/bin/osascript -e 'tell application \"TextEdit\" to quit saving no'" 2>/dev/null || true

if [ "$KEEP_VM" = true ]; then
    log_info "VM kept running (--keep). Connect with:"
    log_info "  sshpass -p '$SSH_PASS' ssh ${SSH_USER}@${VM_IP}"
fi

[ $failed -eq 0 ] && log_info "Screenshots written to $OUT_DIR" || log_warn "Some scenes failed to capture"
exit $failed
