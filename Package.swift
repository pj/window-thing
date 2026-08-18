// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowThing",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Core library with all the logic
        .target(
            name: "WindowThingCore",
            dependencies: [
                "Yams",
            ],
            path: "Sources/WindowThingCore"
        ),
        // Executable app
        .executableTarget(
            name: "WindowThing",
            dependencies: [
                "WindowThingCore",
                "WindowThingViewModel",
                "HotKey",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/WindowThing",
            linkerSettings: [
                // Sparkle ships as an XCFramework that has to be embedded in the
                // .app; SwiftPM does not embed frameworks for executables, so
                // scripts/package.sh copies it into Contents/Frameworks and this
                // rpath is what lets the binary find it there at runtime.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // ViewModel library (testable, no SwiftUI)
        .target(
            name: "WindowThingViewModel",
            dependencies: ["WindowThingCore"],
            path: "Sources/WindowThingViewModel"
        ),
        // Generic layout canvas — no domain dependencies
        .target(
            name: "WindowThingCanvas",
            dependencies: [],
            path: "Sources/WindowThingCanvas"
        ),
        // Standalone demo app for the canvas
        .executableTarget(
            name: "WindowThingCanvasDemo",
            dependencies: ["WindowThingCanvas"],
            path: "Sources/WindowThingCanvasDemo"
        ),
        // Test target
        .testTarget(
            name: "WindowThingTests",
            dependencies: ["WindowThingCore", "Yams"],
            path: "Tests/WindowThingTests"
        ),
        // ViewModel tests
        .testTarget(
            name: "WindowThingViewModelTests",
            dependencies: ["WindowThingViewModel", "WindowThingCore"],
            path: "Tests/WindowThingViewModelTests"
        ),
        // Canvas tests (ViewInspector + Swift Testing)
        .testTarget(
            name: "WindowThingCanvasTests",
            dependencies: [
                "WindowThingCanvas",
                .product(name: "ViewInspector", package: "ViewInspector"),
            ],
            path: "Tests/WindowThingCanvasTests"
        ),
    ]
)
