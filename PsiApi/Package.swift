// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PsiApi",
    platforms: [
        .iOS(.v10),
        .macOS(.v10_11),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "PsiApi",
            targets: ["PsiApi", "InAppPurchase"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", from: "6.1.0"),
        .package(url: "https://github.com/google/promises.git", from: "1.2.8"),
        .package(path: "../Utilities"),
        .package(path: "../Testing"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "PsiApi",
            dependencies: ["ReactiveSwift", "Promises", "Utilities"]),
        .target(
            name: "InAppPurchase",
            dependencies: ["PsiApi", "ReactiveSwift", "Promises", "Utilities"]),
        .testTarget(
            name: "PsiApiTests",
            dependencies: ["PsiApi", "ReactiveSwift", "Promises", "Utilities", "Testing"]),
    ]
)
