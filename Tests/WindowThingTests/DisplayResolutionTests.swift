import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Display-to-Layout-Key Resolution")
struct DisplayResolutionTests {

    // MARK: - $PRIMARY Resolution

    @Test("$PRIMARY resolves to isMain display")
    func primaryResolvesToMain() {
        // Two displays: first is NOT main, second IS main
        let displays = [
            Display.testDisplay(id: 0, name: "External Display", width: 1920, height: 1080, isMain: false),
            Display.testDisplay(id: 1, name: "Main Monitor", x: 1920, width: 2560, height: 1440, isMain: true)
        ]
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode")
            ])]
        )
        let placements = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: TestFixtures.typicalWindows
        )
        // VSCode should be placed on the main display (starts at x: 1920, width: 2560)
        let vscodePlacement = placements.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscodePlacement != nil)
        #expect(vscodePlacement!.targetFrame.x == 1920)
        #expect(vscodePlacement!.targetFrame.width == 2560)
    }

    @Test("$PRIMARY resolution changes when main display changes")
    func primaryFollowsMainChange() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode")
            ])]
        )

        // First: main is display A
        let displaysA = [
            Display.testDisplay(id: 0, name: "Display A", width: 1920, height: 1080, isMain: true),
            Display.testDisplay(id: 1, name: "Display B", x: 1920, width: 1920, height: 1080, isMain: false)
        ]
        let placementsA = LayoutCalculator.calculatePlacements(
            layout: layout, displays: displaysA, windows: TestFixtures.typicalWindows
        )
        let vscodeA = placementsA.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscodeA!.targetFrame.x == 0)

        // Second: main is display B
        let displaysB = [
            Display.testDisplay(id: 0, name: "Display A", width: 1920, height: 1080, isMain: false),
            Display.testDisplay(id: 1, name: "Display B", x: 1920, width: 1920, height: 1080, isMain: true)
        ]
        let placementsB = LayoutCalculator.calculatePlacements(
            layout: layout, displays: displaysB, windows: TestFixtures.typicalWindows
        )
        let vscodeB = placementsB.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscodeB!.targetFrame.x == 1920)
    }

    // MARK: - Name Matching

    @Test("Named display key uses exact case-sensitive matching")
    func caseSensitiveMatching() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                "External Display": .pinned(app: "Safari")
            ])]
        )
        // Display name is lowercase — should NOT match "External Display"
        let displays = [
            Display.testDisplay(id: 0, name: "Main Display", width: 1920, height: 1080, isMain: true),
            Display.testDisplay(id: 1, name: "external display", x: 1920, width: 1920, height: 1080, isMain: false)
        ]

        // The screen set references "External Display" which doesn't exist (case mismatch)
        // matchingScreenSet should not match this screen set since it requires "External Display"
        let match = layout.matchingScreenSet(for: displays)
        // It should still match (since $PRIMARY matches) but won't use the external layout
        // Actually: screenSetNames = {"External Display"}, displayNames = {"Main Display", "external display"}
        // "External Display" is NOT a subset of displayNames, so this screen set should NOT match
        #expect(match == nil)
    }

    @Test("Multiple displays none matching any non-primary key")
    func noNamedKeysMatch() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([.empty(percentage: 50), .stackAll(percentage: 50)]),
                "Unknown Monitor": .pinned(app: "Safari")
            ])]
        )
        let displays = [
            Display.testDisplay(id: 0, name: "Main Display", width: 1920, height: 1080, isMain: true),
            Display.testDisplay(id: 1, name: "Side Monitor", x: 1920, width: 1920, height: 1080, isMain: false)
        ]
        // "Unknown Monitor" not in display list → screen set doesn't match
        let match = layout.matchingScreenSet(for: displays)
        #expect(match == nil)
    }

    @Test("Display with no isMain flag degrades gracefully")
    func noMainDisplay() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode")
            ])]
        )
        // All displays have isMain: false
        let displays = [
            Display.testDisplay(id: 0, name: "Display A", width: 1920, height: 1080, isMain: false),
            Display.testDisplay(id: 1, name: "Display B", x: 1920, width: 1920, height: 1080, isMain: false)
        ]
        // Should not crash; $PRIMARY won't resolve so windows remain unplaced or use fallback
        let placements = LayoutCalculator.calculatePlacements(
            layout: layout, displays: displays, windows: TestFixtures.typicalWindows
        )
        // With no main display, $PRIMARY can't resolve; the calculator should handle gracefully
        // (may place nothing for pinned, but remaining windows should still get stacked somewhere)
        // At minimum: no crash
        _ = placements
    }

    @Test("$PRIMARY plus named display both resolve correctly")
    func primaryAndNamedResolve() {
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode"),
                "External Display": .pinned(app: nil, bundleId: "com.apple.Safari")
            ])]
        )
        let placements = LayoutCalculator.calculatePlacements(
            layout: layout, displays: TestFixtures.dualDisplays, windows: TestFixtures.typicalWindows
        )
        // VSCode on main (x: 0)
        let vscode = placements.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode != nil)
        #expect(vscode!.targetFrame.x == 0)

        // Safari on external (x: 1920)
        let safari = placements.first { $0.window.bundleId == "com.apple.Safari" }
        #expect(safari != nil)
        #expect(safari!.targetFrame.x == 1920)
    }

    @Test("Exact name match with special characters in display name")
    func specialCharactersInName() {
        let displayName = "LG HDR 4K (2)"
        let displays = [
            Display.testDisplay(id: 0, name: "Main Display", width: 1920, height: 1080, isMain: true),
            Display.testDisplay(id: 1, name: displayName, x: 1920, width: 3840, height: 2160, isMain: false)
        ]
        let layout = Layout(
            name: "Test",
            screenSets: [ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                displayName: .pinned(app: nil, bundleId: "com.apple.Safari")
            ])]
        )
        let match = layout.matchingScreenSet(for: displays)
        #expect(match != nil)
        #expect(match!.layouts[displayName] != nil)

        let placements = LayoutCalculator.calculatePlacements(
            layout: layout, displays: displays, windows: TestFixtures.typicalWindows
        )
        let safari = placements.first { $0.window.bundleId == "com.apple.Safari" }
        #expect(safari != nil)
        #expect(safari!.targetFrame.x == 1920)
        #expect(safari!.targetFrame.width == 3840)
    }
}
