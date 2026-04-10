// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AppModules",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "AppPlatform", targets: ["AppPlatform"]),
        .library(name: "DesktopDomain", targets: ["DesktopDomain"]),
        .library(name: "DesktopStore", targets: ["DesktopStore"]),
        .library(name: "RuntimeRegistry", targets: ["RuntimeRegistry"]),
        .library(name: "WindowManager", targets: ["WindowManager"]),
        .library(name: "DesktopCompositor", targets: ["DesktopCompositor"]),
        .library(name: "InputKit", targets: ["InputKit"]),
        .library(name: "ConnectionKit", targets: ["ConnectionKit"]),
        .library(name: "SSHKit", targets: ["SSHKit"]),
        .library(name: "VNCKit", targets: ["VNCKit"]),
        .library(name: "TerminalFeature", targets: ["TerminalFeature"]),
        .library(name: "FilesFeature", targets: ["FilesFeature"]),
        .library(name: "BrowserFeature", targets: ["BrowserFeature"]),
        .library(name: "VNCFeature", targets: ["VNCFeature"]),
        .library(name: "PersistenceKit", targets: ["PersistenceKit"]),
        .library(name: "SecurityKit", targets: ["SecurityKit"]),
        .library(name: "TelemetryKit", targets: ["TelemetryKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.90.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.12.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.26.0")
    ],
    targets: [
        .target(
            name: "AppPlatform",
            dependencies: [
                "DesktopDomain",
                "DesktopStore",
                "RuntimeRegistry",
                "WindowManager",
                "DesktopCompositor",
                "InputKit",
                "ConnectionKit",
                "SSHKit",
                "PersistenceKit",
                "SecurityKit",
                "TelemetryKit"
            ]
        ),
        .target(name: "DesktopDomain"),
        .target(
            name: "DesktopStore",
            dependencies: [
                "DesktopDomain",
                "WindowManager"
            ]
        ),
        .target(
            name: "RuntimeRegistry",
            dependencies: [
                "DesktopDomain",
                "SSHKit"
            ]
        ),
        .target(
            name: "WindowManager",
            dependencies: ["DesktopDomain"]
        ),
        .target(
            name: "DesktopCompositor",
            dependencies: [
                "DesktopDomain",
                "WindowManager"
            ]
        ),
        .target(
            name: "InputKit",
            dependencies: ["DesktopDomain"]
        ),
        .target(
            name: "ConnectionKit",
            dependencies: ["DesktopDomain"]
        ),
        .target(
            name: "SSHKit",
            dependencies: [
                "DesktopDomain",
                "ConnectionKit",
                "SecurityKit",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
            ]
        ),
        .target(
            name: "VNCKit",
            dependencies: [
                "DesktopDomain",
                "ConnectionKit"
            ]
        ),
        .target(
            name: "TerminalFeature",
            dependencies: [
                "DesktopDomain",
                "DesktopStore",
                "RuntimeRegistry",
                "WindowManager",
                "InputKit",
                "SSHKit"
            ]
        ),
        .target(
            name: "FilesFeature",
            dependencies: [
                "DesktopDomain",
                "DesktopStore",
                "WindowManager"
            ]
        ),
        .target(
            name: "BrowserFeature",
            dependencies: [
                "DesktopDomain",
                "DesktopStore",
                "RuntimeRegistry",
                "WindowManager",
                "InputKit"
            ]
        ),
        .target(
            name: "VNCFeature",
            dependencies: [
                "DesktopDomain",
                "DesktopStore",
                "RuntimeRegistry",
                "WindowManager",
                "InputKit",
                "VNCKit"
            ]
        ),
        .target(
            name: "PersistenceKit",
            dependencies: ["DesktopDomain"]
        ),
        .target(name: "SecurityKit"),
        .target(name: "TelemetryKit"),
        .testTarget(
            name: "SSHKitTests",
            dependencies: [
                "DesktopDomain",
                "SSHKit"
            ]
        ),
        .testTarget(
            name: "SecurityKitTests",
            dependencies: ["SecurityKit"]
        ),
        .testTarget(
            name: "DesktopStoreTests",
            dependencies: [
                "DesktopDomain",
                "DesktopStore"
            ]
        )
    ]
)
