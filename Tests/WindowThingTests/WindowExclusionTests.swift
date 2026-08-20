import Testing
import Foundation
@testable import WindowThingCore

/// Windows the config asks the layout to leave alone.
///
/// The automatic filter catches menus and popovers by their Accessibility
/// subrole. It cannot catch Finder's Get Info window, which is a genuine
/// standard window — movable, resizable, listed — and indistinguishable by any
/// attribute from Activity Monitor or System Settings, which do want placing.
@Suite("Window exclusions")
struct WindowExclusionTests {

    private func window(
        app: String = "Finder", bundle: String? = "com.apple.finder", title: String = ""
    ) -> Window {
        Window(id: 1, title: title, application: app, bundleId: bundle,
               frame: WindowFrame(x: 0, y: 0, width: 400, height: 774), pid: 1)
    }

    // MARK: - Matching

    @Test("Every field given has to match")
    func allFieldsMustMatch() {
        let rule = WindowExclusion(bundleId: "com.apple.finder", titleContains: " Info")

        #expect(rule.matches(window(title: "pauljohnson Info")))
        // Right app, wrong title.
        #expect(!rule.matches(window(title: "Documents")))
        // Right title, wrong app.
        #expect(!rule.matches(window(app: "Preview", bundle: "com.apple.Preview",
                                     title: "notes Info")))
    }

    @Test("Titles and app names match case-insensitively")
    func matchingIsCaseInsensitive() {
        let rule = WindowExclusion(application: "finder", titleContains: " info")
        #expect(rule.matches(window(app: "Finder", title: "pauljohnson Info")))
    }

    @Test("A rule with no fields matches nothing")
    func emptyRuleMatchesNothing() {
        // Otherwise a malformed entry would swallow every window on the system.
        let rule = WindowExclusion()

        #expect(!rule.isMeaningful)
        #expect(!rule.matches(window(title: "anything")))
        #expect(![rule].excludes(window(title: "anything")))
    }

    @Test("A rule on title alone applies to every app")
    func titleOnlyRule() {
        let rule = WindowExclusion(titleContains: "Picture in Picture")
        #expect(rule.matches(window(app: "Safari", bundle: "com.apple.Safari",
                                    title: "Picture in Picture")))
    }

    // MARK: - Defaults

    @Test("Get Info is excluded out of the box")
    func defaultsCatchGetInfo() {
        #expect(WindowExclusion.defaults.excludes(window(title: "pauljohnson Info")))
    }

    @Test("Ordinary Finder windows are untouched by the default")
    func defaultsSpareRealWindows() {
        #expect(!WindowExclusion.defaults.excludes(window(title: "Documents")))
        #expect(!WindowExclusion.defaults.excludes(window(title: "Nix Apps")))
    }

    @Test("The default is scoped to Finder")
    func defaultDoesNotLeakToOtherApps() {
        // "Info" is a common enough word that an unscoped rule would catch
        // unrelated windows.
        #expect(!WindowExclusion.defaults.excludes(
            window(app: "Xcode", bundle: "com.apple.dt.Xcode", title: "Build Info")))
    }

    // MARK: - Configuration

    @Test("Config with no exclusions uses the defaults")
    func absentMeansDefaults() {
        let config = makeConfig(exclusions: nil)
        #expect(config.effectiveExclusions == WindowExclusion.defaults)
    }

    @Test("Config with exclusions replaces the defaults outright")
    func presentReplacesDefaults() {
        // What is in the file is what is in effect — nothing invisible added on
        // top, so a rule can be removed by editing it out.
        let mine = [WindowExclusion(application: "Photos")]
        #expect(makeConfig(exclusions: mine).effectiveExclusions == mine)
    }

    @Test("An empty list turns exclusions off entirely")
    func emptyListDisablesThem() {
        let config = makeConfig(exclusions: [])

        #expect(config.effectiveExclusions.isEmpty)
        #expect(!config.effectiveExclusions.excludes(window(title: "pauljohnson Info")))
    }

    @Test("Rules survive a round trip through the config")
    func rulesAreCodable() throws {
        let rule = WindowExclusion(bundleId: "com.apple.finder", titleContains: " Info")
        let decoded = try JSONDecoder().decode(
            WindowExclusion.self, from: JSONEncoder().encode(rule))

        #expect(decoded == rule)
    }

    private func makeConfig(exclusions: [WindowExclusion]?) -> AppConfig {
        AppConfig(
            activationHotKey: .default, layouts: [], overlayOpacity: 1,
            overlayBackgroundColor: "#000000", highlightColor: "#ffffff",
            pollIntervalMs: 500, minimumWindowWidth: 200, minimumWindowHeight: 200,
            excludedWindows: exclusions
        )
    }
}
