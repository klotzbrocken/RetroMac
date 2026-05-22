// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RetroMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RetroMac",
            path: "Sources",
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
            ]
        )
    ]
)
