// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RetroMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "RetroMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: ["CameraExtension", "DALPlugin"],
            resources: [
                .copy("../Resources/Shaders"),
                .copy("../Resources/Themes")
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOSurface"),
                .linkedFramework("SystemExtensions"),
                .linkedFramework("WebKit"),
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
    ]
)
