#!/usr/bin/env swift
//
// ax-driver.swift — drive WindowThing's interface through the Accessibility API.
//
//   swift ax-driver.swift list
//   swift ax-driver.swift press "Delete layout Scratch"
//   swift ax-driver.swift exists "Delete layout Scratch"
//   swift ax-driver.swift set-text "Layout name" "New Name"
//   swift ax-driver.swift type "Layout name" "New Name"
//   swift ax-driver.swift confirm
//   swift ax-driver.swift key escape
//   swift ax-driver.swift value "Search apps and windows"
//   swift ax-driver.swift count "Delete layout "
//   swift ax-driver.swift wait "Delete Layout" [seconds]
//   swift ax-driver.swift gone "Delete Layout" [seconds]
//
// Why Accessibility rather than AppleScript: the VM grants /usr/bin/swift the
// Accessibility permission already, so a script run this way needs no further
// approval. Sending Apple events would additionally need Automation consent for
// the sender/target pair, which is one more thing to arrange in a fresh VM.
//
// Why not System Events: it proved unable to see the layout surface reliably —
// the window sits at the screen-saver level, and `window 1` came and went
// between calls. Reading the tree directly is stable.
//
// Exit status is the point: 0 when the thing asked for happened, 1 when it did
// not, so a shell test can just check it.

import AppKit
import ApplicationServices
import Foundation

let bundleID = "com.windowthing.app"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let app = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == bundleID }) else {
    fail("WindowThing is not running")
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)

func children(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return (value as? [AXUIElement]) ?? []
}

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

/// A control's user-facing name, however the framework chose to expose it.
func label(of element: AXUIElement) -> String? {
    for attribute in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] {
        if let text = string(element, attribute), !text.isEmpty, text != "button" {
            return text
        }
    }
    return nil
}

struct Control {
    let element: AXUIElement
    let role: String
    let label: String
}

/// Every labelled control in the app, depth-first.
func controls() -> [Control] {
    var found: [Control] = []

    func walk(_ element: AXUIElement, depth: Int) {
        guard depth < 60 else { return }   // SwiftUI trees are deep but not endless
        if let role = string(element, kAXRoleAttribute), let name = label(of: element) {
            found.append(Control(element: element, role: role, label: name))
        }
        for child in children(of: element) { walk(child, depth: depth + 1) }
    }

    var windowsValue: CFTypeRef?
    AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
    for window in (windowsValue as? [AXUIElement]) ?? [] { walk(window, depth: 0) }
    return found
}

func control(labelled wanted: String) -> Control? {
    controls().first { $0.label == wanted }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("usage: ax-driver.swift <list|press|exists|value|count|actions|do|set-text|type|key|hotkey|confirm|wait|gone> [arguments]")
}

switch command {
case "list":
    let all = controls()
    print("controls: \(all.count)")
    for item in all { print("  [\(item.role)] \(item.label)") }

case "exists":
    guard arguments.count >= 2 else { fail("exists needs a label") }
    guard control(labelled: arguments[1]) != nil else {
        fail("no control labelled '\(arguments[1])'")
    }
    print("found: \(arguments[1])")

case "press":
    guard arguments.count >= 2 else { fail("press needs a label") }
    guard let target = control(labelled: arguments[1]) else {
        fail("no control labelled '\(arguments[1])'")
    }
    let result = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
    guard result == .success else { fail("pressing '\(arguments[1])' failed: \(result.rawValue)") }
    print("pressed: \(arguments[1])")

case "set-text":
    guard arguments.count >= 3 else { fail("set-text needs a label and a value") }
    guard let target = control(labelled: arguments[1]) else {
        fail("no control labelled '\(arguments[1])'")
    }
    let result = AXUIElementSetAttributeValue(
        target.element, kAXValueAttribute as CFString, arguments[2] as CFTypeRef)
    guard result == .success else { fail("setting '\(arguments[1])' failed: \(result.rawValue)") }
    print("set: \(arguments[1]) = \(arguments[2])")

case "type":
    // Real keystrokes, not AXValue. Setting a SwiftUI TextField's accessibility
    // value does not write through to its binding, so the field looked changed
    // and the model never heard about it. Typing is what a person does and what
    // the binding actually observes.
    //
    // Focus has to be arranged first. The layout surface deliberately does not
    // reclaim key focus when it loses it, so its text field can be on screen and
    // and not first responder — keystrokes then go nowhere at all, silently.
    guard arguments.count >= 3 else { fail("type needs a field label and some text") }
    guard let field = control(labelled: arguments[1]) else {
        fail("no control labelled '\(arguments[1])'")
    }

    app.activate()
    usleep(300_000)
    AXUIElementSetAttributeValue(
        field.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    usleep(300_000)

    var focusedNow: CFTypeRef?
    AXUIElementCopyAttributeValue(
        field.element, kAXFocusedAttribute as CFString, &focusedNow)
    guard (focusedNow as? Bool) == true else {
        fail("could not focus '\(arguments[1])' — typing would go nowhere")
    }

    let typeSource = CGEventSource(stateID: .hidSystemState)
    for character in arguments[2].utf16 {
        var unit = character
        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: typeSource, virtualKey: 0, keyDown: isDown) else { continue }
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            event.post(tap: .cghidEventTap)
        }
        usleep(20_000)
    }
    print("typed: \(arguments[2]) into \(arguments[1])")

