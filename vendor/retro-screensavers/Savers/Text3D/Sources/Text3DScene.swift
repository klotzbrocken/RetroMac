import SceneKit

/// Extruded 3D text (or the current time) turning in the middle of the screen.
///
/// The geometry only changes when the text does (once a second for the time), so a frame is mostly
/// just a new rotation. Everything runs on SceneKit's render thread via `renderer(_:updateAtTime:)`.
final class Text3DScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let turntable = SCNNode()
    private let textNode = SCNNode()
    private var settings: Text3DSettings
    private var aspect: Float
    private var rng: SplitMix64
    private var time: Float = 0
    private var shownString = ""
    private var tumbleAxis = SIMD3<Float>(0, 1, 0)
    private var lastUpdateTime: TimeInterval?
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    private let restartLock = NSLock()
    private var pendingSettings: Text3DSettings?
    private var pendingAspect: Float?

    private static let fieldOfView: Float = 40
    private static let cameraDistance: Float = 6
    private static let halfHeight = cameraDistance * tan(fieldOfView / 2 * .pi / 180)
    /// Font size the text is built at; the node scale sizes it on screen.
    private static let fontSize: CGFloat = 10
    private static let extrusionDepth: CGFloat = 2.6
    /// Radians per second at normal speed.
    private static let spinSpeed: Float = 1.1
    private static let environment = makeEnvironment()

    init(settings: Text3DSettings, aspect: Float, seed: UInt64) {
        self.settings = settings
        self.aspect = aspect
        rng = SplitMix64(seed: seed)
        super.init()
        setUpScene()
        rebuild()
    }

    /// Thread-safe: applied on the next rendered frame.
    func restart(settings: Text3DSettings? = nil, aspect: Float? = nil) {
        restartLock.lock()
        defer { restartLock.unlock() }
        pendingSettings = settings ?? pendingSettings
        pendingAspect = aspect ?? pendingAspect
    }

    // MARK: - SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastUpdateTime.map { Float((time - $0).clamped(to: 0...0.1)) } ?? 0
        lastUpdateTime = time
        step(by: dt)
    }

    // MARK: - Animation

    func step(by dt: Float, at date: Date = Date()) {
        applyPendingRestart()
        time += dt * Float(settings.speed)

        if settings.content == .time {
            let string = timeFormatter.string(from: date)
            if string != shownString {
                show(string)
            }
        }

        let t = time
        switch settings.rotation {
        case .none:
            turntable.simdOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        case .spin:
            turntable.simdEulerAngles = [0, t * Self.spinSpeed, 0]
        case .seeSaw:
            turntable.simdEulerAngles = [0, 0.95 * sin(t * 0.9), 0]
        case .wobble:
            turntable.simdEulerAngles = [0.35 * sin(t * 1.1), 0.6 * sin(t * 0.8 + 1), 0.15 * sin(t * 0.6 + 2)]
        case .tumble:
            // Spin about an axis that wanders, so it never repeats.
            let nudge = SIMD3(Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng))
            tumbleAxis = simd_normalize(tumbleAxis + nudge * dt * 0.4)
            turntable.simdOrientation = simd_quatf(angle: Self.spinSpeed * dt * Float(settings.speed), axis: tumbleAxis) * turntable.simdOrientation
        }
    }

    private func rebuild() {
        turntable.simdOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        tumbleAxis = simd_normalize([0.3, 1, 0.2])
        time = 0
        shownString = ""
        show(settings.content == .time ? timeFormatter.string(from: Date()) : settings.text)
    }

    private func show(_ string: String) {
        shownString = string
        let text = SCNText(string: string, extrusionDepth: Self.extrusionDepth)
        text.font = settings.font.font(size: Self.fontSize)
        text.flatness = 0.05
        // A small bevel catches the light (and chrome's reflections) along every edge.
        text.chamferRadius = 0.25
        text.materials = [makeMaterial()]
        textNode.geometry = text

        // Centre the text on the turntable, and size it to the screen. For the time, size it by the
        // time with every digit an 8, so it doesn't change size as the digits change.
        let (minimum, maximum) = text.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, (minimum.z + maximum.z) / 2)
        var width = Float(maximum.x - minimum.x)
        let height = Float(maximum.y - minimum.y)
        if settings.content == .time {
            let sample = SCNText(string: String(string.map { $0.isNumber ? "8" : $0 }), extrusionDepth: 0)
            sample.font = text.font
            width = max(width, Float(sample.boundingBox.max.x - sample.boundingBox.min.x))
        }
        guard width > 0, height > 0 else { return }
        let screenWidth = 2 * Self.halfHeight * aspect
        let scale = min(Float(settings.size) * screenWidth / width, 0.6 * 2 * Self.halfHeight / height)
        textNode.simdScale = SIMD3(repeating: scale)
    }

    private func makeMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .phong
        material.specular.contents = NSColor(white: settings.showsHighlights ? 0.9 : 0, alpha: 1)
        material.shininess = 0.5
        material.locksAmbientWithDiffuse = true
        switch settings.surface {
        case .solid:
            material.diffuse.contents = settings.color.color
        case .chrome:
            material.diffuse.contents = NSColor(white: 0.04, alpha: 1)
            material.reflective.contents = Self.environment
        case .marble, .wood, .granite:
            material.diffuse.contents = settings.surface.texture?.makeImage()
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.mipFilter = .linear
            // SCNText's own texture coordinates smear textures into streaks, so project the texture
            // straight onto the letters instead, repeating about every two letters.
            material.shaderModifiers = [.geometry: "_geometry.texcoords[0] = _geometry.position.xy * 0.07;"]
        }
        return material
    }

    /// What chrome reflects, as the six faces of a cube map (+X, -X, +Y, -Y, +Z, -Z): a deep blue
    /// sky, a bright horizon, a dark floor, and two tall studio lights that glint as the text turns.
    private static func makeEnvironment() -> [NSImage] {
        let size = 128
        // Direction through each face pixel, in the cube map convention SceneKit uses.
        let faces: [(Float, Float) -> SIMD3<Float>] = [
            { u, v in [1, -v, -u] }, { u, v in [-1, -v, u] },
            { u, v in [u, 1, v] }, { u, v in [u, -1, -v] },
            { u, v in [u, -v, 1] }, { u, v in [-u, -v, -1] },
        ]
        return faces.map { face in
            var pixels = [UInt8](repeating: 255, count: size * size * 4)
            for y in 0..<size {
                for x in 0..<size {
                    let u = (Float(x) + 0.5) / Float(size) * 2 - 1
                    let v = (Float(y) + 0.5) / Float(size) * 2 - 1
                    let color = environmentColor(simd_normalize(face(u, v)))
                    let i = (y * size + x) * 4
                    for channel in 0..<3 {
                        pixels[i + channel] = UInt8((color[channel].clamped(to: 0...1) * 255).rounded())
                    }
                }
            }
            let image = CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: CGDataProvider(data: Data(pixels) as CFData)!,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent
            )!
            return NSImage(cgImage: image, size: NSSize(width: size, height: size))
        }
    }

    private static func environmentColor(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let up = direction.y
        var color: SIMD3<Float>
        if up >= 0 {
            // A white horizon turning quickly to deep blue overhead; the hard contrast is what reads as chrome.
            let t = min(up / 0.3, 1)
            let eased = t * t * (3 - 2 * t)
            color = SIMD3<Float>(1, 1, 1) + (SIMD3<Float>(0.05, 0.12, 0.42) - SIMD3<Float>(1, 1, 1)) * eased
        } else {
            // A dark floor right under the horizon.
            color = SIMD3<Float>(0.22, 0.18, 0.15) * (1 - min(-up / 0.4, 1))
        }
        let azimuth = atan2(direction.z, direction.x)
        for light in [0.7, 2.7] as [Float] {
            var difference = abs(azimuth - light)
            difference = min(difference, 2 * .pi - difference)
            if difference < 0.22, up > 0.05, up < 0.7 {
                color = simd_max(color, SIMD3(repeating: 0.95))
            }
        }
        return color
    }

    private func applyPendingRestart() {
        restartLock.lock()
        let newSettings = pendingSettings
        let newAspect = pendingAspect
        pendingSettings = nil
        pendingAspect = nil
        restartLock.unlock()

        var needsRebuild = false
        if let newAspect, newAspect != aspect {
            aspect = newAspect
            needsRebuild = true
        }
        if let newSettings, newSettings != settings {
            settings = newSettings
            needsRebuild = true
        }
        if needsRebuild {
            rebuild()
        }
    }

    // MARK: - Scene setup

    private func setUpScene() {
        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(turntable)
        turntable.addChildNode(textNode)

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.fieldOfView)
        camera.zNear = 0.1
        camera.zFar = 50
        cameraNode.camera = camera
        cameraNode.simdPosition = [0, 0, Self.cameraDistance]
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(white: 0.25, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = [-5, 7, 10]
        keyNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 300
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.simdPosition = [8, -3, 6]
        fillNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(fillNode)
    }
}
