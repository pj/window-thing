import Testing
import CoreGraphics
@testable import WindowThingCore

@Suite("Layout Manager Tests")
struct LayoutManagerTests {

    // MARK: - Layout Loading

    @Test("Load layouts from config")
    func loadLayoutsFromConfig() {
        let mockWindowManager = MockWindowManager()
        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let config = AppConfig(
            activationHotKey: .default,
            layouts: [
                TestFixtures.halfSplitLayout,
                TestFixtures.codingLayout
            ],
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )

        layoutManager.loadLayouts(from: config)

        #expect(layoutManager.layouts.count == 2)
        #expect(layoutManager.layouts[0].name == "Half Split")
        #expect(layoutManager.layouts[1].name == "Coding")
    }

    @Test("Load layouts applies default layout")
    func loadLayoutsAppliesDefaultLayout() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let config = AppConfig(
            activationHotKey: .default,
            layouts: [TestFixtures.halfSplitLayout, TestFixtures.codingLayout],
            defaultLayoutName: "Coding",
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )

        layoutManager.loadLayouts(from: config)

        #expect(layoutManager.currentLayout != nil)
        #expect(layoutManager.currentLayout?.name == "Coding")
    }

    @Test("Load layouts with quick key as default name")
    func loadLayoutsWithQuickKeyAsDefaultName() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let config = AppConfig(
            activationHotKey: .default,
            layouts: [TestFixtures.halfSplitLayout],
            defaultLayoutName: "1",
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )

        layoutManager.loadLayouts(from: config)

        #expect(layoutManager.currentLayout != nil)
        #expect(layoutManager.currentLayout?.name == "Half Split")
    }

    // MARK: - Layout Application

    @Test("Apply layout sets current layout")
    func applyLayoutSetsCurrentLayout() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.codingLayout)
        layoutManager.waitForPendingApply()

        #expect(layoutManager.currentLayout != nil)
        #expect(layoutManager.currentLayout?.name == "Coding")
    }

    @Test("Apply layout calls set window frame")
    func applyLayoutCallsSetWindowFrame() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.codingLayout)
        layoutManager.waitForPendingApply()

        // With new stack behavior: 3 pinned + 2 remaining = 5 total
        #expect(mockWindowManager.setWindowFrameCalls.count == 5)
    }

    @Test("Apply layout correct placements")
    func applyLayoutCorrectPlacements() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.codingLayout)
        layoutManager.waitForPendingApply()

        let vscodeCall = mockWindowManager.setWindowFrameCalls.first {
            $0.pid == TestFixtures.codeWindow.pid
        }
        #expect(vscodeCall != nil)
        #expect(vscodeCall?.frame.x == 0)
        #expect(vscodeCall?.frame.width == 1152)
        #expect(vscodeCall?.frame.height == 1080)
    }

    @Test("Apply layout no matching windows")
    func applyLayoutNoMatchingWindows() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = []

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.codingLayout)
        layoutManager.waitForPendingApply()

        #expect(mockWindowManager.setWindowFrameCalls.count == 0)
    }

    @Test("Apply layout dual display")
    func applyLayoutDualDisplay() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.dualDisplays
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.dualDisplayLayout)
        layoutManager.waitForPendingApply()

        // All 5 windows should be placed (3 pinned + 2 remaining on main)
        #expect(mockWindowManager.setWindowFrameCalls.count == 5)

        let vscodeCall = mockWindowManager.setWindowFrameCalls.first {
            $0.pid == TestFixtures.codeWindow.pid
        }
        #expect(vscodeCall?.frame.x == 0)

        let terminalCall = mockWindowManager.setWindowFrameCalls.first {
            $0.pid == TestFixtures.terminalWindow.pid
        }
        #expect(terminalCall?.frame.x == 1920)  // External Display starts at 1920
    }

    // MARK: - Quick Key Lookup

    @Test("Get layout by quick key")
    func getLayoutByQuickKey() {
        let mockWindowManager = MockWindowManager()
        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let config = AppConfig(
            activationHotKey: .default,
            layouts: [TestFixtures.halfSplitLayout, TestFixtures.codingLayout],
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )
        layoutManager.loadLayouts(from: config)

        let layout = layoutManager.getLayoutByQuickKey("c")

        #expect(layout != nil)
        #expect(layout?.name == "Coding")
    }

    @Test("Get layout by quick key not found")
    func getLayoutByQuickKeyNotFound() {
        let mockWindowManager = MockWindowManager()
        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let config = AppConfig(
            activationHotKey: .default,
            layouts: [TestFixtures.halfSplitLayout],
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )
        layoutManager.loadLayouts(from: config)

        let layout = layoutManager.getLayoutByQuickKey("z")

        #expect(layout == nil)
    }

    @Test("Apply layout by quick key success")
    func applyLayoutByQuickKeySuccess() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let config = AppConfig(
            activationHotKey: .default,
            layouts: [TestFixtures.codingLayout],
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )
        layoutManager.loadLayouts(from: config)

        let result = layoutManager.applyLayoutByQuickKey("c")

        #expect(result == true)
        #expect(layoutManager.currentLayout?.name == "Coding")
    }

    @Test("Apply layout by quick key failure")
    func applyLayoutByQuickKeyFailure() {
        let mockWindowManager = MockWindowManager()
        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        let config = AppConfig(
            activationHotKey: .default,
            layouts: [TestFixtures.codingLayout],
            overlayOpacity: 0.9,
            overlayBackgroundColor: "#000",
            highlightColor: "#fff",
            pollIntervalMs: 500,
            minimumWindowWidth: 200,
            minimumWindowHeight: 200
        )
        layoutManager.loadLayouts(from: config)

        let result = layoutManager.applyLayoutByQuickKey("z")

        #expect(result == false)
    }

    // MARK: - Stack Layout

    @Test("Apply stack layout")
    func applyStackLayout() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.stackLayout)
        layoutManager.waitForPendingApply()

        // With new behavior: Stack collects ALL remaining windows (5 total)
        #expect(mockWindowManager.setWindowFrameCalls.count == 5)

        let safariCall = mockWindowManager.setWindowFrameCalls.first {
            $0.pid == TestFixtures.safariWindow.pid
        }
        let finderCall = mockWindowManager.setWindowFrameCalls.first {
            $0.pid == TestFixtures.finderWindow.pid
        }

        #expect(safariCall != nil)
        #expect(finderCall != nil)
        // All windows should be stacked at the same location
        #expect(safariCall?.frame == finderCall?.frame)
    }

    // MARK: - Edge Cases

    @Test("Apply layout no displays")
    func applyLayoutNoDisplays() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = []
        mockWindowManager.windows = TestFixtures.typicalWindows

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.codingLayout)
        layoutManager.waitForPendingApply()

        #expect(mockWindowManager.setWindowFrameCalls.count == 0)
    }

    @Test("Apply layout set window frame fails")
    func applyLayoutSetWindowFrameFails() {
        let mockWindowManager = MockWindowManager()
        mockWindowManager.displays = TestFixtures.singleDisplay
        mockWindowManager.windows = TestFixtures.typicalWindows
        mockWindowManager.setWindowFrameReturnValue = false

        let layoutManager = LayoutManager(windowManager: mockWindowManager)

        layoutManager.applyLayout(TestFixtures.codingLayout)
        layoutManager.waitForPendingApply()

        // With new stack behavior: 3 pinned + 2 remaining = 5 total
        // Even if setWindowFrame fails, we still try to set all windows
        #expect(mockWindowManager.setWindowFrameCalls.count == 5)
    }
}
