// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RetroMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "SkyLightBridge",
            path: "Sources/SkyLightBridge",
            publicHeadersPath: "include"
        ),
        // Platter's drive sound engine (MIT, hurtz/platter), unchanged.
        .target(
            name: "DriveSynth",
            path: "Sources/DriveSynth",
            exclude: ["LICENSE"],
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "RetroMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "SkyLightBridge",
                "DriveSynth",
            ],
            path: "Sources",
            exclude: ["CameraExtension", "SkyLightBridge", "DriveSynth"],
            resources: [
                .copy("../Resources/Themes"),
                .copy("../Resources/TV"),
                .copy("../Resources/Widgets"),
                .copy("../Resources/Savers"),
                .copy("../Resources/Chrome"),
                .copy("../Resources/Fonts"),
                .copy("../Resources/Crashes")
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOSurface"),
                .linkedFramework("SystemExtensions"),
                .linkedFramework("WebKit"),
                // Private WindowServer framework for per-window borders (SkyLightBridge). Weak, with
                // weak imports in the bridge: a symbol a macOS update drops must not stop launch.
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-Xlinker", "-weak_framework", "-Xlinker", "SkyLight"]),
            ]
        ),
        .executableTarget(
            name: "RetroMacCameraExtension",
            path: "Sources/CameraExtension",
            linkerSettings: [
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Foundation"),
            ]
        ),
        .testTarget(
            name: "RetroMacTests",
            dependencies: ["RetroMac"],
            path: "Tests/RetroMacTests"
        ),
    ]
)
