// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Main actor by default for the app and CLI. Expressed as a compiler flag because tools-version 6.2
// (`.defaultIsolation`) makes `swift test` lose the Swift Testing macro plugin with Command Line Tools.
let mainActorByDefault: [SwiftSetting] = [.unsafeFlags(["-default-isolation", "MainActor"])]

// With Command Line Tools only, SwiftPM sometimes forgets the Swift Testing macro plugin ("plugin for module
// 'TestingMacros' not found"). Point the test target at it explicitly when the CLT copy exists.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])] : []

let package = Package(
    name: "Dylan",
    defaultLocalization: "id",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Dylan", targets: ["Dylan"]),
        .executable(name: "dylan-cli", targets: ["DylanCLI"]),
        .executable(name: "dylan-fan-helper", targets: ["DylanFanHelper"]),
    ],
    targets: [
        // Pure logic, no AppKit. Everything here has unit tests.
        .target(name: "DylanCore"),
        // AppleSMC access, shared by the app (read) and the root fan helper (write). Kept tiny on purpose:
        // the helper runs as root and links nothing else.
        .target(name: "SMCKit", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "DylanFanHelper", dependencies: ["SMCKit"], swiftSettings: mainActorByDefault),
        .executableTarget(
            name: "Dylan",
            dependencies: ["DylanCore", "SMCKit"],
            exclude: ["Resources"],
            // AppKit app: main actor by default; background work opts out explicitly.
            swiftSettings: mainActorByDefault,
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("MapKit"),
                .linkedFramework("OpenDirectory"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // The CLI ships as Dylan.app/Contents/Helpers/dylan. It cannot sit next to the app binary in
        // Contents/MacOS because "Dylan" and "dylan" are the same name on a case-insensitive disk.
        .executableTarget(name: "DylanCLI", dependencies: ["DylanCore"], swiftSettings: mainActorByDefault),
        .testTarget(
            name: "DylanCoreTests",
            dependencies: ["DylanCore", "SMCKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: testSettings
        ),
    ]
)
