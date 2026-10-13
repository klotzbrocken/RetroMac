import SceneKit

/// A colourful shape that floats across the screen, bouncing off the edges and spinning, while it
/// morphs: it grows spikes and petals, rounds into a ball, and snaps back to its plain shape.
///
/// Everything runs on SceneKit's render thread via `renderer(_:updateAtTime:)`.
final class FlowerBoxScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let objectNode = SCNNode()
    private var settings: FlowerBoxSettings
    private var rng: SplitMix64
    private var mesh: ShapeMesh
    private var materials: [SCNMaterial] = []
    private var aspect: Float
    private var morphTime: Float = 0
    private var hueOffset: Float
    /// The hue offset the materials were last coloured with.
    private var appliedHueOffset: Float = -1
    private var position = SIMD2<Float>(0, 0)
    private var velocity = SIMD2<Float>(0, 0)
    private var spinAxis = SIMD3<Float>(0, 1, 0)
    private var lastUpdateTime: TimeInterval?

    private let restartLock = NSLock()
    private var pendingSettings: FlowerBoxSettings?
    private var pendingAspect: Float?

    private static let fieldOfView: Float = 40
    private static let cameraDistance: Float = 6
    /// Half the screen height at the object's depth.
    private static let halfHeight = cameraDistance * tan(fieldOfView / 2 * .pi / 180)
    /// Floating speed in screen heights per second.
    private static let floatSpeed: Float = 0.18
    private static let spinSpeed: Float = 0.9
    /// Hue turns per second when cycling colours.
    private static let hueSpeed: Float = 0.04
    /// Distinct meshes per second of morph. Each is built once and reused every cycle.
    private static let morphFrameRate: Float = 30

    /// One morph cycle as keyframes, eased in between: the plain shape swells into petals, shoots
    /// out spikes, draws the petals back in, rounds into a ball, and quickly returns to the shape.
    private static let keyframes: [(time: Float, state: MorphState)] = [
        (0, MorphState()),
        (1.5, MorphState()),
        (3.5, MorphState(petals: 1)),
        (5, MorphState(petals: 1, spikes: 1)),
        (6.5, MorphState(petals: 0.45, spikes: 1)),
        (7.5, MorphState(petals: 0.45, spikes: 1)),
        (9.5, MorphState(roundness: 1)),
        (10.5, MorphState(roundness: 1)),
        (11.5, MorphState()),
    ]

    init(settings: FlowerBoxSettings, aspect: Float, seed: UInt64) {
        self.settings = settings
        self.aspect = aspect
        rng = SplitMix64(seed: seed)
        mesh = ShapeMesh(shape: settings.shape)
        hueOffset = Float.random(in: 0..<1, using: &rng)
        super.init()
        setUpScene()
        reset()
    }

    /// Thread-safe: the restart happens on the next rendered frame.
    func restart(settings: FlowerBoxSettings? = nil, aspect: Float? = nil) {
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

    func step(by dt: Float) {
        applyPendingRestart()
        let dt = dt * Float(settings.speed)

        if settings.blooms {
            morphTime = (morphTime + dt).truncatingRemainder(dividingBy: Self.keyframes.last!.time)
        }
        if settings.cyclesColors {
            hueOffset = (hueOffset + dt * Self.hueSpeed).truncatingRemainder(dividingBy: 1)
            // Recolouring is the costliest part of a frame, so only do it once the hue visibly moves.
            if abs(hueOffset - appliedHueOffset) >= 1 / 360 {
                updateColors()
            }
        }
        if settings.spins {
            // Let the spin axis wander a little, so the tumbling doesn't repeat.
            spinAxis = simd_normalize(spinAxis + SIMD3(Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng)) * dt * 0.3)
            objectNode.simdOrientation = simd_quatf(angle: Self.spinSpeed * dt, axis: spinAxis) * objectNode.simdOrientation
        }
        float(by: dt)

        let frame = (morphTime * Self.morphFrameRate).rounded() / Self.morphFrameRate
        let state = settings.blooms ? Self.morphState(at: frame) : MorphState()
        let geometry = mesh.geometry(for: state, materials: materials)
        if objectNode.geometry !== geometry {
            objectNode.geometry = geometry
        }
    }

    /// Moves the object across the screen, bouncing off the edges.
    private func float(by dt: Float) {
        let scale = objectNode.simdScale.x
        let reach = mesh.maxRadius * scale
        // Zero when the object is wider than the screen, so it stays centred instead of jittering.
        let limit = simd_max(SIMD2(Self.halfHeight * aspect, Self.halfHeight) - reach, .zero)
        position += velocity * dt
        for axis in 0..<2 {
            if position[axis] > limit[axis] {
                position[axis] = limit[axis]
                velocity[axis] = -abs(velocity[axis])
            } else if position[axis] < -limit[axis] {
                position[axis] = -limit[axis]
                velocity[axis] = abs(velocity[axis])
            }
        }
        objectNode.simdPosition = [position.x, position.y, 0]
    }

    static func morphState(at time: Float) -> MorphState {
        guard let next = keyframes.firstIndex(where: { $0.time > time }), next > 0 else { return MorphState() }
        let from = keyframes[next - 1]
        let to = keyframes[next]
        let t = (time - from.time) / (to.time - from.time)
        let eased = t * t * (3 - 2 * t)
        func blend(_ value: KeyPath<MorphState, Float>) -> Float {
            from.state[keyPath: value] + (to.state[keyPath: value] - from.state[keyPath: value]) * eased
        }
        return MorphState(petals: blend(\.petals), spikes: blend(\.spikes), roundness: blend(\.roundness))
    }

    private func reset() {
        mesh = ShapeMesh(shape: settings.shape)
        materials = mesh.patches.map { _ in Self.makeMaterial() }
        updateColors()

        // Size relative to the screen height, measured at full bloom.
        let scale = Float(settings.size) * Self.halfHeight / mesh.maxRadius
        objectNode.simdScale = SIMD3(repeating: scale)
        position = .zero
        let angle = Float.random(in: 0..<(2 * .pi), using: &rng)
        velocity = SIMD2(cos(angle), sin(angle)) * Self.floatSpeed * 2 * Self.halfHeight
        spinAxis = simd_normalize(SIMD3(Float.random(in: -1...1, using: &rng), 1, Float.random(in: -1...1, using: &rng)))
        morphTime = 0
        step(by: 0)
    }

    /// Spreads the patches evenly around the colour wheel.
    private func updateColors() {
        appliedHueOffset = hueOffset
        for (index, material) in materials.enumerated() {
            let hue = (Float(index) / Float(materials.count) + hueOffset).truncatingRemainder(dividingBy: 1)
            material.diffuse.contents = NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: 0.95, alpha: 1)
        }
    }

    private static func makeMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .phong
        material.specular.contents = NSColor(white: 0.8, alpha: 1)
        material.shininess = 0.4
        material.locksAmbientWithDiffuse = true
        material.isDoubleSided = true
        return material
    }

    private func applyPendingRestart() {
        restartLock.lock()
        let newSettings = pendingSettings
        let newAspect = pendingAspect
        pendingSettings = nil
        pendingAspect = nil
        restartLock.unlock()

        if let newAspect {
            aspect = newAspect
        }
        if let newSettings, newSettings != settings {
            settings = newSettings
            reset()
        }
    }

    // MARK: - Scene setup

    private func setUpScene() {
        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(objectNode)

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
        key.intensity = 950
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = [-6, 8, 10]
        keyNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 300
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.simdPosition = [8, -4, 6]
        fillNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(fillNode)
    }
}
