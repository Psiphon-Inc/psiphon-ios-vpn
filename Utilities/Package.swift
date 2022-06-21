// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Utilities",
    platforms: [
        .iOS(.v10),
        .macOS(.v10_11)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "Utilities",
            targets: ["Utilities", "Rfc3339CTimestamp"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(path: "../Testing")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(name: "Rfc3339CTimestamp",
                dependencies: [],
                path: "Sources/c-timestamp"),
        .target(
            name: "Utilities",
            dependencies: ["Rfc3339CTimestamp"]),
        .testTarget(
            name: "UtilitiesTests",
            dependencies: ["Utilities", "Rfc3339CTimestamp", "Testing"]),
    ]
)
