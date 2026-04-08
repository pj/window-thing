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
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Swift uses system toolchain on macOS
            # These are supporting tools
            swift-format
            swiftlint

            # YAML parsing dependency
            libyaml

            # Build tools
            xcbuild

            # Useful dev tools
            jq
            yq

          ];

          shellHook = ''
            echo "WindowThing Development Environment"
            echo "Swift version: $(swift --version 2>/dev/null | head -1 || echo 'Use system Swift')"
            echo ""
            echo "Build commands:"
            echo "  swift build        - Build the project"
            echo "  swift build -c release - Build release version"
            echo "  swift run          - Run the app"
            echo "  ./scripts/build.sh - Build the .app bundle"
          '';

          # Ensure we can find system frameworks
          NIX_LDFLAGS = "-F/System/Library/Frameworks -framework Cocoa -framework Carbon -framework ApplicationServices";
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "window-thing";
          version = "0.1.0";
          src = ./.;

          buildInputs = with pkgs; [
            darwin.apple_sdk.frameworks.Cocoa
            darwin.apple_sdk.frameworks.Carbon
            darwin.apple_sdk.frameworks.ApplicationServices
            darwin.apple_sdk.frameworks.CoreGraphics
            libyaml
          ];

          buildPhase = ''
            swift build -c release
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp .build/release/WindowThing $out/bin/
          '';
        };
      }
    );
}
