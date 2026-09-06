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
        // A mão do serviço sobre o próprio registro (SMAppService.unregister),
        // chamada pelo serviço quando o pacote vai para o Lixo (0.8.3).
        .executable(name: "river-bridge-servico", targets: ["RiverBridgeServico"]),
        // O widget do macOS (0.10.0): o executável do .appex que o empacotador
        // monta em Contents/PlugIns. Um alvo do SwiftPM basta (medido em
        // 2026-09-06: `@main struct: Widget` compila e liga o WidgetKit nativo).
        .executable(name: "RiverBridgeWidget", targets: ["RiverBridgeWidget"]),
    ],
    targets: [
        .target(name: "RiverBridgeCore"),
        .executableTarget(
            name: "RiverBridgeApp",
            dependencies: ["RiverBridgeCore"]
        ),
        .executableTarget(name: "RiverBridgeServico"),
        .executableTarget(
            name: "RiverBridgeWidget",
            dependencies: ["RiverBridgeCore"]
        ),
        .testTarget(
            name: "RiverBridgeCoreTests",
            dependencies: ["RiverBridgeCore"]
        ),
    ]
)
