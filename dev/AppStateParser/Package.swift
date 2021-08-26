// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppStateParser",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(name: "parser", targets: ["AppStateParserCLI"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/davedufresne/SwiftParsec.git", from: "4.0.1"),
        .package(url: "https://github.com/mxcl/Chalk.git", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.3.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.1.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "AppStateParserCLI",
            dependencies: [
                "AppStateParser",
                "SwiftParsec",
                "Chalk",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "AppStateParser",
            dependencies: ["SwiftParsec", "Chalk"]
        ),
        .testTarget(
            name: "AppStateParserTests",
            dependencies: ["AppStateParser", "SwiftParsec"]),
    ]
)
