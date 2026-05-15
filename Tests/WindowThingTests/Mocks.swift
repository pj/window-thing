import Foundation
import CoreGraphics
import WindowThingCore

// MARK: - Mock Window Manager

public class MockWindowManager: WindowManaging {
    public var displays: [Display] = []
    public var windows: [Window] = []
    public var focusedApplication: Application?

    // Track calls for verification
    public var setWindowFrameCalls: [(pid: pid_t, windowTitle: String?, frame: WindowFrame)] = []
    public var setWindowFrameReturnValue: Bool = true

    public init() {}

    public func getDisplays() -> [Display] {
        return displays
    }

    public func getWindows() -> [Window] {
        return windows
    }

    public func setWindowFrame(pid: pid_t, windowTitle: String?, frame: WindowFrame) -> Bool {
        setWindowFrameCalls.append((pid: pid, windowTitle: windowTitle, frame: frame))
        return setWindowFrameReturnValue
    }

    public func setWindowFrame(pid: pid_t, windowId: CGWindowID, frame: WindowFrame) -> Bool {
        setWindowFrameCalls.append((pid: pid, windowTitle: nil, frame: frame))
        return setWindowFrameReturnValue
    }

    public func getFocusedApplication() -> Application? {
        return focusedApplication
    }
}

// MARK: - Mock Layout Manager

public class MockLayoutManager: LayoutManaging {
    public var layouts: [Layout] = []
    public var savedSetups: [SavedSetup] = []
    public var currentLayout: Layout?
    public var lastUsedLayout: Layout?

    // Call tracking
    public var appliedLayouts: [Layout] = []
    public var updatedLayouts: [Layout] = []
    public var movedWindows: [(Window, CellAddress)] = []

    public init() {}

    public func loadLayouts(from config: AppConfig) {
        layouts = config.layouts
    }

    public func applyLayout(_ layout: Layout) {
        appliedLayouts.append(layout)
        currentLayout = layout
        lastUsedLayout = layout
    }

    public func updateLayout(_ layout: Layout) {
        updatedLayouts.append(layout)
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
        }
    }

    public func saveCurrentSetup(name: String) {}
    public func loadSetup(_ setup: SavedSetup) {}

    public func moveWindow(_ window: Window, toCellAt address: CellAddress, displays: [Display]) throws {
        movedWindows.append((window, address))
    }

    public func cellAddresses(for layout: Layout, displays: [Display]) -> [IndexedCell] {
        CellIndexer.indexCells(layout: layout, displays: displays)
    }
}

// MARK: - Test Helpers

extension Display {
    static func testDisplay(
        id: Int = 0,
        name: String = "Test Display",
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 1920,
        height: CGFloat = 1080,
        isMain: Bool = true
    ) -> Display {
        Display(
            id: id,
            name: name,
            frame: WindowFrame(x: x, y: y, width: width, height: height),
            isMain: isMain
        )
    }
}

extension Window {
    static func testWindow(
        id: CGWindowID = 1,
        title: String = "Test Window",
        application: String = "TestApp",
        bundleId: String? = "com.test.app",
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 800,
        height: CGFloat = 600,
        pid: pid_t = 1234
    ) -> Window {
        Window(
            id: id,
            title: title,
            application: application,
            bundleId: bundleId,
            frame: WindowFrame(x: x, y: y, width: width, height: height),
            pid: pid
        )
    }
}

// MARK: - Test Fixtures

struct TestFixtures {

    // MARK: - Displays

    static let singleDisplay: [Display] = [
        Display.testDisplay(id: 0, name: "Main Display", width: 1920, height: 1080, isMain: true)
    ]

    static let dualDisplays: [Display] = [
        Display.testDisplay(id: 0, name: "Main Display", width: 1920, height: 1080, isMain: true),
        Display.testDisplay(id: 1, name: "External Display", x: 1920, width: 1920, height: 1080, isMain: false)
    ]

