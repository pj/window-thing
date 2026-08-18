# Releasing WindowThing

WindowThing ships as a **Developer ID–signed, notarized, stapled** `.app`. It runs on any
macOS 13+ Mac with no developer account and no Gatekeeper warning.

## TL;DR

```sh
scripts/release.sh 0.2.0      # test, package, tag, push, publish
```

## Why it has to be signed

Not for Gatekeeper. Gatekeeper only challenges files carrying the `com.apple.quarantine`
attribute, which is set by the *downloading* application — nix's fetchers don't set it, so an
unsigned build installed through nix would launch without complaint.

The reason is **TCC**. WindowThing needs Accessibility (mandatory) and Screen Recording
(optional, for window thumbnails), and macOS records those grants against the app's code
signature:

- **Unsigned or ad-hoc signed** — the identity is effectively the binary's cdhash. Every rebuild
  produces a new hash, and every nix upgrade a new store path, so the OS drops the grants and the
  user re-approves the app in System Settings **after every update**.
- **Developer ID signed**, with a stable bundle identifier — the designated requirement still
  matches after an upgrade, so the grants persist.

That is also why `CFBundleIdentifier` (`com.windowthing.app`) must never change, and why
`flake.nix` installs the prebuilt release rather than compiling from source: nix cannot sign
inside its build sandbox.

**No provisioning profiles are needed.** Accessibility and Screen Recording are TCC prompts, not
restricted entitlements, so there are no App IDs, capabilities or profiles to manage — and no
entitlements file at all. Hardened runtime plus a secure timestamp is the whole requirement.

## One-time build-machine setup

### 1. Signing certificate

Install the **Developer ID Application** certificate and its private key into the login keychain.
Verify:

```sh
security find-identity -v -p codesigning
# → Developer ID Application: Paul Johnson (YF7LH93MG3)
```

### 2. Notarization credentials

```sh
xcrun notarytool store-credentials windowthing \
  --apple-id <your-apple-id> --team-id YF7LH93MG3 --password <app-specific-password>
```

`windowthing` is the keychain profile name `scripts/package.sh` expects; override with
`NOTARY_PROFILE`. Generate the app-specific password at <https://account.apple.com> →
Sign-In & Security.

### 3. Toolchain

Full Xcode (for `swift`, `notarytool`, `stapler`), plus `gh` authenticated with push access.

## What the scripts do

### `scripts/package.sh`

1. `swift build -c release`
2. Assembles `build/WindowThing.app` from `packaging/Info.plist`, stamping
   `CFBundleShortVersionString` from `./VERSION` and `CFBundleVersion` from the commit count.
3. `codesign --options runtime --timestamp` — hardened runtime and secure timestamp, both
   required for notarization. Everything links statically, so there are no nested binaries and
   no need for `--deep`.
4. `notarytool submit --wait`, then `stapler staple`, then re-zips so the shipped archive holds
   the stapled bundle.
5. Verifies with `stapler validate` and `spctl`.

Flags: `--no-notarize` (signed only, fast) and `--no-sign` (plain bundle).

### `scripts/release.sh`

Refuses to run on a dirty tree, a detached HEAD, or an existing tag. Runs the tests, packages,
then rewrites the `version` and `hash` in `flake.nix` to point at the new asset, commits that,
tags, pushes, and creates the GitHub Release.

The flake pin is updated **before** tagging on purpose: consumers pin a tag as their flake input,
so the `flake.nix` at that tag has to already describe its own release.

`--dry-run` stops after packaging, before anything is pushed.

## Bumping a version

`scripts/release.sh 0.2.0` writes `./VERSION` for you. Everything else — the bundle version, the
About box, the flake pin, the tag, the download URL — derives from that one file.

## Verifying a build by hand

```sh
codesign -dv --verbose=4 build/WindowThing.app   # Developer ID + hardened runtime + timestamp
xcrun stapler validate    build/WindowThing.app
spctl -a -vvv -t install  build/WindowThing.app  # → accepted, source=Notarized Developer ID
```

## Installing on another Mac

Via nix (see the README), or download the zip from the release, unzip, and drag
`WindowThing.app` to `/Applications`.

Either way, on first launch grant **Accessibility** in System Settings → Privacy & Security
(the app can't move windows without it), and optionally **Screen Recording** for window
thumbnails — it falls back to app icons if you decline.
