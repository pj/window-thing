import Testing
@testable import WindowThingCore

/// A layout has exactly one stack across all of its displays — it is the single
/// place unpinned windows land. Two stacks means windows land in one of them
/// arbitrarily; none means they have nowhere to go.
@Suite("One stack per screen set")
struct StackInvariantTests {

    @Test("A screen set reports which monitors hold a stack")
    func reportsStackKeys() {
        let set = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .pinned(app: "Mail")
        ])

        #expect(set.containsStack)
        #expect(set.stackKeys == [ScreenConfig.primaryKey])
    }

    @Test("A screen set with no stack anywhere reports none")
    func reportsNoStack() {
        let set = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .pinned(app: "Mail"),
            "External": .empty()
        ])

        #expect(!set.containsStack)
        #expect(set.stackKeys.isEmpty)
    }

    @Test("A surplus stack on another monitor is demoted to empty")
    func demotesSurplusStack() {
        let set = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .stackAll()
        ])

        let fixed = set.deduplicatingStacks()

        #expect(fixed.stackKeys == [ScreenConfig.primaryKey])
        #expect(fixed.layouts["External"]?.type == .empty)
    }

    @Test("The primary display keeps the stack when both have one")
    func primaryWinsTheStack() {
        let set = ScreenConfig(layouts: [
            "External": .stackAll(),
            ScreenConfig.primaryKey: .stackAll()
        ])

        #expect(set.deduplicatingStacks().stackKeys == [ScreenConfig.primaryKey])
    }

    @Test("A nested surplus stack is demoted in place, keeping its size")
    func demotesNestedStack() {
        let set = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .stackAll(),
            "External": .columns([
                .pinned(app: "Mail", percentage: 70),
                .stackAll(percentage: 30)
            ])
        ])

        let fixed = set.deduplicatingStacks()
        let external = fixed.layouts["External"]

        #expect(fixed.stackKeys == [ScreenConfig.primaryKey])
        #expect(external?.columns?[1].type == .empty)
        // The pane keeps its share of the screen; only its role changed.
        #expect(external?.columns?[1].percentage == 30)
    }

    @Test("A screen set with a single stack is left alone")
    func leavesValidSetsAlone() {
        let set = ScreenConfig(layouts: [
            ScreenConfig.primaryKey: .columns([.stackAll(percentage: 60), .empty(percentage: 40)]),
            "External": .pinned(app: "Mail")
        ])

        #expect(set.deduplicatingStacks() == set)
    }

    @Test("Repair covers every screen set of a layout")
    func repairsWholeLayout() {
        let layout = Layout(name: "Test", screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                "External": .stackAll()
            ]),
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])

        let fixed = layout.deduplicatingStacks()

        #expect(fixed.screenSets[0].stackKeys.count == 1)
        #expect(fixed.screenSets[1].stackKeys.count == 1)
    }

    @Test("Loading a config repairs a layout that already has two stacks")
    func loadRepairsExistingConfigs() {
        // A config written by an older build — or edited by hand — can hold two
        // stacks. Loading has to fix it, since nothing else will.
        let broken = Layout(name: "Broken", screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stackAll(),
                "External": .stackAll()
            ])
        ])
        let manager = LayoutManager(windowManager: MockWindowManager())

        manager.loadLayouts(from: AppConfig(
            activationHotKey: .default,
            layouts: [broken],
            overlayOpacity: 1,
            overlayBackgroundColor: "#000000",
            highlightColor: "#ffffff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        ))

        #expect(manager.layouts[0].screenSets[0].stackKeys == [ScreenConfig.primaryKey])
    }

    @Test("Adding a display to a set that has a stack adds an empty pane")
    func addingDisplayDoesNotAddASecondStack() {
        // The bug: `addingDisplay` defaults to a full stack, so adding a second
        // monitor silently gave the layout two.
        let layout = Layout(name: "Test", screenSets: [
            ScreenConfig(layouts: [ScreenConfig.primaryKey: .stackAll()])
        ])

        let updated = layout.addingDisplay(
            key: "External", defaultNode: .empty(), toScreenSetAt: 0
        )

        #expect(updated?.screenSets[0].stackKeys.count == 1)
        #expect(updated?.screenSets[0].layouts["External"]?.type == .empty)
    }
}
