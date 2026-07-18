// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentController",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentControllerCore", targets: ["AgentControllerCore"]),
        .library(name: "AgentControllerPlatform", targets: ["AgentControllerPlatform"]),
        .executable(name: "AgentControllerMac", targets: ["AgentControllerMac"])
    ],
    targets: [
        .target(name: "AgentControllerCore"),
        .target(
            name: "AgentControllerPlatform",
            dependencies: ["AgentControllerCore"]
        ),
        .executableTarget(
            name: "AgentControllerMac",
            dependencies: ["AgentControllerCore", "AgentControllerPlatform"]
        ),
        .testTarget(
            name: "AgentControllerCoreTests",
            dependencies: ["AgentControllerCore"]
        ),
        .testTarget(
            name: "AgentControllerPlatformTests",
            dependencies: ["AgentControllerPlatform"]
        ),
        .testTarget(
            name: "AgentControllerMacTests",
            dependencies: ["AgentControllerMac"]
        )
    ]
)
