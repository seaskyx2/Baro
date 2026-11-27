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
            name: "BaroCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications")
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
