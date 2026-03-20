import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Screen Set Matching Tests")
struct ScreenSetMatchingTests {

    // MARK: - Basic Matching

    @Test("Matching screen set single display primary only")
    func matchingScreenSetSingleDisplayPrimaryOnly() {
        let layout = Layout(
            name: "Simple",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty()
                ])
            ]
        )
        let displays = TestFixtures.singleDisplay

        let result = layout.matchingScreenSet(for: displays)

        #expect(result != nil)
        #expect(result!.layouts.keys.contains(ScreenConfig.primaryKey))
    }

    @Test("Matching screen set dual display primary only")
    func matchingScreenSetDualDisplayPrimaryOnly() {
        let layout = Layout(
            name: "Simple",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty()
                ])
            ]
        )
        let displays = TestFixtures.dualDisplays

        let result = layout.matchingScreenSet(for: displays)

        #expect(result != nil)
    }

    @Test("Matching screen set dual display specific names")
    func matchingScreenSetDualDisplaySpecificNames() {
        let layout = Layout(
            name: "Dual Setup",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty()
                ])
            ]
        )
        let displays = TestFixtures.dualDisplays

        let result = layout.matchingScreenSet(for: displays)

        #expect(result != nil)
        #expect(result!.layouts.keys.contains("External Display"))
    }

    @Test("Matching screen set missing display returns nil")
    func matchingScreenSetMissingDisplayReturnsNil() {
        let layout = Layout(
            name: "Triple Required",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "NonExistent Display": .empty()
                ])
            ]
        )
        let displays = TestFixtures.singleDisplay

        let result = layout.matchingScreenSet(for: displays)

        // Should return nil when required display is missing
        // (fallback to stack on primary handled by LayoutCalculator)
        #expect(result == nil)
    }

    // MARK: - Multiple Screen Sets

    @Test("Matching screen set selects best match")
    func matchingScreenSetSelectsBestMatch() {
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty(),
                    "LG 27UK850": .empty()
                ]),
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty()
                ]),
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty()
                ])
            ]
        )

        let dualResult = layout.matchingScreenSet(for: TestFixtures.dualDisplays)
        #expect(dualResult != nil)
        #expect(dualResult!.layouts.keys.contains("External Display"))

        let singleResult = layout.matchingScreenSet(for: TestFixtures.singleDisplay)
        #expect(singleResult != nil)
    }

    @Test("Matching screen set triple display")
    func matchingScreenSetTripleDisplay() {
        let layout = Layout(
            name: "Triple Setup",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty(),
                    "Left Display": .empty()
                ])
            ]
        )
        let displays = TestFixtures.tripleDisplays

        let result = layout.matchingScreenSet(for: displays)

        #expect(result != nil)
        #expect(result!.layouts.keys.contains("External Display"))
        #expect(result!.layouts.keys.contains("Left Display"))
    }

    // MARK: - Edge Cases

    @Test("Matching screen set empty screen sets")
    func matchingScreenSetEmptyScreenSets() {
        let layout = Layout(name: "Empty", screenSets: [])
        let displays = TestFixtures.singleDisplay

        let result = layout.matchingScreenSet(for: displays)

        #expect(result == nil)
    }

    @Test("Matching screen set empty displays")
    func matchingScreenSetEmptyDisplays() {
        let layout = Layout(
            name: "Simple",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty()
                ])
            ]
        )
        let displays: [Display] = []

        let result = layout.matchingScreenSet(for: displays)

        #expect(result != nil)
    }

    @Test("Matching screen set empty layouts in screen set")
    func matchingScreenSetEmptyLayoutsInScreenSet() {
        let layout = Layout(
            name: "Empty Config",
            screenSets: [
                ScreenConfig(layouts: [:])
            ]
        )
        let displays = TestFixtures.singleDisplay

        let result = layout.matchingScreenSet(for: displays)

        #expect(result != nil)
        #expect(result!.layouts.isEmpty)
    }

    // MARK: - Primary Display Handling

    @Test("Primary key matches main display")
    func primaryKeyMatchesMainDisplay() {
        let layout = Layout(
            name: "Primary Test",
            screenSets: [
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode")
                ])
            ]
        )
        let displays = TestFixtures.dualDisplays

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: TestFixtures.typicalWindows
        )

        // With new behavior: VSCode pinned, remaining 4 windows go fullscreen on main
        #expect(result.count == 5)

        let mainDisplay = displays.first { $0.isMain }!

        // VSCode should be on main display
        let vscode = result.first { $0.window.bundleId == "com.microsoft.VSCode" }
        #expect(vscode?.targetFrame.x == mainDisplay.frame.x)

        // All windows should be on main display
        for placement in result {
            #expect(placement.targetFrame.x == mainDisplay.frame.x)
        }
    }

    @Test("Non-main display not matched by primary")
    func nonMainDisplayNotMatchedByPrimary() {
        let layout = Layout(
            name: "Secondary Only",
            screenSets: [
                ScreenConfig(layouts: [
                    "External Display": .pinned(app: nil, bundleId: "com.microsoft.VSCode")
                ])
            ]
        )
        let displays = TestFixtures.dualDisplays

        let result = LayoutCalculator.calculatePlacements(
            layout: layout,
            displays: displays,
            windows: TestFixtures.typicalWindows
        )

        // With new behavior: No main display in layout, so only VSCode placed
        // (Remaining windows not stacked since there's no main display stack)
        #expect(result.count == 1)

        let externalDisplay = displays.first { $0.name == "External Display" }!
        #expect(result[0].targetFrame.x == externalDisplay.frame.x)
        #expect(result[0].window.bundleId == "com.microsoft.VSCode")
    }

    // MARK: - Screen Set Subset Matching

    @Test("Screen set subset matching")
    func screenSetSubsetMatching() {
        let layout = Layout(
            name: "Subset",
            screenSets: [
                ScreenConfig(layouts: [
                    "External Display": .empty()
                ])
            ]
        )

        let dualResult = layout.matchingScreenSet(for: TestFixtures.dualDisplays)
        #expect(dualResult != nil)

        let tripleResult = layout.matchingScreenSet(for: TestFixtures.tripleDisplays)
        #expect(tripleResult != nil)

        let singleResult = layout.matchingScreenSet(for: TestFixtures.singleDisplay)
        // Single display doesn't have "External Display", so no match
        #expect(singleResult == nil)
    }

    // MARK: - Maximizing Matches

    @Test("Maximize matches prefers more displays")
    func maximizeMatchesPrefersMoreDisplays() {
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                // 2 displays (should be skipped when 3 available)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty()
                ]),
                // 3 displays (should be chosen when 3 available)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty(),
                    "Left Display": .empty()
                ]),
                // 1 display (should be skipped when 3 available)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty()
                ])
            ]
        )

        let result = layout.matchingScreenSet(for: TestFixtures.tripleDisplays)

        #expect(result != nil)
        #expect(result!.layouts.count == 3)
        #expect(result!.layouts.keys.contains(ScreenConfig.primaryKey))
        #expect(result!.layouts.keys.contains("External Display"))
        #expect(result!.layouts.keys.contains("Left Display"))
    }

    @Test("Maximize matches same count prefers first")
    func maximizeMatchesSameCountPrefersFirst() {
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                // First dual-display config
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .pinned(app: "Firefox"),
                    "External Display": .empty()
                ]),
                // Second dual-display config (same count, should be skipped)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .pinned(app: "Safari")
                ])
            ]
        )

        let result = layout.matchingScreenSet(for: TestFixtures.dualDisplays)

        #expect(result != nil)
        // Should be the first one (with Firefox on primary)
        let primaryLayout = result!.layouts[ScreenConfig.primaryKey]
        #expect(primaryLayout?.type == .pinned)
        #expect(primaryLayout?.pinned?.application == "Firefox")
    }

    @Test("Maximize matches skips unavailable displays")
    func maximizeMatchesSkipsUnavailableDisplays() {
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                // Triple display config (should be skipped - not all displays available)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty(),
                    "NonExistent Display": .empty()
                ]),
                // Dual display config (should be chosen)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty()
                ]),
                // Single display config (should be skipped - dual has more matches)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty()
                ])
            ]
        )

        let result = layout.matchingScreenSet(for: TestFixtures.dualDisplays)

        #expect(result != nil)
        #expect(result!.layouts.count == 2)
        #expect(result!.layouts.keys.contains(ScreenConfig.primaryKey))
        #expect(result!.layouts.keys.contains("External Display"))
        #expect(!result!.layouts.keys.contains("NonExistent Display"))
    }

    @Test("Maximize matches counts primary key")
    func maximizeMatchesCountsPrimaryKey() {
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                // Only external display (1 match)
                ScreenConfig(layouts: [
                    "External Display": .empty()
                ]),
                // Primary + external (2 matches - should be chosen)
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty(),
                    "External Display": .empty()
                ])
            ]
        )

        let result = layout.matchingScreenSet(for: TestFixtures.dualDisplays)

        #expect(result != nil)
        #expect(result!.layouts.count == 2)
        #expect(result!.layouts.keys.contains(ScreenConfig.primaryKey))
        #expect(result!.layouts.keys.contains("External Display"))
    }

    @Test("No matching screen set returns nil")
    func noMatchingScreenSetReturnsNil() {
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                // First config (can't match)
                ScreenConfig(layouts: [
                    "NonExistent1": .empty()
                ]),
                // Second config (can't match either)
                ScreenConfig(layouts: [
                    "NonExistent2": .empty()
                ])
            ]
        )

        let result = layout.matchingScreenSet(for: TestFixtures.singleDisplay)

        // Should return nil when no screen sets match
        // (fallback to stack on primary handled by LayoutCalculator)
        #expect(result == nil)
    }

    @Test("Maximize matches with partial overlap")
    func maximizeMatchesWithPartialOverlap() {
        let layout = Layout(
            name: "Adaptive",
            screenSets: [
                // 1 matching + 1 non-matching = invalid, skipped
                ScreenConfig(layouts: [
                    "External Display": .empty(),
                    "NonExistent": .empty()
                ]),
                // 1 matching = valid, chosen
                ScreenConfig(layouts: [
                    "External Display": .empty()
                ]),
                // 0 matching but empty = valid, 0 score
                ScreenConfig(layouts: [
                    ScreenConfig.primaryKey: .empty()
                ])
            ]
        )

        let result = layout.matchingScreenSet(for: TestFixtures.dualDisplays)

        #expect(result != nil)
        // Should choose the one with just "External Display" (1 match)
        // over the one with just $PRIMARY (1 match, but comes later)
        #expect(result!.layouts.count == 1)
        #expect(result!.layouts.keys.contains("External Display"))
    }
}
