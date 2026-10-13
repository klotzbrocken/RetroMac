import SceneKit

/// The Pipes simulation: pipes grow cell by cell through a 3D grid, turning at random,
/// until the screen is full enough; then the screen dissolves to black and starts over.
///
/// Everything runs on SceneKit's render thread via `renderer(_:updateAtTime:)`.
final class PipesScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let overlay = DissolveOverlay(size: CGSize(width: 16, height: 10))
    /// Chance that a ball joint is drawn as a Utah teapot instead, like the Windows original's easter egg.
    var teapotChance: Float = 1.0 / 300

    private let pipeRoot = SCNNode()
    private lazy var solidKits = PipeKit.palette.map(PipeKit.init(color:))
    /// Built on first use, since generating a texture takes a moment.
    private var textureKits: [RetroTexture: PipeKit] = [:]
    private var settings: PipesSettings
    private var rng: SplitMix64
    private var grid: Grid
    private var pipes: [Pipe] = []
    private var phase = Phase.growing
    private var spawnDelay: Float = 0
    private var spawningClosed = false
    private var lastKitIndex = -1
    private var lastUpdateTime: TimeInterval?

    private let restartLock = NSLock()
    private var viewSize = CGSize(width: 16, height: 10)
    private var pendingSettings: PipesSettings?
    private var pendingAspect: Float?

    private enum Phase {
        case growing
        case holding(remaining: Float)
        case dissolving(progress: Float)
    }

    /// Grid cells from bottom to top; the width follows the screen's aspect ratio.
    private static let rows = 16
    /// Deeper than it is tall, so pipes recede towards a vanishing point like in the original.
    private static let depth = 24
    /// Chance of turning at a cell even though the way ahead is free.
    private static let turnChance: Float = 0.2
    /// No new pipes start once this share of the grid is taken.
    private static let fillLimit = 0.2
    private static let fieldOfView: Float = 55
    /// Camera distance to the grid's front face. Close, so the nearest pipes loom large and run off screen.
    private static let frontDistance: Float = 7
    /// Each screen looks into the grid from a slightly different angle (radians).
    private static let maxViewYaw: Float = 0.3
    private static let maxViewPitch: Float = 0.2
    private static let holdDuration: Float = 2
    private static let dissolveDuration: Float = 1.2

    init(settings: PipesSettings, aspect: Float, seed: UInt64) {
        self.settings = settings
        rng = SplitMix64(seed: seed)
        grid = Grid(size: Self.gridSize(aspect: aspect))
        super.init()
        setUpScene()
        positionCamera()
        randomizeView()
    }

    /// Thread-safe: the restart happens on the next rendered frame.
    func restart(settings: PipesSettings? = nil, aspect: Float? = nil) {
        restartLock.lock()
        defer { restartLock.unlock() }
        pendingSettings = settings ?? pendingSettings
        pendingAspect = aspect ?? pendingAspect
    }

    /// Thread-safe: the size the dissolve overlay should cover.
    func setViewSize(_ size: CGSize) {
        restartLock.lock()
        defer { restartLock.unlock() }
        viewSize = size
    }

    var statusLine: String {
        let nodes = pipeRoot.childNodes.reduce(0) { $0 + 1 + $1.childNodes.count }
        return String(format: "grid %dx%dx%d, %.0f%% filled, %d growing, %d nodes, %@",
                      grid.size.x, grid.size.y, grid.size.z, grid.fillRatio * 100, pipes.count, nodes, String(describing: phase))
    }

    private var isDissolving: Bool {
        if case .dissolving = phase { return true }
        return false
    }

    // MARK: - SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastUpdateTime.map { Float((time - $0).clamped(to: 0...0.1)) } ?? 0
        lastUpdateTime = time
        step(by: dt)

        // The overlay's hidden tiles still cost a little every frame, so it's only attached while dissolving.
        if isDissolving, renderer.overlaySKScene == nil {
            restartLock.lock()
            overlay.size = viewSize
            restartLock.unlock()
            renderer.overlaySKScene = overlay
        } else if !isDissolving, renderer.overlaySKScene != nil {
            renderer.overlaySKScene = nil
        }
    }

    // MARK: - Simulation

    func step(by dt: Float) {
        applyPendingRestart()

        switch phase {
        case .growing:
            if !spawningClosed, pipes.count < settings.pipeCount {
                spawnDelay -= dt
                if spawnDelay <= 0 {
                    spawningClosed = !spawnPipe()
                    spawnDelay = Float.random(in: 0.2...0.8, using: &rng)
                }
            }
            for pipe in pipes {
                advance(pipe, by: dt)
            }
            pipes.removeAll { !$0.isActive }
            if grid.fillRatio >= Self.fillLimit {
                spawningClosed = true
            }
            if spawningClosed, pipes.isEmpty {
                phase = .holding(remaining: Self.holdDuration)
            }

        case .holding(let remaining):
            phase = remaining > dt ? .holding(remaining: remaining - dt) : .dissolving(progress: 0)

        case .dissolving(let progress):
            let next = progress + dt / Self.dissolveDuration
            overlay.progress = Double(min(next, 1))
            // Linger on black for a moment before the next screen.
            if next >= 1.3 {
                clear()
            } else {
                phase = .dissolving(progress: next)
            }
        }
    }

    private func spawnPipe() -> Bool {
        for _ in 0..<64 {
            let cell = SIMD3<Int>(
                Int.random(in: 0..<grid.size.x, using: &rng),
                Int.random(in: 0..<grid.size.y, using: &rng),
                Int.random(in: 0..<grid.size.z, using: &rng)
            )
            guard grid.isFree(cell) else { continue }
            let exits = Direction.allCases.filter { grid.isFree(cell &+ $0.offset) }
            guard let direction = exits.randomElement(using: &rng) else { continue }

            grid.occupy(cell)
            grid.occupy(cell &+ direction.offset)

            let kit = nextKit()
            let usesElbows: Bool
            switch settings.jointStyle {
            case .elbow: usesElbows = true
            case .ball: usesElbows = false
            case .mixed: usesElbows = Bool.random(using: &rng)
            }
            let start = grid.center(of: cell)
            let node = SCNNode()
            pipeRoot.addChildNode(node)
            addNode(kit.cap, at: start, to: node)
            pipes.append(Pipe(
                kit: kit,
                usesElbows: usesElbows,
                maxLength: Int.random(in: 20...80, using: &rng),
                cell: cell,
                direction: direction,
                node: node,
                run: makeRunNode(kit: kit, direction: direction, in: node),
                runStart: start
            ))
            return true
        }
        return false
    }

    private func advance(_ pipe: Pipe, by dt: Float) {
        pipe.progress += dt * Float(settings.speed)
        while pipe.progress >= 1, pipe.isActive {
            pipe.progress -= 1
            pipe.cell = pipe.cell &+ pipe.direction.offset
            pipe.length += 1
            chooseNextStep(for: pipe)
        }
        if pipe.isActive {
            updateRun(of: pipe, to: grid.center(of: pipe.cell) + pipe.direction.vector * pipe.progress)
        }
    }

    /// Called when the tip reaches the centre of a cell: keep going, turn, or stop.
    private func chooseNextStep(for pipe: Pipe) {
        let here = pipe.cell
        let aheadIsFree = grid.isFree(here &+ pipe.direction.offset)
        let turns = pipe.direction.perpendiculars.filter { grid.isFree(here &+ $0.offset) }

        if pipe.length >= pipe.maxLength || (!aheadIsFree && turns.isEmpty) {
            let center = grid.center(of: here)
            updateRun(of: pipe, to: center)
            addNode(pipe.kit.cap, at: center, to: pipe.node)
            pipe.isActive = false
            merge(pipe)
            return
        }

        if let turn = turns.randomElement(using: &rng),
           !aheadIsFree || Float.random(in: 0..<1, using: &rng) < Self.turnChance {
            self.turn(pipe, to: turn)
        }
        grid.occupy(here &+ pipe.direction.offset)
    }

    private func turn(_ pipe: Pipe, to newDirection: Direction) {
        let center = grid.center(of: pipe.cell)
        let incoming = pipe.direction.vector
        let outgoing = newDirection.vector

        if pipe.usesElbows {
            // The elbow replaces the last `bendRadius` of the incoming run and the first of the outgoing one.
            let bend = PipeMetrics.bendRadius
            updateRun(of: pipe, to: center - incoming * bend)
            let elbow = SCNNode(geometry: pipe.kit.elbow)
            elbow.simdPosition = center - incoming * bend + outgoing * bend
            elbow.simdOrientation = simd_quatf(simd_float3x3(incoming, outgoing, simd_cross(incoming, outgoing)))
            pipe.node.addChildNode(elbow)
            pipe.runStart = center + outgoing * bend
        } else {
            updateRun(of: pipe, to: center)
            if Float.random(in: 0..<1, using: &rng) < teapotChance {
                addTeapot(pipe.kit, at: center, to: pipe.node)
            } else {
                addNode(pipe.kit.ball, at: center, to: pipe.node)
            }
            pipe.runStart = center
        }

        pipe.direction = newDirection
        pipe.run = makeRunNode(kit: pipe.kit, direction: newDirection, in: pipe.node)
        pipe.runs.append(pipe.run)
    }

    /// Merges a finished pipe into a single node, so it's drawn in one go instead of piece by piece.
    private func merge(_ pipe: Pipe) {
        for run in pipe.runs {
            if run.isHidden {
                run.removeFromParentNode()
            } else {
                // Swap the stretched cylinder for one built at its real length, so the texture
                // keeps repeating along it once the stretch is baked into the merged mesh.
                run.geometry = pipe.kit.straightRun(length: run.simdScale.y)
                run.simdScale = [1, 1, 1]
            }
        }
        pipeRoot.replaceChildNode(pipe.node, with: pipe.node.flattenedClone())
    }

    private func updateRun(of pipe: Pipe, to end: SIMD3<Float>) {
        let direction = pipe.direction.vector
        let length = simd_dot(end - pipe.runStart, direction)
        pipe.run.isHidden = length <= 0.001
        pipe.run.simdScale = [1, max(length, 0.001), 1]
        pipe.run.simdPosition = pipe.runStart + direction * (length / 2)
    }

    private func makeRunNode(kit: PipeKit, direction: Direction, in parent: SCNNode) -> SCNNode {
        let node = SCNNode(geometry: kit.cylinder)
        // SCNCylinder runs along Y; lay it along the pipe's axis.
        switch direction {
        case .right, .left: node.simdEulerAngles = [0, 0, .pi / 2]
        case .forward, .back: node.simdEulerAngles = [.pi / 2, 0, 0]
        case .up, .down: break
        }
        node.isHidden = true
        parent.addChildNode(node)
        return node
    }

    private func addNode(_ geometry: SCNGeometry, at position: SIMD3<Float>, to parent: SCNNode) {
        let node = SCNNode(geometry: geometry)
        node.simdPosition = position
        parent.addChildNode(node)
    }

    private func addTeapot(_ kit: PipeKit, at position: SIMD3<Float>, to parent: SCNNode) {
        let node = SCNNode(geometry: kit.teapot)
        node.simdPosition = position
        node.simdScale = SIMD3(repeating: PipeMetrics.teapotScale)
        // Roughly side-on, spout left or right, so it reads as a teapot from the camera.
        let facing: Float = Bool.random(using: &rng) ? 0 : .pi
        node.simdEulerAngles = [0, facing + Float.random(in: -0.6...0.6, using: &rng), 0]
        parent.addChildNode(node)
    }

    /// The kits new pipes pick from under the current surface setting.
    private func availableKits() -> [PipeKit] {
        let textures = settings.surface.textures
        guard !textures.isEmpty else { return solidKits }
        return textures.map { texture in
            if let kit = textureKits[texture] {
                return kit
            }
            let kit = PipeKit(texture: texture)
            textureKits[texture] = kit
            return kit
        }
    }

    private func nextKit() -> PipeKit {
        let kits = availableKits()
        var index = Int.random(in: 0..<kits.count, using: &rng)
        if index == lastKitIndex {
            index = (index + 1) % kits.count
        }
        lastKitIndex = index
        return kits[index]
    }

    private func clear() {
        pipeRoot.childNodes.forEach { $0.removeFromParentNode() }
        grid.clear()
        pipes.removeAll()
        spawningClosed = false
        spawnDelay = 0.3
        overlay.progress = 0
        phase = .growing
        randomizeView()
    }

    private func applyPendingRestart() {
        restartLock.lock()
        let newSettings = pendingSettings
        let newAspect = pendingAspect
        pendingSettings = nil
        pendingAspect = nil
        restartLock.unlock()

        var needsClear = false
        if let newSettings, newSettings != settings {
            settings = newSettings
            needsClear = true
        }
        if let newAspect, Self.gridSize(aspect: newAspect) != grid.size {
            grid = Grid(size: Self.gridSize(aspect: newAspect))
            positionCamera()
            needsClear = true
        }
        if needsClear {
            clear()
        }
    }

    // MARK: - Scene setup

    private static func gridSize(aspect: Float) -> SIMD3<Int> {
        let columns = max(rows, Int((Float(rows) * aspect).rounded()))
        return [columns, rows, depth]
    }

    private func setUpScene() {
        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(pipeRoot)

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.fieldOfView)
        camera.zNear = 0.1
        camera.zFar = 200
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(white: 0.22, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1000
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = [-10, 14, 20]
        keyNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 250
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.simdPosition = [12, -6, 10]
        fillNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(fillNode)
    }

    private func positionCamera() {
        cameraNode.simdPosition = [0, 0, Float(grid.size.z) / 2 + Self.frontDistance]
    }

    /// Turns the grid rather than the camera, so the lighting stays the same relative to the view.
    private func randomizeView() {
        let yaw = Float.random(in: -Self.maxViewYaw...Self.maxViewYaw, using: &rng)
        let pitch = Float.random(in: -Self.maxViewPitch...Self.maxViewPitch, using: &rng)
        pipeRoot.simdOrientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }
}

private final class Pipe {
    let kit: PipeKit
    let usesElbows: Bool
    let maxLength: Int
    /// The cell the tip most recently passed through the centre of.
    var cell: SIMD3<Int>
    var direction: Direction
    /// 0...1 of the way from `cell` to the next cell.
    var progress: Float = 0
    var length = 0
    var isActive = true
    /// Holds all of the pipe's pieces until it's finished and merged.
    let node: SCNNode
    /// The straight run currently growing, and where it starts.
    var run: SCNNode
    var runStart: SIMD3<Float>
    var runs: [SCNNode]

    init(kit: PipeKit, usesElbows: Bool, maxLength: Int, cell: SIMD3<Int>, direction: Direction, node: SCNNode, run: SCNNode, runStart: SIMD3<Float>) {
        self.kit = kit
        self.usesElbows = usesElbows
        self.maxLength = maxLength
        self.cell = cell
        self.direction = direction
        self.node = node
        self.run = run
        self.runStart = runStart
        runs = [run]
    }
}
