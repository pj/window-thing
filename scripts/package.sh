#!/usr/bin/env bash
# package.sh — build WindowThing.app and, by default, sign + notarize + staple it.
#
# Usage:
#   scripts/package.sh                  # signed, notarized, stapled → build/WindowThing.zip
#   scripts/package.sh --no-notarize    # signed only (fast; for local smoke tests)
#   scripts/package.sh --no-sign        # plain unsigned bundle (implies --no-notarize)
#
# Environment:
#   CODESIGN_IDENTITY   signing identity (default: "Developer ID Application")
#   NOTARY_PROFILE      notarytool keychain profile (default: "windowthing")
#
# Why signing matters here: WindowThing needs Accessibility and Screen Recording,
# and macOS keys those grants to the app's code signature. An unsigned or ad-hoc
# signed build gets a new identity on every rebuild, so the OS drops the grants
# and the user has to re-approve after every single update. A Developer ID
# signature keeps the identity stable across versions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="WindowThing"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-windowthing}"

SIGN=true
NOTARIZE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-sign)      SIGN=false; NOTARIZE=false; shift ;;
        --no-notarize)  NOTARIZE=false;             shift ;;
        --help|-h)      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)              echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

log()  { echo "==> $*"; }
fail() { echo "error: $*" >&2; exit 1; }

# ---- toolchain (mirrors scripts/dev.sh and the nix devShell) --------------