case "confirm":
    // Commit a text field. Setting its value does not submit it — SwiftUI's
    // onSubmit runs on Return — so the keystroke has to actually be delivered.
    // Posting it needs Accessibility, which /usr/bin/swift already has here.
    app.activate()
    usleep(200_000)
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
    down?.post(tap: .cghidEventTap)
    usleep(50_000)
    up?.post(tap: .cghidEventTap)
    print("pressed: return")

case "hotkey":
    // The global activation chord, Cmd+Shift+Space by default.
    //
    // This is the only way to reopen the surface *inside the same process*.
    // Relaunching the app would reload config.yaml from disk, which hides
    // exactly the class of bug where the editor's list and the layout manager's
    // have drifted apart — the file is right, and the app forgets anyway.
    // The modifier keys are pressed as their own events, not just declared as
    // flags on the space keystroke. A Carbon global hotkey watches the real
    // modifier state, and a synthetic key that merely claims to be modified
    // does not trigger it.
    let chordSource = CGEventSource(stateID: .hidSystemState)
    let command: CGKeyCode = 0x37
    let shift: CGKeyCode = 0x38
    let space: CGKeyCode = 0x31

    func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(
            keyboardEventSource: chordSource, virtualKey: key, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        usleep(40_000)
    }

    post(command, down: true, flags: .maskCommand)
    post(shift, down: true, flags: [.maskCommand, .maskShift])
    post(space, down: true, flags: [.maskCommand, .maskShift])
    post(space, down: false, flags: [.maskCommand, .maskShift])
    post(shift, down: false, flags: .maskCommand)
    post(command, down: false, flags: [])
    print("hotkey: command-shift-space")

case "actions":
    // What a control will actually respond to. AXPress is not the only one —
    // a context menu is AXShowMenu — and guessing wastes a VM cycle.
    guard arguments.count >= 2 else { fail("actions needs a label") }
    guard let target = control(labelled: arguments[1]) else {
        fail("no control labelled '\(arguments[1])'")
    }
    var names: CFArray?
    AXUIElementCopyActionNames(target.element, &names)
    print(((names as? [String]) ?? []).joined(separator: " "))

case "do":
    // Perform a named action, for the ones that are not a press.
    guard arguments.count >= 3 else { fail("do needs a label and an action") }
    guard let target = control(labelled: arguments[1]) else {
        fail("no control labelled '\(arguments[1])'")
    }
    let result = AXUIElementPerformAction(target.element, arguments[2] as CFString)
    guard result == .success else {
        fail("'\(arguments[2])' on '\(arguments[1])' failed: \(result.rawValue)")
    }
    print("did: \(arguments[2]) on \(arguments[1])")

case "key":
    // A named key, for the ones the interface treats as commands.
    guard arguments.count >= 2 else { fail("key needs a name") }
    let codes: [String: CGKeyCode] = [
        "escape": 0x35, "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33,
    ]
    guard let code = codes[arguments[1].lowercased()] else {
        fail("unknown key '\(arguments[1])' — known: \(codes.keys.sorted().joined(separator: ", "))")
    }
    app.activate()
    usleep(200_000)
    let keySource = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: true)?
        .post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(keyboardEventSource: keySource, virtualKey: code, keyDown: false)?
        .post(tap: .cghidEventTap)
    print("key: \(arguments[1])")

case "value":
    // The label is how a control is addressed; its value is separate, and for a
    // text field it is the contents.
    guard arguments.count >= 2 else { fail("value needs a label") }
    guard let target = control(labelled: arguments[1]) else {
        fail("no control labelled '\(arguments[1])'")
    }
    var raw: CFTypeRef?
    AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString, &raw)
    print((raw as? String) ?? "")

case "count":
    // How many controls mention this — the layout list, the visible windows.
    guard arguments.count >= 2 else { fail("count needs a substring") }
    print(controls().filter { $0.label.contains(arguments[1]) }.count)

case "gone":
    // The opposite of `wait`: succeed once something has disappeared, so a test
    // does not have to guess how long an animation takes.
    guard arguments.count >= 2 else { fail("gone needs a label") }
    let goneTimeout = Double(arguments.count > 2 ? arguments[2] : "5") ?? 5
    let goneDeadline = Date().addingTimeInterval(goneTimeout)
    while Date() < goneDeadline {
        if control(labelled: arguments[1]) == nil {
            print("gone: \(arguments[1])")
            exit(0)
        }
        usleep(200_000)
    }
    fail("'\(arguments[1])' was still there after \(goneTimeout)s")

case "wait":
    guard arguments.count >= 2 else { fail("wait needs a label") }
    let timeout = Double(arguments.count > 2 ? arguments[2] : "5") ?? 5
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if control(labelled: arguments[1]) != nil {
            print("appeared: \(arguments[1])")
            exit(0)
        }
        usleep(200_000)
    }
    fail("'\(arguments[1])' did not appear within \(timeout)s")

default:
    fail("unknown command '\(command)'")
}
