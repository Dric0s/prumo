// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrumoKit",
    defaultLocalization: "pt-BR",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PrumoKit", targets: ["PrumoKit"]),
    ],
    targets: [
        // No iOS/macOS o SQLite vem do SDK (`import SQLite3`). No Linux, usado só
        // para rodar os testes do motor, o módulo de sistema liga a libsqlite3.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", providers: [.apt(["libsqlite3-dev"]), .yum(["sqlite-devel"])]),
        .target(
            name: "PrumoKit",
            dependencies: [.target(name: "CSQLite", condition: .when(platforms: [.linux]))],
            resources: [
                .copy("Resources/prumo-catalogo.json"),
                .copy("Resources/prumo-fontes.json"),
            ]
        ),
        .testTarget(name: "PrumoKitTests", dependencies: ["PrumoKit"]),
    ]
)
