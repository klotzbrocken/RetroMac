import Foundation

struct SlangPreset {
    let passes: [ShaderPass]
    let textures: [LUTTexture]
    let parameters: [String: Float]
}

struct ShaderPass {
    let index: Int
    let shaderPath: String
    let filterLinear: Bool
    let scaleType: ScaleType
    let scaleX: Float
    let scaleY: Float
    let alias: String?
    let srgbFramebuffer: Bool
    let floatFramebuffer: Bool
    let wrapMode: WrapMode
    let mipmap: Bool

    enum ScaleType: String {
        case source, viewport, absolute
    }

    enum WrapMode: String {
        case clampToEdge = "clamp_to_edge"
        case repeatWrap = "repeat"
        case mirroredRepeat = "mirrored_repeat"
    }
}

struct LUTTexture {
    let name: String
    let path: String
    let filterLinear: Bool
    let mipmap: Bool
    let wrapMode: ShaderPass.WrapMode
}

final class SlangPresetParser {
    enum ParseError: Error {
        case fileNotFound(String)
        case invalidFormat(String)
        case missingShaderCount
    }

    func parse(url: URL) throws -> SlangPreset {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParseError.fileNotFound(url.path)
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let dict = parseINI(content)
        let baseDir = url.deletingLastPathComponent()

        guard let shaderCountStr = dict["shaders"], let shaderCount = Int(shaderCountStr) else {
            throw ParseError.missingShaderCount
        }

        var passes: [ShaderPass] = []
        for i in 0..<shaderCount {
            let pass = parsePass(index: i, dict: dict, baseDir: baseDir)
            passes.append(pass)
        }

        let textures = parseTextures(dict: dict, baseDir: baseDir)
        let parameters = parseParameters(dict: dict)

        return SlangPreset(passes: passes, textures: textures, parameters: parameters)
    }

    private func parseINI(_ content: String) -> [String: String] {
        var dict: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            dict[key] = value
        }
        return dict
    }

    private func parsePass(index i: Int, dict: [String: String], baseDir: URL) -> ShaderPass {
        let shaderRel = dict["shader\(i)"] ?? ""
        let shaderPath = baseDir.appendingPathComponent(shaderRel).path

        let filterLinear = dict["filter_linear\(i)"].flatMap { $0 == "true" } ?? false

        let scaleTypeStr = dict["scale_type\(i)"] ?? dict["scale_type_x\(i)"] ?? "source"
        let scaleType = ShaderPass.ScaleType(rawValue: scaleTypeStr) ?? .source

        let scaleX = dict["scale_x\(i)"].flatMap { Float($0) } ?? dict["scale\(i)"].flatMap { Float($0) } ?? 1.0
        let scaleY = dict["scale_y\(i)"].flatMap { Float($0) } ?? dict["scale\(i)"].flatMap { Float($0) } ?? 1.0

        let alias = dict["alias\(i)"]
        let srgb = dict["srgb_framebuffer\(i)"] == "true"
        let floatFB = dict["float_framebuffer\(i)"] == "true"
        let wrapStr = dict["wrap_mode\(i)"] ?? "clamp_to_edge"
        let wrapMode = ShaderPass.WrapMode(rawValue: wrapStr) ?? .clampToEdge
        let mipmap = dict["mipmap_input\(i)"] == "true"

        return ShaderPass(
            index: i,
            shaderPath: shaderPath,
            filterLinear: filterLinear,
            scaleType: scaleType,
            scaleX: scaleX,
            scaleY: scaleY,
            alias: alias,
            srgbFramebuffer: srgb,
            floatFramebuffer: floatFB,
            wrapMode: wrapMode,
            mipmap: mipmap
        )
    }

    private func parseTextures(dict: [String: String], baseDir: URL) -> [LUTTexture] {
        guard let textureList = dict["textures"] else { return [] }
        let names = textureList.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return names.compactMap { name in
            guard let relPath = dict[name] else { return nil }
            let path = baseDir.appendingPathComponent(relPath).path
            let linear = dict["\(name)_linear"] == "true"
            let mipmap = dict["\(name)_mipmap"] == "true"
            let wrapStr = dict["\(name)_wrap_mode"] ?? "clamp_to_edge"
            let wrapMode = ShaderPass.WrapMode(rawValue: wrapStr) ?? .clampToEdge
            return LUTTexture(name: name, path: path, filterLinear: linear, mipmap: mipmap, wrapMode: wrapMode)
        }
    }

    private func parseParameters(dict: [String: String]) -> [String: Float] {
        guard let paramList = dict["parameters"] else { return [:] }
        let names = paramList.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var params: [String: Float] = [:]
        for name in names {
            if let val = dict[name].flatMap({ Float($0) }) {
                params[name] = val
            }
        }
        return params
    }
}
