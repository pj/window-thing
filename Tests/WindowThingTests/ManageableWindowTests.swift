import Testing
import AppKit
@testable import WindowThingCore

/// Which windows the layout is allowed to move.
///
/// Size and layer checks don't catch menus: an app is free to draw its
/// right-click menu as an ordinary layer-0 window large enough to pass, and
/// several do. The Accessibility subrole is what separates a real window from a
/// menu, popover, sheet or panel.
@Suite("Manageable windows")
struct ManageableWindowTests {

    private let standard = kAXStandardWindowSubrole as String

    @Test("A standard window is managed")
    func standardWindowIsManaged() {
        #expect(WindowManager.isManageable(
            subrole: standard, foundInAXList: true, axListReadable: true))
    }

    @Test("Menus, dialogs and panels are not")
    func nonStandardSubrolesAreSkipped() {
        for subrole in [
            kAXDialogSubrole as String,
            kAXSystemDialogSubrole as String,
            kAXFloatingWindowSubrole as String,
            kAXSystemFloatingWindowSubrole as String,
            "AXUnknown",
        ] {
            #expect(!WindowManager.isManageable(
                subrole: subrole, foundInAXList: true, axListReadable: true),
                "\(subrole) should not be placed by a layout")
        }
    }

    @Test("A window with no subrole at all is not managed")
    func missingSubroleIsSkipped() {
        #expect(!WindowManager.isManageable(
            subrole: nil, foundInAXList: true, axListReadable: true))
    }

    @Test("A window Accessibility doesn't list is not managed")
    func unlistedWindowIsSkipped() {
        // This is the case that catches the right-click menu: CoreGraphics
        // reports it as an on-screen window, the app does not expose it as one.
        #expect(!WindowManager.isManageable(
            subrole: nil, foundInAXList: false, axListReadable: true))
    }

    @Test("An app that lists no windows at all loses every window")
    func emptyAXListDropsEverything() {
        // Why the window lookup cannot stop at kAXWindows. Finder answers that
        // attribute with success and an empty array while its window sits in
        // AXChildren as an ordinary resizable AXWindow. An empty list is
        // readable, so this verdict is reached rather than the fail-open one
        // below — every Finder window was classified as a popover and silently
        // dropped from every layout, with no error raised anywhere.
        //
        // The verdict is correct given its inputs. The fix belongs where the
        // list is gathered, so keep this pinned: it is what makes an
        // enumeration bug fatal rather than merely lossy.
        #expect(!WindowManager.isManageable(
            subrole: nil, foundInAXList: false, axListReadable: true))
        #expect(!WindowManager.isManageable(
            subrole: kAXStandardWindowSubrole as String,
            foundInAXList: false, axListReadable: true))
    }

    // MARK: - Failing open

    @Test("An app that can't be asked keeps all of its windows")
    func unreadableAppFailsOpen() {
        // Permissions, or an app that simply isn't answering. Treating silence
        // as "not a window" would drop every window of an unresponsive app out
        // of every layout — far worse than occasionally moving a menu.
        #expect(WindowManager.isManageable(
            subrole: nil, foundInAXList: false, axListReadable: false))
        #expect(WindowManager.isManageable(
            subrole: "AXUnknown", foundInAXList: true, axListReadable: false))
    }

    @Test("Readability decides before anything else does")
    func readabilityTakesPrecedence() {
        // The parameters can disagree — an unreadable list cannot meaningfully
        // report a subrole — and the fail-open case must win regardless.
        for subrole in [standard, "AXUnknown", nil] {
            for found in [true, false] {
                #expect(WindowManager.isManageable(
                    subrole: subrole, foundInAXList: found, axListReadable: false),
                    "an unreadable app should keep its windows")
            }
        }
    }
}
