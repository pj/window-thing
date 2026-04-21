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

        # Common environment + SPM setup for derivations that invoke swift.
        # Copies the already-resolved SPM checkout cache so the build can run
        # offline (nix sandbox blocks network by default).
        xcodeSdk = "${developerDir}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";

        swiftSetup = ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"

          # Override xcode-select so the Xcode toolchain is found correctly.
          export DEVELOPER_DIR="${developerDir}"

          # Point SPM / swiftc at the matching Xcode SDK, not the nix one.
          export SDKROOT="${xcodeSdk}"

          # Put the real toolchain bin first so xcrun resolves correctly.
          export PATH="${xcodeToolchain}:$PATH"

          # Reproduce the SPM directory layout so swift build finds checkouts.
          mkdir -p .build
          if [ -d "${self}/.build/checkouts" ]; then
            cp -r "${self}/.build/checkouts" .build/checkouts
          fi
        '';

      in
      {
        # ------------------------------------------------------------------ #
        #  Dev shell                                                           #
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
            echo "Build:  swift build"
            echo "Test:   swift test"
            echo "Lint:   swift-format lint --recursive Sources/ Tests/"
          '';
        };

        # ------------------------------------------------------------------ #
        #  Build                                                               #
        # ------------------------------------------------------------------ #
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = "window-thing";
          version = "0.1.0";
          src = ./.;

          # Allow access to the Xcode toolchain and system frameworks.
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
            ${swiftSetup}
            ${swiftBin} build -c release \
              --disable-automatic-resolution \
              2>&1
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp .build/release/WindowThing $out/bin/window-thing
          '';

          meta = {
            description = "macOS window manager with hotkey-driven layouts";
            platforms = pkgs.lib.platforms.darwin;
          };
        };

        # ------------------------------------------------------------------ #
        #  Checks (tests)                                                      #
        # ------------------------------------------------------------------ #
        checks = {
          # Run the full test suite.
          tests = pkgs.stdenvNoCC.mkDerivation {
            name = "window-thing-tests";
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
              ${swiftSetup}
              ${swiftBin} test \
                --disable-automatic-resolution \
                2>&1 | tee test-output.log
              # Propagate test failures
              exit ''${PIPESTATUS[0]}
            '';

            installPhase = ''
              mkdir -p $out
              cp test-output.log $out/
            '';
          };

          # Run swift-format in lint mode (no changes, just check).
          format = pkgs.stdenvNoCC.mkDerivation {
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
        };
      }
    );
}
