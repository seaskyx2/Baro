// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Baro",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "BaroCore",
            targets: ["BaroCore"]
        ),
        .library(
            name: "BaroKit",
            targets: ["BaroKit"]
        ),
        .executable(
            name: "Baro",
            targets: ["Baro"]
        )
    ],
    targets: [
        .target(
            name: "CNVMeSmart",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "BaroCore",
            dependencies: ["CNVMeSmart"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "BaroKit",
            dependencies: ["BaroCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "Baro",
            dependencies: ["BaroCore", "BaroKit"]
        ),
        .testTarget(
            name: "BaroCoreTests",
            dependencies: ["BaroCore", "BaroKit"]
        )
    ]
)
