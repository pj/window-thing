import Testing
@testable import WindowThingCore

/// Sparkle updates by replacing the .app on disk, so it only works where that
/// bundle is writable. These pin down which installs get an update check.
@Suite("Update channel")
struct UpdateChannelTests {

    @Test("A normal install updates through Sparkle")
    func applicationsInstallUsesSparkle() {
        let channel = UpdateChannelResolver.channel(forBundlePath: "/Applications/WindowThing.app")

        #expect(channel == .sparkle)
        #expect(channel.supportsInAppUpdates)
        #expect(channel.unavailableReason == nil)
    }

    @Test("A copy in the nix store is managed by nix")
    func nixStoreInstallIsManaged() {
        // /nix/store is read-only and root-owned, so Sparkle could only fail.
        let channel = UpdateChannelResolver.channel(
            forBundlePath: "/nix/store/a8g00is5kvlci3vgf2pa7yasy8k6rbb6-window-thing-0.1.1/Applications/WindowThing.app"
        )

        #expect(channel == .managed(by: "nix"))
        #expect(!channel.supportsInAppUpdates)
        #expect(channel.unavailableReason == "Updates managed by nix")
    }

    @Test("A bare executable has no bundle to replace")
    func bareBinaryIsUnpackaged() {
        let channel = UpdateChannelResolver.channel(forBundlePath: "/Users/me/window_thing/.build/debug")

        #expect(channel == .unpackaged)
        #expect(!channel.supportsInAppUpdates)
    }

    @Test("No bundle path at all is unpackaged")
    func missingPathIsUnpackaged() {
        #expect(UpdateChannelResolver.channel(forBundlePath: nil) == .unpackaged)
    }

    @Test("A path merely containing nix/store is not treated as managed")
    func onlyLeadingPrefixCounts() {
        // The check is a prefix, not a substring — a user directory that happens
        // to mention the store must still get a working update check.
        let channel = UpdateChannelResolver.channel(
            forBundlePath: "/Users/me/nix/store/WindowThing.app"
        )

        #expect(channel == .sparkle)
    }
}
