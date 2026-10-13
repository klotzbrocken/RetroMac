import SceneKit

/// Flying through a field of stars, like the Windows "Starfield Simulation".
///
/// All the stars are one point mesh drawn in a single call, and the GPU moves them: each star keeps
/// a fixed spot and a phase along the flight, and a shader modifier places it from a shared clock.
/// So the CPU only advances that clock each frame, however many stars there are.
final class StarfieldScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let starsNode = SCNNode()
    private let material = SCNMaterial()
    private var settings: StarfieldSettings
    private var aspect: Float
    private var rng: SplitMix64
    /// How far through one flight the stars are, 0..<1.
    private var flight: Float = 0
    private var lastUpdateTime: TimeInterval?
    /// Scales the stars' size; the harness enlarges them for the small System Settings tile.
    private let starScale: Float

    private let restartLock = NSLock()
    private var pendingSettings: StarfieldSettings?
    private var pendingAspect: Float?

    /// Stars fly from `farthest` to `nearest` in front of the camera, then start over far away.
    private static let nearest: Float = 0.6
    private static let farthest: Float = 30
    private static let fieldOfView: Float = 60
    /// Flights per second at warp speed 1.
    private static let flightRate: Float = 0.08

    /// Places each star along its flight. The vertex colour's red channel carries the star's phase;
    /// the colour is then set to its brightness, so far stars are dim grey and near ones white.
    private static let flightShader = """
        #pragma arguments
        float flight;
        #pragma body
        float travelled = fract(_geometry.color.r - flight);
        float distance = \(nearest)f + (1.0f - travelled) * \(farthest - nearest)f;
        _geometry.position.z = -distance;
        float brightness = 0.18f + 0.82f * travelled * travelled;
        _geometry.color = float4(brightness, brightness, brightness, 1.0f);
        """

    init(settings: StarfieldSettings, aspect: Float, seed: UInt64, starScale: Float = 1) {
        self.settings = settings
        self.aspect = aspect
        self.starScale = starScale
        rng = SplitMix64(seed: seed)
        super.init()
        setUpScene()
        buildStars()
    }

    /// Thread-safe: applied on the next rendered frame.
    func restart(settings: StarfieldSettings? = nil, aspect: Float? = nil) {
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
        restartLock.lock()
        let newSettings = pendingSettings
        let newAspect = pendingAspect
        pendingSettings = nil
        pendingAspect = nil
        restartLock.unlock()
        var needsStars = false
        if let newSettings, newSettings != settings {
            needsStars = newSettings.density != settings.density
            settings = newSettings
        }
        if let newAspect, newAspect != aspect {
            aspect = newAspect
            needsStars = true
        }
        if needsStars {
            buildStars()
        }

        flight = (flight + dt * Self.flightRate * Float(settings.warpSpeed)).truncatingRemainder(dividingBy: 1)
        material.setValue(NSNumber(value: flight), forKey: "flight")
    }

    private func buildStars() {
        // Spread the stars over the whole view at the far end, so they stream out of the depths
        // evenly and fly off every edge as they come closer.
        let halfHeight = Self.farthest * tan(Self.fieldOfView / 2 * .pi / 180)
        let spread = SIMD2(halfHeight * aspect, halfHeight)
        var positions: [SCNVector3] = []
        var phases: [SIMD3<Float>] = []
        for _ in 0..<settings.density {
            let x = Float.random(in: -spread.x...spread.x, using: &rng)
            let y = Float.random(in: -spread.y...spread.y, using: &rng)
            let phase = Float.random(in: 0..<1, using: &rng)
            // Real depths are set by the shader; this one only has to be somewhere along the flight.
            positions.append(SCNVector3(x, y, -Self.farthest / 2))
            phases.append(SIMD3(phase, 0, 0))
        }
        let colors = SCNGeometrySource(
            data: phases.withUnsafeBytes { Data($0) }, semantic: .color, vectorCount: phases.count,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride
        )
        let element = SCNGeometryElement(indices: (0..<UInt32(settings.density)).map { $0 }, primitiveType: .point)
        // Point size is in scene units, so stars grow as they come closer, within these limits (in pixels).
        element.pointSize = CGFloat(0.12 * starScale)
        element.minimumPointScreenSpaceRadius = CGFloat(0.8 * starScale)
        element.maximumPointScreenSpaceRadius = CGFloat(5 * starScale)

        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), colors], elements: [element])
        geometry.materials = [material]
        // The stars move in the shader, so tell SceneKit the whole volume they fly through.
        geometry.boundingBox = (
            min: SCNVector3(-spread.x, -spread.y, -Self.farthest),
            max: SCNVector3(spread.x, spread.y, -Self.nearest)
        )
        starsNode.geometry = geometry
    }

    // MARK: - Scene setup

    private func setUpScene() {
        scene.background.contents = NSColor.black

        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        material.shaderModifiers = [.geometry: Self.flightShader]
        material.setValue(NSNumber(value: Float(0)), forKey: "flight")
        scene.rootNode.addChildNode(starsNode)

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.fieldOfView)
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }
}
