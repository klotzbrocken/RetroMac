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
        .executableTarget(
            name: "RetroMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "SkyLightBridge",
            ],
            path: "Sources",
            exclude: ["CameraExtension", "DALPlugin", "SkyLightBridge"],
            resources: [
                .copy("../Resources/Themes"),
                .copy("../Resources/TV"),
                .copy("../Resources/Widgets"),
                .copy("../Resources/Savers"),
                .copy("../Resources/Chrome")
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
                // Private WindowServer framework for per-window borders (SkyLightBridge).
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "SkyLight"]),
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
