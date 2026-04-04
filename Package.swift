// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeBat",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeBatCore",
            path: "ClaudeBat",
            exclude: [
                "Info.plist",
                "ClaudeBat.entitlements",
                "Assets.xcassets",
            ],
            resources: [
                .process("Resources/PressStart2P-Regular.ttf"),
            ]
        ),
        .executableTarget(
            name: "ClaudeBat",
            dependencies: ["ClaudeBatCore"],
            path: "ClaudeBatApp"
        ),
        .testTarget(
            name: "ClaudeBatTests",
            dependencies: ["ClaudeBatCore"],
            path: "Tests/ClaudeBatTests"
        ),
    ]
)
