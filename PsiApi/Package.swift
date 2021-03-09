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
            targets: ["PsiApi", "AppStoreIAP"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", from: "6.1.0"),
        .package(url: "https://github.com/google/promises.git", from: "1.2.10"),
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0"),
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
            name: "PsiCashClient",
            dependencies: ["PsiApi"]),
        .target(
            name: "AppStoreIAP",
            dependencies: ["PsiApi", "PsiCashClient", "ReactiveSwift", "Promises", "Utilities"]),
        .target(
            name: "PsiApiTestingCommon",
            dependencies: ["PsiApi", "PsiCashClient", "AppStoreIAP", "ReactiveSwift", "Testing",
                           "SwiftCheck"],
            path: "Tests/PsiApiTestingCommon"),
        .testTarget(
            name: "PsiApiTests",
            dependencies: ["PsiApi", "PsiApiTestingCommon", "ReactiveSwift", "Promises",
                           "Utilities", "Testing"]),
        .testTarget(
            name: "AppStoreIAPTests",
            dependencies: ["AppStoreIAP", "PsiApiTestingCommon", "Testing"]),
        .testTarget(
            name: "PsiApiTestingCommonTests",
            dependencies: ["PsiApiTestingCommon", "PsiApi", "PsiCashClient", "AppStoreIAP",
                           "ReactiveSwift", "Testing", "SwiftCheck"]
        )
    ]
)
