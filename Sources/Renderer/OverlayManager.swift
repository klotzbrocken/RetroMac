import Metal
import AppKit

enum OverlayType: String, CaseIterable {
    case scanline
    case reflection
}

struct OverlayInfo: Identifiable, Hashable {
    let id: String
    let displayName: String
    let type: OverlayType
    let isCustom: Bool

    init(id: String, displayName: String, type: OverlayType, isCustom: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.isCustom = isCustom
    }
}

final class OverlayManager {
    let device: MTLDevice
    private let textureLoader: MTKTextureLoaderLite
    private(set) var scanlineTexture: MTLTexture?
    private(set) var reflectionTexture: MTLTexture?

    private static let overlaysDirName = "RetroMac/Overlays"

    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoaderLite(device: device)
        ensureOverlaysDirectory()
    }

    // MARK: - Load

    func loadScanline(named name: String) {
        guard !name.isEmpty else { scanlineTexture = nil; return }
        if name.hasPrefix("custom:") {
            let fileName = String(name.dropFirst("custom:".count))
            scanlineTexture = loadCustom(fileName: fileName, type: .scanline)
        } else {
            scanlineTexture = generateBuiltinScanline(named: name)
        }
    }

    func loadReflection(named name: String) {
        guard !name.isEmpty else { reflectionTexture = nil; return }
        if name.hasPrefix("custom:") {
            let fileName = String(name.dropFirst("custom:".count))
            reflectionTexture = loadCustom(fileName: fileName, type: .reflection)
        } else {
            reflectionTexture = generateBuiltinReflection(named: name)
        }
    }

    // MARK: - Built-in Registry

    static let builtinScanlines: [OverlayInfo] = [
        OverlayInfo(id: "scanline-fine", displayName: "Fine", type: .scanline),
        OverlayInfo(id: "scanline-medium", displayName: "Medium", type: .scanline),
        OverlayInfo(id: "scanline-heavy", displayName: "Heavy", type: .scanline),
    ]

    static let builtinReflections: [OverlayInfo] = [
        OverlayInfo(id: "reflection-center", displayName: "Center Highlight", type: .reflection),
        OverlayInfo(id: "reflection-corner", displayName: "Corner Glare", type: .reflection),
    ]

    static func customOverlays(type: OverlayType) -> [OverlayInfo] {
        let dir = overlaysDirectory().appendingPathComponent(type.rawValue)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { ["png", "jpg", "jpeg", "tiff"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return OverlayInfo(id: "custom:\(name)", displayName: name, type: type, isCustom: true)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func allOverlays(type: OverlayType) -> [OverlayInfo] {
        let builtins: [OverlayInfo]
        switch type {
        case .scanline: builtins = builtinScanlines
        case .reflection: builtins = builtinReflections
        }
        return builtins + customOverlays(type: type)
    }

    static func overlaysDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(overlaysDirName)
    }

    // MARK: - Custom Loading

    private func loadCustom(fileName: String, type: OverlayType) -> MTLTexture? {
        let dir = Self.overlaysDirectory().appendingPathComponent(type.rawValue)
        let extensions = ["png", "jpg", "jpeg", "tiff"]
        for ext in extensions {
            let url = dir.appendingPathComponent("\(fileName).\(ext)")
            if let tex = textureLoader.load(from: url) { return tex }
        }
        return nil
    }

    private func ensureOverlaysDirectory() {
        let fm = FileManager.default
        let base = Self.overlaysDirectory()
        for type in OverlayType.allCases {
            let dir = base.appendingPathComponent(type.rawValue)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Programmatic Scanline Generation

    private func generateBuiltinScanline(named name: String) -> MTLTexture? {
        // Each scanline pattern: alternating dark lines and transparent gaps
        // height = total rows per repeat, darkRows = how many rows are dark
        let height: Int
        let darkRows: Int
        switch name {
        case "scanline-fine": height = 2; darkRows = 1
        case "scanline-medium": height = 3; darkRows = 1
        case "scanline-heavy": height = 4; darkRows = 2
        default: return nil
        }

        let width = 1
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let idx = row * width * 4
            if row < darkRows {
                pixels[idx] = 0; pixels[idx+1] = 0; pixels[idx+2] = 0; pixels[idx+3] = 255
            } else {
                pixels[idx] = 0; pixels[idx+1] = 0; pixels[idx+2] = 0; pixels[idx+3] = 0
            }
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    // MARK: - Programmatic Reflection Generation

    private func generateBuiltinReflection(named name: String) -> MTLTexture? {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        switch name {
        case "reflection-center":
            // Subtle oval highlight in upper-center area of screen
            for y in 0..<size {
                for x in 0..<size {
                    let ux = (Float(x) / Float(size)) - 0.5
                    let uy = (Float(y) / Float(size)) - 0.3
                    let dist = sqrt(ux * ux * 2.0 + uy * uy * 4.0)
                    let falloff = max(0, 1.0 - dist * 2.0)
                    let alpha = falloff * falloff * falloff * 0.6
                    let idx = (y * size + x) * 4
                    let val = UInt8(min(255, alpha * 255))
                    pixels[idx] = 255; pixels[idx+1] = 255; pixels[idx+2] = 255; pixels[idx+3] = val
                }
            }
        case "reflection-corner":
            // Subtle glare from top-left corner
            for y in 0..<size {
                for x in 0..<size {
                    let ux = Float(x) / Float(size)
                    let uy = 1.0 - Float(y) / Float(size)
                    let distTL = sqrt(ux * ux + uy * uy)
                    let falloff = max(0, 1.0 - distTL * 1.5)
                    let alpha = falloff * falloff * falloff * 0.5
                    let idx = (y * size + x) * 4
                    let val = UInt8(min(255, alpha * 255))
                    pixels[idx] = 255; pixels[idx+1] = 255; pixels[idx+2] = 255; pixels[idx+3] = val
                }
            }
        default:
            return nil
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
        return texture
    }
}

// MARK: - Lightweight Texture Loader

struct MTKTextureLoaderLite {
    let device: MTLDevice

    func load(from url: URL) -> MTLTexture? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return load(from: image)
    }

    func load(from image: NSImage) -> MTLTexture? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cgImage.width
        let h = cgImage.height

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        let bytesPerRow = w * 4
        var pixelData = [UInt8](repeating: 0, count: h * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixelData, bytesPerRow: bytesPerRow)
        return texture
    }
}
