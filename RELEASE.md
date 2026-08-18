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

## Auto-update

WindowThing checks GitHub Releases for updates via [Sparkle](https://sparkle-project.org).
There is a "Check for Updates…" item in the menubar menu, and a background check once a day
(`SUScheduledCheckInterval`). `SUAllowsAutomaticUpdates` is false, so an available update still
surfaces Sparkle's normal "Install Update" prompt rather than swapping the app out silently.

**Where it does and doesn't apply.** Sparkle updates by replacing the `.app` on disk, which only
works where that bundle is writable. A nix-installed copy lives in `/nix/store`, which is
read-only and root-owned, so an update attempt could only fail. `UpdateChannel` in
`WindowThingCore` resolves this at launch from the bundle path: a normal install gets the updater,
a nix install gets a disabled "Updates managed by nix" item, and a bare `swift run` binary gets
"Updates unavailable in development builds". Update nix installs by bumping the flake input.

**How it's wired:**

- `SUFeedURL` points at `appcast.xml` at the repo root, served over `raw.githubusercontent.com`.
  That works because the repo is public; a private repo would need different hosting.
- `SUPublicEDKey` is the EdDSA public half of a signing keypair whose private half lives only in
  this machine's login keychain. Anyone can read the appcast and the zips, but only this machine
  can produce an update Sparkle accepts — it refuses any enclosure whose signature doesn't verify.
  This is the **same key SiteBlocker uses**: Sparkle's own guidance is that one signing key covers
  every app you embed it in, and `generate_keys` reuses the existing keychain entry rather than
  creating a second.
- Sparkle ships as an XCFramework that SwiftPM links but does not embed, so `package.sh` copies it
  into `Contents/Frameworks` and `Package.swift` adds the `@executable_path/../Frameworks` rpath.
- Sparkle's nested helpers (`Downloader.xpc`, `Installer.xpc`, `Autoupdate`, `Updater.app`) arrive
  signed by the Sparkle project. Notarization rejects that, so `package.sh` re-signs them
  inside-out with our Developer ID before sealing the app. Re-signing them with our own identity
  is also what satisfies the hardened runtime's library validation, so no
  `disable-library-validation` entitlement is needed.

`release.sh` signs the zip with `sign_update` and appends an `<item>` to `appcast.xml` **before**
tagging, so one commit carries the version, the flake pin and the appcast entry. The download URL
is deterministic from the tag, so the entry can be written before the release exists. The build
number in the entry is read back out of the built bundle rather than recomputed, since committing
changes the commit count and Sparkle compares `CFBundleVersion`.

If another machine ever needs to publish, it needs its own Developer ID cert and notarization
credentials **and** the Sparkle private key exported from this one
(`generate_keys -x <path>` to export, `-f <path>` to import). Don't generate a second keypair, or
`SUPublicEDKey` in already-shipped builds won't match.

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
