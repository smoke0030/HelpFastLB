// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HelpFastLB",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "HelpFastLB",
            targets: ["HelpFastLB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework", from: "6.16.2")
    ],
    
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "HelpFastLB",
            dependencies: [
                .product(name: "AppsFlyerLib", package: "AppsFlyerFramework")
            ]
        ),
            
        .testTarget(
            name: "HelpFastLBTests",
            dependencies: ["HelpFastLB"]),
    ]
)
