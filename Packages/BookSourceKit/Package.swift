// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BookSourceKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "BookSourceModel", targets: ["BookSourceModel"]),
        .library(name: "RuleEngine", targets: ["RuleEngine"]),
        .library(name: "NetworkClient", targets: ["NetworkClient"]),
        .library(name: "WebBookOrchestrator", targets: ["WebBookOrchestrator"]),
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "BookSourceModel"
        ),
        .target(
            name: "RuleEngine",
            dependencies: [
                "BookSourceModel",
                "SwiftSoup"
            ]
        ),
        .target(
            name: "NetworkClient"
        ),
        .target(
            name: "WebBookOrchestrator",
            dependencies: [
                "BookSourceModel",
                "RuleEngine",
                "NetworkClient"
            ]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "BookSourceModel"
            ]
        ),
        .testTarget(
            name: "BookSourceModelTests",
            dependencies: ["BookSourceModel"]
        ),
        .testTarget(
            name: "RuleEngineTests",
            dependencies: ["RuleEngine", "SwiftSoup"]
        ),
        .testTarget(
            name: "WebBookOrchestratorTests",
            dependencies: ["WebBookOrchestrator", "BookSourceModel", "RuleEngine", "NetworkClient"]
        ),
        .testTarget(
            name: "NetworkClientTests",
            dependencies: ["NetworkClient"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "BookSourceModel"]
        )
    ]
)
