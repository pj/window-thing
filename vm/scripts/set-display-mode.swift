#!/usr/bin/env swift
//
// Switch the VM's main display to a given logical resolution.
//
// `tart set --display` sizes the virtual display, but the macOS guest keeps its
// own mode selection and stays at whatever it booted with. This picks the
// matching CGDisplayMode inside the guest, preferring the HiDPI (2x) variant so
// captured screenshots are Retina-crisp.
//
// Usage: swift set-display-mode.swift <width> <height>

import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3,
      let targetWidth = Int(args[1]),
      let targetHeight = Int(args[2]) else {
    print("usage: set-display-mode.swift <width> <height>")
    exit(2)
}

let display = CGMainDisplayID()

func describeCurrent() -> String {
    "\(CGDisplayPixelsWide(display))x\(CGDisplayPixelsHigh(display))"
}

if CGDisplayPixelsWide(display) == targetWidth, CGDisplayPixelsHigh(display) == targetHeight {
    print("already at \(describeCurrent())")
    exit(0)
}

let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
guard let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else {
    print("error: could not enumerate display modes")
    exit(1)
}

let candidates = modes.filter { $0.width == targetWidth && $0.height == targetHeight }
guard let mode = candidates.max(by: { $0.pixelWidth < $1.pixelWidth }) else {
    let available = Set(modes.map { "\($0.width)x\($0.height)" }).sorted()
    print("error: no \(targetWidth)x\(targetHeight) mode. Available: \(available.joined(separator: ", "))")
    exit(1)
}

var config: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&config) == .success else {
    print("error: CGBeginDisplayConfiguration failed")
    exit(1)
}
CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
    print("error: CGCompleteDisplayConfiguration failed")
    exit(1)
}

// The WindowServer needs a moment before the new geometry is reported.
Thread.sleep(forTimeInterval: 2)
print("set \(mode.width)x\(mode.height) (backing \(mode.pixelWidth)x\(mode.pixelHeight)) — now \(describeCurrent())")
