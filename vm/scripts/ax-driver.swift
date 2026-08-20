#!/usr/bin/env swift
//
// ax-driver.swift — drive WindowThing's interface through the Accessibility API.
//
//   swift ax-driver.swift list
//   swift ax-driver.swift press "Delete layout Scratch"
//   swift ax-driver.swift exists "Delete layout Scratch"
//   swift ax-driver.swift set-text "Layout name" "New Name"
//   swift ax-driver.swift wait "Delete Layout" [seconds]
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
    fail("usage: ax-driver.swift <list|press|exists|set-text|wait> [arguments]")
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
