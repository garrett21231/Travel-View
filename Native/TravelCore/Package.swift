// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TravelCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TravelCore", targets: ["TravelCore"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
    ],
    targets: [
        .target(name: "TravelCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "TravelCoreTests", dependencies: ["TravelCore", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
