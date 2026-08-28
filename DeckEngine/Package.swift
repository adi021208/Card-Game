// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeckEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DeckCore", targets: ["DeckCore"]),
        .library(name: "DeckGames", targets: ["DeckGames"]),
        .library(name: "DeckAI", targets: ["DeckAI"]),
        .library(name: "DeckCatalog", targets: ["DeckCatalog"]),
        .library(name: "DeckProgression", targets: ["DeckProgression"]),
        .library(name: "DeckEngine", targets: ["DeckCore", "DeckGames", "DeckAI", "DeckCatalog", "DeckProgression"])
    ],
    targets: [
        .target(name: "DeckCore"),
        .target(name: "DeckGames", dependencies: ["DeckCore"]),
        .target(name: "DeckAI", dependencies: ["DeckCore", "DeckGames"]),
        .target(name: "DeckCatalog", dependencies: ["DeckCore", "DeckGames", "DeckAI"]),
        .target(name: "DeckProgression", dependencies: ["DeckCore", "DeckGames", "DeckAI", "DeckCatalog"]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"]),
        .testTarget(name: "DeckGamesTests", dependencies: ["DeckCore", "DeckGames"]),
        .testTarget(name: "DeckAITests", dependencies: ["DeckCore", "DeckGames", "DeckAI"]),
        .testTarget(name: "DeckCatalogTests", dependencies: ["DeckCore", "DeckGames", "DeckAI", "DeckCatalog"]),
        .testTarget(name: "DeckProgressionTests", dependencies: ["DeckCore", "DeckGames", "DeckAI", "DeckCatalog", "DeckProgression"])
    ]
)
