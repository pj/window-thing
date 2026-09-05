{
  description = "WindowThing - A Swift window management app for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Full path to the Xcode swift binary.  Bypasses nix's xcbuild stub
        # which shadows /usr/bin/swift and breaks xcrun-based tool lookup.
        xcodeToolchain = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin";
        swiftBin = "${xcodeToolchain}/swift";
        developerDir = "/Applications/Xcode.app/Contents/Developer";
        xcodeSdk = "${developerDir}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";

      in
      {
        # ------------------------------------------------------------------ #
        #  Default package — the released, notarized app                      #
        # ------------------------------------------------------------------ #
        #
        # This deliberately installs a *prebuilt* app rather than compiling from
        # source. WindowThing needs Accessibility and Screen Recording, and macOS
        # keys those grants to the app's code signature. Nix can't sign inside its
        # build sandbox, so a source build would be ad-hoc signed — and its
        # identity would change on every rebuild, making the OS drop the
        # permissions and forcing the user to re-approve after each update.
        #
        # The release asset is Developer ID signed, notarized and stapled, so its
        # identity is stable across versions and the grants survive upgrades.
        #
        # `scripts/release.sh` rewrites the version and hash below, so keep them
        # each on their own line as a simple `name = "value";` pair.
        packages.default = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "window-thing";
          version = "0.6.5";

          src = pkgs.fetchurl {
            url = "https://github.com/pj/window-thing/releases/download/v${finalAttrs.version}/WindowThing.zip";
            hash = "sha256-Q6JXZGm+sD9QYkPCZV/Fj7JDzsfQXrHSRLHxLhT8aDk=";
          };

          nativeBuildInputs = [ pkgs.unzip ];

          # The zip holds WindowThing.app at its root, not inside a directory.
          sourceRoot = ".";

          # Nothing here is ours to fix up. Stripping the binary or letting the
          # darwin re-signing hook touch it would invalidate the Developer ID
          # signature and the stapled notarization ticket.
          dontFixup = true;

          installPhase = ''
            runHook preInstall

            # unzip materialises any AppleDouble entries in the archive as stray
            # `._*` files. They are not part of the signature's seal, so leaving
            # them turns a valid signature into "a sealed resource is missing or
            # invalid" and Gatekeeper rejects the app. Releases built by
            # scripts/package.sh no longer contain them, but older assets do.
            find . -name '._*' -delete
            rm -rf __MACOSX

            mkdir -p "$out/Applications"
            cp -R WindowThing.app "$out/Applications/"

            # Convenience entry point; the app is a menubar agent so this mainly
            # exists for `--screenshot` and other CLI flags.
            mkdir -p "$out/bin"
            ln -s "$out/Applications/WindowThing.app/Contents/MacOS/WindowThing" \
                  "$out/bin/window-thing"

            runHook postInstall
          '';

          meta = {
            description = "macOS menubar window manager with hotkey-driven layouts";
            homepage = "https://github.com/pj/window-thing";
            platforms = pkgs.lib.platforms.darwin;
            mainProgram = "window-thing";
            sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          };
        });

        # ------------------------------------------------------------------ #
        #  Source build — development only                                    #
        # ------------------------------------------------------------------ #
        #
        # Impure: reaches into the host's Xcode and reuses the SPM checkout cache
        # from the working tree so it can run without network access. Produces an
        # ad-hoc signed binary, so it is NOT suitable for installing the app —
        # see the note on packages.default. Use `scripts/package.sh` to produce a
        # distributable build.
        packages.from-source = pkgs.stdenvNoCC.mkDerivation {
          name = "window-thing-from-source";
          src = ./.;

          __impureHostDeps = [
            "/usr/bin/swift"
            "/usr/bin/swiftc"
            "/usr/bin/swift-package"
            "/Applications/Xcode.app"
            "/Library/Developer/CommandLineTools"
            "/System/Library/Frameworks"
            "/usr/lib/swift"
          ];

          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export DEVELOPER_DIR="${developerDir}"
            export SDKROOT="${xcodeSdk}"
            export PATH="${xcodeToolchain}:$PATH"

            mkdir -p .build
            if [ -d "${self}/.build/checkouts" ]; then
              cp -r "${self}/.build/checkouts" .build/checkouts
            fi

            ${swiftBin} build -c release --disable-automatic-resolution 2>&1
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp .build/release/WindowThing $out/bin/window-thing
          '';

          meta = {
            description = "macOS window manager built from source (unsigned, development only)";
            platforms = pkgs.lib.platforms.darwin;
          };
        };

        # ------------------------------------------------------------------ #
        #  Dev shell                                                          #
        # ------------------------------------------------------------------ #
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            swift-format
            swiftlint
            jq
            yq
          ];

          shellHook = ''
            # Override the nix xcbuild stub so the real Xcode toolchain is used.
            export DEVELOPER_DIR="${developerDir}"
            export SDKROOT="${xcodeSdk}"
            export PATH="${xcodeToolchain}:$PATH"

            echo "WindowThing Development Environment"
            echo "Swift: $(${swiftBin} --version 2>/dev/null | head -1 || echo 'not found')"
            echo ""
            echo "Build:    swift build"
            echo "Test:     swift test"
            echo "Lint:     swift-format lint --recursive Sources/ Tests/"
            echo "Package:  scripts/package.sh"
            echo "Release:  scripts/release.sh"
          '';
        };

        # ------------------------------------------------------------------ #
        #  Checks                                                             #
        # ------------------------------------------------------------------ #
        checks.format = pkgs.stdenvNoCC.mkDerivation {
          name = "window-thing-format-check";
          src = ./.;
          nativeBuildInputs = [ pkgs.swift-format ];
          buildPhase = ''
            swift-format lint --recursive Sources/ Tests/ 2>&1 | tee format-output.log
          '';
          installPhase = ''
            mkdir -p $out
            cp format-output.log $out/
          '';
        };
      }
    );
}
