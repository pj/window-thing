#!/usr/bin/env bash
# vm-store.sh — where the test VMs live, and whether they are reachable.
#
# Sourced by anything that drives tart. The VMs are tens of gigabytes each and
# sit on an external disk rather than the boot drive; tart finds them through
# TART_HOME, so everything here is about pointing that at the right place and
# failing clearly when the disk is not attached.

# Overridable, so a machine that keeps its VMs elsewhere needs no edit here.
TART_HOME="${TART_HOME:-/Volumes/VMs/tart}"
export TART_HOME

# The volume the store sits on, which is what gets unplugged.
VM_VOLUME="$(dirname "$TART_HOME")"

# The pristine copy, kept beside the working VM.
#
# On APFS this costs almost nothing: `cp -c` clones block-for-block and the two
# only diverge as the working VM is written to. It exists so that a VM broken by
# a bad test run, an interrupted write, or a yanked cable can be put back in
# seconds instead of being rebuilt — which means re-downloading the base image
# and granting Accessibility to three clients by hand again.
VM_GOLDEN="${VM_GOLDEN:-${VM_NAME:-macos-dev}-golden}"

# Fail unless the store is really on the external disk.
#
# Checking the directory exists is not enough. With the disk detached, anything
# that writes to the path creates it on the boot drive instead — tart would then
# start from an empty home and report no VMs, and macOS would refuse to mount the
# real disk there later because the mount point is occupied. So compare device
# numbers: same device as `/` means we are looking at a stray directory, not the
# disk.
require_vm_store() {
    local root_dev store_dev
    root_dev="$(/usr/bin/stat -f '%d' / 2>/dev/null)"

    if [ ! -d "$VM_VOLUME" ]; then
        vm_store_error "The VM disk is not attached: $VM_VOLUME does not exist."
        return 1
    fi

    store_dev="$(/usr/bin/stat -f '%d' "$VM_VOLUME" 2>/dev/null)"
    if [ "$store_dev" = "$root_dev" ]; then
        vm_store_error \
            "$VM_VOLUME is on the boot disk, so the external disk is not mounted." \
            "Remove that directory once nothing is using it, or the disk cannot mount there:" \
            "  rmdir '$VM_VOLUME'"
        return 1
    fi

    if [ ! -d "$TART_HOME/vms" ]; then
        vm_store_error "The disk is attached but holds no VM store at $TART_HOME/vms."
        return 1
    fi

    return 0
}

# One place for the explanation, since every caller needs to say the same thing.
vm_store_error() {
    {
        echo ""
        for line in "$@"; do echo "  $line"; done
        echo ""
        echo "  The test VMs live on an external disk to keep ~27GB off the boot drive."
        echo "  Attach it, or point somewhere else for this run:"
        echo "      TART_HOME=/path/to/tart ./vm/run-tests.sh ..."
        echo ""
        echo "  If the working VM is broken rather than missing, restore the pristine copy:"
        echo "      TART_HOME='$TART_HOME' tart delete '${VM_NAME:-macos-dev}'"
        echo "      /bin/cp -c -R '$TART_HOME/vms/$VM_GOLDEN' '$TART_HOME/vms/${VM_NAME:-macos-dev}'"
        echo "  That is an APFS clone: it takes a second and costs no extra space."
        echo ""
    } >&2
}
