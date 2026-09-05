#!/bin/bash
# check-accessibility.sh — is Accessibility actually usable, not merely ticked?
#
# Runs inside the VM. Prints one line per client: "<name> <verdict>", where the
# verdict is one of ok | missing | denied | stale | unreadable.
#
# "stale" is the one worth having this script for. A TCC row carries a code
# requirement as well as a yes/no, and the two can disagree: an entry added
# while the app was unsigned pins that build's cdhash, and toggling the checkbox
# afterwards does not rewrite it. The row then reads as approved while TCC
# refuses the app that is actually installed, and the only symptom is every
# window-driving assertion timing out.

DB="/Library/Application Support/com.apple.TCC/TCC.db"
SERVICE="kTCCServiceAccessibility"
PROJECT_DIR="${1:-$HOME/Projects/window_thing}"

verdict_for() {
    local label="$1" client="$2" target="$3"

    local row
    row=$(sudo sqlite3 "$DB" \
        "select auth_value || '|' || coalesce(hex(csreq),'') from access
          where service='$SERVICE' and client='$client';" 2>/dev/null)

    if [ -z "$row" ]; then echo "$label missing"; return; fi
    if [ "${row%%|*}" != "2" ]; then echo "$label denied"; return; fi

    local hex="${row#*|}"
    if [ -z "$hex" ]; then
        # Approved with no requirement recorded: TCC accepts the client by path
        # or bundle id alone, which is what the scripted grants used to write.
        echo "$label ok"
        return
    fi

    local req
    req=$(echo "$hex" | xxd -r -p | csreq -r- -t 2>/dev/null)
    if [ -z "$req" ]; then echo "$label unreadable"; return; fi

    if codesign --verify -R="$req" "$target" >/dev/null 2>&1; then
        echo "$label ok"
    else
        echo "$label stale"
    fi
}

verdict_for WindowThing com.windowthing.app "$PROJECT_DIR/build/WindowThing.app"
verdict_for ax-driver "$PROJECT_DIR/build/ax-driver" "$PROJECT_DIR/build/ax-driver"

# The process TCC actually blames for the driver.
#
# Consent is recorded against the *responsible* process, not the one that calls
# the API. The app escapes this because `open` hands it to launchd, which makes
# it its own responsible process; the driver is exec'd straight from the ssh
# session, so the decision is taken against sshd-keygen-wrapper instead. Its own
# row can sit at denied while the driver's says approved, and then every query
# the driver makes comes back empty with nothing to say why.
verdict_for ssh-responsible-process /usr/libexec/sshd-keygen-wrapper /usr/libexec/sshd-keygen-wrapper
