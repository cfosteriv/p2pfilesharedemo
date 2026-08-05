// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "P2PFileSharingDemoSDK",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "P2PFileSharingSDK",
            targets: ["P2PFileSharingSDK"]
        ),
    ],
    targets: [
        .target(
            name: "P2PFileSharingSDK",
            path: "Sources/P2PFileSharingDemoSDK"
        ),
        .testTarget(
            name: "P2PFileSharingSDKTests",
            dependencies: ["P2PFileSharingSDK"],
            path: "Tests/P2PFileSharingDemoSDKTests"
        ),
    ]
)
