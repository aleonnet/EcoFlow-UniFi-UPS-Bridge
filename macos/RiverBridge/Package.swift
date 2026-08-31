// swift-tools-version: 6.0
// River Bridge — native macOS UI (spec §7A). Core is a testable library;
// the app target holds SwiftUI views. XCUITests arrive with the .xcodeproj
// in ordem 8; until then `swift test` covers Core and views compile via build.
import PackageDescription

let package = Package(
    name: "RiverBridge",
    // Both machines measured at macOS 26.6.2 (2026-08-31) — target the
    // Liquid Glass design language natively, no fallbacks.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "RiverBridgeCore", targets: ["RiverBridgeCore"]),
        .executable(name: "RiverBridge", targets: ["RiverBridgeApp"]),
    ],
    targets: [
        .target(name: "RiverBridgeCore"),
        .executableTarget(
            name: "RiverBridgeApp",
            dependencies: ["RiverBridgeCore"]
        ),
        .testTarget(
            name: "RiverBridgeCoreTests",
            dependencies: ["RiverBridgeCore"]
        ),
    ]
)