    static let tripleDisplays: [Display] = [
        Display.testDisplay(id: 0, name: "Main Display", width: 1920, height: 1080, isMain: true),
        Display.testDisplay(id: 1, name: "External Display", x: 1920, width: 1920, height: 1080, isMain: false),
        Display.testDisplay(id: 2, name: "Left Display", x: -1920, width: 1920, height: 1080, isMain: false)
    ]

    // MARK: - Windows

    static let codeWindow = Window.testWindow(
        id: 1,
        title: "main.swift - WindowThing",
        application: "Code",
        bundleId: "com.microsoft.VSCode",
        pid: 1001
    )

    static let terminalWindow = Window.testWindow(
        id: 2,
        title: "Terminal — zsh",
        application: "Terminal",
        bundleId: "com.apple.Terminal",
        pid: 1002
    )

    static let safariWindow = Window.testWindow(
        id: 3,
        title: "Apple - Apple",
        application: "Safari",
        bundleId: "com.apple.Safari",
        pid: 1003
    )

    static let finderWindow = Window.testWindow(
        id: 4,
        title: "Documents",
        application: "Finder",
        bundleId: "com.apple.finder",
        pid: 1004
    )

    static let slackWindow = Window.testWindow(
        id: 5,
        title: "#general - Slack",
        application: "Slack",
        bundleId: "com.tinyspeck.slackmacgap",
        pid: 1005
    )

    static let typicalWindows: [Window] = [
        codeWindow, terminalWindow, safariWindow, finderWindow, slackWindow
    ]

    // MARK: - Layouts

    static let halfSplitLayout = Layout(
        name: "Half Split",
        quickKey: "1",
        screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .empty(percentage: 50),
                    .empty(percentage: 50)
                ])
            ])
        ]
    )

    static let thirdsLayout = Layout(
        name: "Thirds",
        quickKey: "2",
        screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .empty(percentage: 33.33),
                    .empty(percentage: 33.33),
                    .empty(percentage: 33.34)
                ])
            ])
        ]
    )

    static let codingLayout = Layout(
        name: "Coding",
        quickKey: "c",
        screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .columns([
                    .pinned(app: nil, bundleId: "com.microsoft.VSCode", percentage: 60),
                    .rows([
                        .pinned(app: "Terminal", percentage: 50),
                        .pinned(app: "Safari", percentage: 50)
                    ])
                ])
            ])
        ]
    )

    static let dualDisplayLayout = Layout(
        name: "Dual Setup",
        quickKey: "d",
        screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .pinned(app: nil, bundleId: "com.microsoft.VSCode"),
                "External Display": .columns([
                    .pinned(app: "Terminal", percentage: 50),
                    .pinned(app: "Safari", percentage: 50)
                ])
            ])
        ]
    )

    static let stackLayout = Layout(
        name: "Stack Layout",
        quickKey: "s",
        screenSets: [
            ScreenConfig(layouts: [
                ScreenConfig.primaryKey: .stack([
                    PinnedConfig(application: "Safari", bundleId: nil, windowTitles: nil),
                    PinnedConfig(application: "Finder", bundleId: nil, windowTitles: nil)
                ])
            ])
        ]
    )
}

// MARK: - Mock App Driver

public final class MockAppDriver: AppDriver, @unchecked Sendable {
    public let driverType: String
    public var paneState: AppPaneState
    public var appliedSublayouts: [LayoutNode] = []
    public var focusedPanes: [Int] = []
    public var currentFocusedIndex: Int?

    public init(driverType: String = "mock", paneState: AppPaneState) {
        self.driverType = driverType
        self.paneState = paneState
    }

    public func queryPaneState() async throws -> AppPaneState {
        paneState
    }

    public func applySublayout(_ layout: LayoutNode) async throws {
        appliedSublayouts.append(layout)
    }

    public func focusPane(at index: Int) async throws {
        focusedPanes.append(index)
    }

    public func focusedPaneIndex() async throws -> Int? {
        currentFocusedIndex
    }
}
