#!/usr/bin/env swift
/// create-virtual-display.swift
///
/// Creates one software-only virtual display using CGVirtualDisplay (macOS 13+).
/// The display persists until this process exits.
///
/// Usage:
///   swift vm/scripts/create-virtual-display.swift [width height refreshRate]
///   swift vm/scripts/create-virtual-display.swift 1920 1080 60
///
/// The script prints the display ID on stdout, then waits for SIGTERM/SIGINT.
/// Pipe its output if you need the ID:
///   DISP_ID=$(swift create-virtual-display.swift & echo $!)
///
/// Note: CGVirtualDisplay requires the process to have Screen Recording permission
/// for the display to appear in CGGetActiveDisplayList. In a VM the display is
/// visible without it, but the system may show a permission banner on first use.

import CoreGraphics
import Foundation

// --------------------------------------------------------------------------- //
// Parse args                                                                   //
// --------------------------------------------------------------------------- //
let args = CommandLine.arguments
let width  = args.count > 1 ? UInt32(args[1]) ?? 1920 : 1920
let height = args.count > 2 ? UInt32(args[2]) ?? 1080 : 1080
let refresh = args.count > 3 ? Double(args[3]) ?? 60.0 : 60.0

// --------------------------------------------------------------------------- //
// Create descriptor                                                             //
// --------------------------------------------------------------------------- //
guard let descriptor = CGVirtualDisplayDescriptor() else {
    fputs("ERROR: CGVirtualDisplayDescriptor() returned nil — requires macOS 13+\n", stderr)
    exit(1)
}

descriptor.name = "WindowThing Test Display"
descriptor.maxPixelsWide = width
descriptor.maxPixelsHigh = height
descriptor.sizeInMillimeters = CGSize(width: 530, height: 300)  // approx 23"
descriptor.productID = 0x1234
descriptor.vendorID  = 0x5678
descriptor.serialNum = 0x0001

// --------------------------------------------------------------------------- //
// Create settings (the active resolution)                                      //
// --------------------------------------------------------------------------- //
guard let settings = CGVirtualDisplaySettings() else {
    fputs("ERROR: CGVirtualDisplaySettings() returned nil\n", stderr)
    exit(1)
}

settings.hiDPI = 0  // 1x — set to 1 for HiDPI/Retina
let mode = CGVirtualDisplayMode(width: width, height: height, refreshRate: refresh)
settings.modes = [mode]

// --------------------------------------------------------------------------- //
// Instantiate                                                                   //
// --------------------------------------------------------------------------- //
guard let display = CGVirtualDisplay(descriptor: descriptor) else {
    fputs("ERROR: CGVirtualDisplay(descriptor:) returned nil\n", stderr)
    exit(1)
}

let result = display.apply(settings)
guard result == .success else {
    fputs("ERROR: apply(settings) failed with \(result.rawValue)\n", stderr)
    exit(1)
}

print("Virtual display created: ID=\(display.displayID) \(width)x\(height)@\(Int(refresh))Hz")
fflush(stdout)

// --------------------------------------------------------------------------- //
// Keep alive until signal                                                       //
// --------------------------------------------------------------------------- //
let sema = DispatchSemaphore(value: 0)

signal(SIGINT)  { _ in sema.signal() }
signal(SIGTERM) { _ in sema.signal() }

sema.wait()

print("Virtual display removed")
