#!/usr/bin/env bash
# release.sh — cut a WindowThing release and publish it to GitHub Releases.
#
# Usage:
#   scripts/release.sh              # release the version in ./VERSION
#   scripts/release.sh 0.2.0        # bump ./VERSION to 0.2.0, then release
#   scripts/release.sh --dry-run    # build and package, but publish nothing
#
# What it does, in order:
#   1. Refuses to run on a dirty tree, a detached HEAD, or an existing tag.
#   2. Runs the test suite.
#   3. Builds, signs, notarizes and staples the app (scripts/package.sh).
#   4. Rewrites flake.nix to point at the new release asset and its hash.
#   5. Commits that, tags it, and pushes.
#   6. Creates the GitHub Release and uploads the zip.
#
# Step 4 has to happen before the tag: the tag is what consumers pin as a flake
# input, so the flake.nix at that tag must already describe its own release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="WindowThing"
REPO="pj/window-thing"

cd "$PROJECT_DIR"

log()  { echo "==> $*"; }
fail() { echo "error: $*" >&2; exit 1; }

# Sparkle's CLI tools (sign_update), cached in build/ across runs.
SPARKLE_VERSION="2.9.6"
SPARKLE_TOOLS="$PROJECT_DIR/build/sparkle-tools"

fetch_sparkle_tools() {
    [ -x "$SPARKLE_TOOLS/bin/sign_update" ] && return 0

    log "Fetching Sparkle $SPARKLE_VERSION CLI tools"
    rm -rf "$SPARKLE_TOOLS"
    mkdir -p "$SPARKLE_TOOLS"
    local tmp
    tmp="$(mktemp -t sparkle).tar.xz"
    curl -fsSL -o "$tmp" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    tar -xf "$tmp" -C "$SPARKLE_TOOLS" ./bin
    rm -f "$tmp"
    xattr -dr com.apple.quarantine "$SPARKLE_TOOLS/bin" 2>/dev/null || true
}

DRY_RUN=false
NEW_VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)  DRY_RUN=true; shift ;;
        --help|-h)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)         fail "unknown option: $1" ;;
        *)          NEW_VERSION="$1"; shift ;;
    esac
done

# ---- preflight -----------------------------------------------------------

command -v gh >/dev/null || fail "gh is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated (run: gh auth login)"

[ -z "$(git status --porcelain)" ] || fail "working tree is dirty — commit or stash first"

BRANCH="$(git branch --show-current)"
[ -n "$BRANCH" ] || fail "HEAD is detached — check out a branch first"

if [ -n "$NEW_VERSION" ]; then
    echo "$NEW_VERSION" > VERSION
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must be X.Y.Z, got: $VERSION"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    fail "tag $TAG already exists — bump VERSION"
fi

log "Releasing $APP_NAME $TAG from branch $BRANCH"

# ---- test ----------------------------------------------------------------

# Skips the two suites that drive real windows through the Accessibility API.
# They are timing-dependent and flake often enough to block a release for no
# good reason ("Switch between layouts moves windows" is the usual culprit).
# CI runs them separately on every push — see .github/workflows/ci.yml, which
# skips the same two in its unit job.
#
# --skip matches the suite's *type* name, not its @Suite display name.
log "Running tests (excluding the window-driving suites)"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
    "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" test \
    --skip "IntegrationTests" \
    --skip "PrimaryDisplayLayoutTests"

# ---- package -------------------------------------------------------------

"$SCRIPT_DIR/package.sh"

ZIP_PATH="$PROJECT_DIR/build/$APP_NAME.zip"
[ -f "$ZIP_PATH" ] || fail "package.sh did not produce $ZIP_PATH"

# Subresource-integrity hash for fetchurl: base64 of the raw sha256 digest.
# Computed with coreutils rather than the nix CLI, whose hashing subcommands
# have changed spelling across releases.
SRI="sha256-$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1 | xxd -r -p | base64)"
log "Asset hash: $SRI"

# ---- sign the update for Sparkle -----------------------------------------

# The download URL is deterministic from the tag, so the appcast entry can be
# written before the release exists. That lets the flake pin and the appcast
# entry land in the same commit as the tag, rather than trailing behind it.
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/$APP_NAME.zip"

# Read the build number back out of the bundle rather than recomputing it: the
# commit count changes when this script commits, and Sparkle compares
# CFBundleVersion, so a mismatch would make the release invisible to installed
# copies.
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$PROJECT_DIR/build/$APP_NAME.app/Contents/Info.plist")"

fetch_sparkle_tools
SIG_LINE="$("$SPARKLE_TOOLS/bin/sign_update" "$ZIP_PATH")"
# sign_update prints: sparkle:edSignature="..." length="..."
SIGNATURE="$(printf '%s' "$SIG_LINE" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

[ -n "$SIGNATURE" ] || fail "sign_update produced no signature (is the EdDSA private key in this keychain?)"

log "Update signature: ${SIGNATURE:0:16}… (${LENGTH} bytes)"

if [ "$DRY_RUN" = true ]; then
    log "Dry run — stopping before any push. Artifact: $ZIP_PATH"
    exit 0
fi

# ---- record the release in the appcast -----------------------------------

log "Appending to appcast.xml"
python3 "$SCRIPT_DIR/append_appcast_item.py" \
    --appcast "$PROJECT_DIR/appcast.xml" \
    --version "$BUILD_NUMBER" \
    --short-version "$VERSION" \
    --url "$ASSET_URL" \
    --length "$LENGTH" \
    --signature "$SIGNATURE"

# ---- pin the release in flake.nix ----------------------------------------

log "Updating flake.nix pin"
python3 - "$VERSION" "$SRI" <<'PY'
import re, sys, pathlib

version, sri = sys.argv[1], sys.argv[2]
path = pathlib.Path("flake.nix")
text = path.read_text()

text, n_v = re.subn(r'(\n\s*version\s*=\s*")[^"]*(";)', rf'\g<1>{version}\g<2>', text, count=1)
text, n_h = re.subn(r'(\n\s*hash\s*=\s*")[^"]*(";)',    rf'\g<1>{sri}\g<2>',     text, count=1)

if n_v != 1 or n_h != 1:
    sys.exit(f"flake.nix: expected one version= and one hash= to rewrite, got {n_v} and {n_h}")

path.write_text(text)
PY

git add flake.nix VERSION appcast.xml
git commit -m "Release $TAG"

# ---- tag and push --------------------------------------------------------

git tag -a "$TAG" -m "$APP_NAME $VERSION"

log "Pushing $BRANCH and $TAG"
git push origin "$BRANCH"
git push origin "$TAG"

# ---- publish -------------------------------------------------------------

log "Creating GitHub release"
gh release create "$TAG" "$ZIP_PATH" \
    --repo "$REPO" \
    --title "$APP_NAME $VERSION" \
    --notes "Developer ID signed, notarized and stapled. Requires macOS 13 or later.

Install with nix:

    window_thing.url = \"github:$REPO?ref=$TAG\";

Or download \`$APP_NAME.zip\`, unzip, and drag \`$APP_NAME.app\` to /Applications.

On first launch, grant Accessibility (required) and Screen Recording (optional,
for window thumbnails) in System Settings → Privacy & Security."

echo
log "Released: https://github.com/$REPO/releases/tag/$TAG"
