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
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "Baro",
            dependencies: ["BaroCore"]
        ),
        .testTarget(
            name: "BaroCoreTests",
            dependencies: ["BaroCore"]
        )
    ]
)