# Asked for rather than assumed. The test VM has Xcode at
# /Applications/Xcode_16.4.app, so hardcoding /Applications/Xcode.app meant this
# script could not build the bundle there at all.
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
[ -n "$DEVELOPER_DIR" ] || DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
XCODE_TOOLCHAIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin"
export DEVELOPER_DIR
export PATH="${XCODE_TOOLCHAIN}:${PATH}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null \
    || echo "${DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")"
SWIFT="${XCODE_TOOLCHAIN}/swift"

[ -x "$SWIFT" ] || SWIFT="$(command -v swift || true)"
[ -n "$SWIFT" ] && [ -x "$SWIFT" ] \
    || fail "no swift toolchain found (DEVELOPER_DIR=$DEVELOPER_DIR)"

# ---- version -------------------------------------------------------------

VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
[ -n "$VERSION" ] || fail "VERSION file is empty"

# Monotonic build number so macOS treats each release as newer than the last.
if BUILD_NUMBER="$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null)"; then
    :
else
    BUILD_NUMBER=1
fi

log "Packaging $APP_NAME $VERSION (build $BUILD_NUMBER)"

# ---- preflight -----------------------------------------------------------
# Check credentials before the (slow) build rather than after it.

if [ "$SIGN" = true ]; then
    security find-identity -v -p codesigning 2>/dev/null \
        | grep -q "$CODESIGN_IDENTITY" \
        || fail "no codesigning identity matching \"$CODESIGN_IDENTITY\" in the keychain.
  Install the Developer ID Application certificate, or pass --no-sign."
fi

if [ "$NOTARIZE" = true ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || fail "no notarytool keychain profile named \"$NOTARY_PROFILE\".
  Create one with:
    xcrun notarytool store-credentials $NOTARY_PROFILE \\
      --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>
  Or override with NOTARY_PROFILE=<name>, or pass --no-notarize."
fi

# ---- build ---------------------------------------------------------------

log "Building release binary"
cd "$PROJECT_DIR"
"$SWIFT" build -c release --product "$APP_NAME"

BINARY="$PROJECT_DIR/.build/release/$APP_NAME"
[ -f "$BINARY" ] || fail "binary not produced at $BINARY"

# ---- assemble bundle -----------------------------------------------------

APP_DIR="$BUILD_DIR/$APP_NAME.app"
log "Assembling $APP_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

# AppleScript terminology. Named by OSAScriptingDefinition in the Info.plist,
# and looked up in Resources — without it the app has no vocabulary and every
# command fails as "not handled".
cp "$PROJECT_DIR/packaging/WindowThing.sdef" "$APP_DIR/Contents/Resources/"

plutil -replace CFBundleShortVersionString -string "$VERSION"      "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion            -string "$BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

# SwiftPM emits resource bundles next to the binary for any target with
# resources; they have to travel inside the app or the app can't find them.
shopt -s nullglob
for bundle in "$PROJECT_DIR"/.build/release/*.bundle; do
    log "Bundling resources: $(basename "$bundle")"
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

# Sparkle arrives as an XCFramework that SwiftPM links against but does not
# embed — executables get no embed step. Copy the macOS slice in ourselves; the
# -rpath in Package.swift is what lets the binary find it here at runtime.
SPARKLE_FW="$(find "$PROJECT_DIR/.build/artifacts" \
    -type d -path '*/Sparkle.xcframework/macos-*/Sparkle.framework' \
    -print -quit 2>/dev/null || true)"

[ -n "$SPARKLE_FW" ] || fail "Sparkle.framework not found under .build/artifacts — run 'swift build' first"

log "Embedding $(basename "$(dirname "$SPARKLE_FW")")/Sparkle.framework"
mkdir -p "$APP_DIR/Contents/Frameworks"
# -R preserves the framework's version symlinks, which codesign requires.
cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"

# ---- sign ----------------------------------------------------------------

ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

if [ "$SIGN" = false ]; then
    log "Skipping signing (--no-sign)"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$ZIP_PATH"
    log "Done (unsigned): $APP_DIR"
    exit 0
fi

# A note on the ditto flags used below: --norsrc --noextattr keep the bundle's
# extended attributes out of the archive. Without them ditto stores them as
# AppleDouble entries, and `unzip` — which is what the nix installer uses —
# materialises those as stray `._*` files. Those files are not in the
# signature's seal, so codesign reports "a sealed resource is missing or
# invalid" and Gatekeeper rejects the app. The only xattr on the bundle is
# com.apple.provenance, which nothing needs.
#
# --options runtime  → hardened runtime, required for notarization
# --timestamp        → secure timestamp, also required for notarization
#
# Our own code links statically, so the only nested code is Sparkle. Signing has
# to run inside-out — helpers, then the framework, then the app — because
# signing an enclosing bundle seals whatever its contents are at that moment.
# Sparkle ships signed by the Sparkle project, and notarization rejects that
# ("not signed with a valid Developer ID certificate", "signature does not
# include a secure timestamp"), so every nested binary gets re-signed here.
#
# Re-signing the framework with our own identity is also what keeps the hardened
# runtime's library validation happy: it requires embedded code to share the
# app's team identifier, so no disable-library-validation entitlement is needed.
log "Signing with \"$CODESIGN_IDENTITY\""

SPARKLE_IN_APP="$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_IN_APP" ]; then
    for nested in \
        "$SPARKLE_IN_APP/Versions/B/XPCServices/Downloader.xpc" \
        "$SPARKLE_IN_APP/Versions/B/XPCServices/Installer.xpc" \
        "$SPARKLE_IN_APP/Versions/B/Autoupdate" \
        "$SPARKLE_IN_APP/Versions/B/Updater.app" \
        "$SPARKLE_IN_APP"
    do
        [ -e "$nested" ] || continue
        log "  signing $(basename "$nested")"
        codesign --force --options runtime --timestamp \
                 --sign "$CODESIGN_IDENTITY" "$nested"
    done
fi

codesign --force \
         --options runtime \
         --timestamp \
         --sign "$CODESIGN_IDENTITY" \
         "$APP_DIR"

# --deep on *verification* (never on signing) so the nested Sparkle helpers are
# checked too, rather than only the app's outer seal.
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$ZIP_PATH"

if [ "$NOTARIZE" = false ]; then
    log "Skipping notarization (--no-notarize)"
    log "Done (signed, not notarized): $ZIP_PATH"
    exit 0
fi

# ---- notarize ------------------------------------------------------------

log "Submitting to Apple for notarization (this takes a few minutes)"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# Staple the ticket into the bundle so it validates offline, then re-zip so the
# shipped archive contains the stapled copy rather than the pre-staple one.
log "Stapling ticket"
xcrun stapler staple "$APP_DIR"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$ZIP_PATH"

# ---- verify --------------------------------------------------------------

log "Verifying"
xcrun stapler validate "$APP_DIR"
spctl -a -vvv -t install "$APP_DIR"

# Verify the *archive* too, not just the bundle on disk. The two can disagree —
# a zip carrying AppleDouble entries unpacks into something whose signature no
# longer verifies, which is exactly how a broken v0.1.0 got shipped.
log "Verifying the archive unpacks to a valid signature"
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
( cd "$VERIFY_DIR" && unzip -q "$ZIP_PATH" )
codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/$APP_NAME.app"
spctl -a -vvv -t install "$VERIFY_DIR/$APP_NAME.app"

echo
log "Done: $ZIP_PATH"
log "SHA-256: $(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)"
