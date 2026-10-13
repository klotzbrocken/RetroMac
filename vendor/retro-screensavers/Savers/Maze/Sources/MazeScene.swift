import SceneKit

/// A walk through a random maze, like the Windows 3D Maze: brick walls, a wooden floor, ceiling
/// tiles, rats scurrying about, grey spinners that flip the world upside down, and a smiley at
/// the finish, after which a new maze begins.
///
/// The walls, floor and ceiling are built once per maze; a frame only moves the camera, the rats
/// and the spinners. Everything runs on SceneKit's render thread via `renderer(_:updateAtTime:)`.
final class MazeScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let map = MazeMap(size: CGSize(width: 16, height: 10))

    private let mazeRoot = SCNNode()
    private let fadeNode = SCNNode()
    private let wallMaterial = MazeScene.texturedMaterial(MazeTextures.brickWall())
    private let floorMaterial = MazeScene.texturedMaterial(MazeTextures.woodFloor())
    private let ceilingMaterial = MazeScene.texturedMaterial(MazeTextures.ceilingTiles())
    private let ratModel = MazeModels.rat()
    private let flipperModel = MazeModels.flipper()
    private let smiley = MazeModels.smiley()

    private var settings: MazeSettings
    private var rng: SplitMix64
    private var layout: MazeLayout
    private var walker = Walker()
    private var rats: [Rat] = []
    private var flippers: [SIMD2<Int>: SCNNode] = [:]
    private var phase = Phase.fadingIn(progress: 0)
    private var roll = Roll()
    private var clock: Float = 0
    /// How many mazes have been walked to the finish, for the harness's status line.
    private(set) var completedMazes = 0
    private var lastUpdateTime: TimeInterval?

    private let restartLock = NSLock()
    private var viewSize = CGSize(width: 16, height: 10)
    private var pendingSettings: MazeSettings?

    private static let cellSize: Float = 2
    private static let wallHeight: Float = 2
    private static let eyeHeight: Float = 1
    /// Seconds per cell walked, and per quarter turn, at speed 1.
    private static let stepDuration: Float = 0.55
    private static let turnDuration: Float = 0.45
    private static let ratSpeed: Float = 1.8
    private static let flipDuration: Float = 1.2
    private static let fadeDuration: Float = 0.9

    private enum Phase {
        case walking
        case fadingOut(progress: Float)
        case fadingIn(progress: Float)
    }

    private struct Walker {
        enum Action {
            case moving(progress: Float)
            case turning(from: Float, to: Float, progress: Float)
        }

        var cell = SIMD2<Int>(0, 0)
        var heading = Heading.north
        var yaw: Float = 0
        var action = Action.moving(progress: 0)
    }

    /// Turning the camera upside down and back, about its line of sight.
    private struct Roll {
        var angle: Float = 0
        var from: Float = 0
        var to: Float = 0
        var progress: Float = 1
    }

    private final class Rat {
        let node: SCNNode
        var cell: SIMD2<Int>
        var heading: Heading
        var progress: Float = 0

        init(node: SCNNode, cell: SIMD2<Int>, heading: Heading) {
            self.node = node
            self.cell = cell
            self.heading = heading
        }
    }

    init(settings: MazeSettings, seed: UInt64) {
        self.settings = settings
        rng = SplitMix64(seed: seed)
        layout = MazeLayout(size: settings.size.cells, rng: &rng)
        super.init()
        setUpScene()
        startMaze()
    }

    /// Thread-safe: applied on the next rendered frame.
    func restart(settings: MazeSettings) {
        restartLock.lock()
        defer { restartLock.unlock() }
        pendingSettings = settings
    }

    /// Thread-safe: the size the overlay map lays itself out in.
    func setViewSize(_ size: CGSize) {
        restartLock.lock()
        defer { restartLock.unlock() }
        viewSize = size
    }

    // MARK: - SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastUpdateTime.map { Float((time - $0).clamped(to: 0...0.1)) } ?? 0
        lastUpdateTime = time
        step(by: dt)

        if settings.showsMap, renderer.overlaySKScene == nil {
            restartLock.lock()
            map.size = viewSize
            restartLock.unlock()
            renderer.overlaySKScene = map
        } else if !settings.showsMap, renderer.overlaySKScene != nil {
            renderer.overlaySKScene = nil
        }
    }

    // MARK: - Animation

    func step(by dt: Float) {
        restartLock.lock()
        let newSettings = pendingSettings
        pendingSettings = nil
        restartLock.unlock()
        if let newSettings, newSettings != settings {
            settings = newSettings
            layout = MazeLayout(size: settings.size.cells, rng: &rng)
            startMaze()
        }

        let dt = dt * Float(settings.speed)
        clock += dt

        switch phase {
        case .walking:
            walk(by: dt)
        case .fadingOut(let progress):
            let next = progress + dt / Self.fadeDuration
            fadeNode.opacity = CGFloat(min(next, 1))
            if next >= 1.2 {
                completedMazes += 1
                layout = MazeLayout(size: settings.size.cells, rng: &rng)
                startMaze()
            } else {
                phase = .fadingOut(progress: next)
            }
        case .fadingIn(let progress):
            walk(by: dt)
            let next = progress + dt / Self.fadeDuration
            fadeNode.opacity = CGFloat(max(1 - next, 0))
            phase = next >= 1 ? .walking : .fadingIn(progress: next)
        }

        moveRats(by: dt)
        for (_, flipper) in flippers {
            flipper.simdEulerAngles = [clock * 0.9, clock * 1.4, 0]
        }
        smiley.simdEulerAngles = [0, clock * 1.6, 0]
        updateRoll(by: dt)
        placeCamera()
    }

    private func walk(by dt: Float) {
        switch walker.action {
        case .moving(let progress):
            let next = progress + dt / Self.stepDuration
            if next < 1 {
                walker.action = .moving(progress: next)
            } else {
                walker.cell = walker.cell &+ walker.heading.offset
                arrive()
            }
        case .turning(let from, let to, let progress):
            let quarterTurns = abs(to - from) / (.pi / 2)
            let next = progress + dt / (Self.turnDuration * quarterTurns)
            if next < 1 {
                walker.action = .turning(from: from, to: to, progress: next)
            } else {
                walker.yaw = to
                walker.action = .moving(progress: 0)
            }
        }
    }

    /// The walker has reached the centre of a cell.
    private func arrive() {
        if let flipper = flippers.removeValue(forKey: walker.cell) {
            flipper.removeFromParentNode()
            roll.from = roll.angle
            roll.to += .pi
            roll.progress = 0
        }
        if walker.cell == layout.finish {
            walker.action = .moving(progress: 0)
            phase = .fadingOut(progress: 0)
            return
        }
        let next = layout.rightHandTurn(at: walker.cell, facing: walker.heading)
        if next == walker.heading {
            walker.action = .moving(progress: 0)
            return
        }
        let turn: Float
        switch next {
        case walker.heading.right: turn = -.pi / 2
        case walker.heading.left: turn = .pi / 2
        default: turn = .pi
        }
        walker.heading = next
        walker.action = .turning(from: walker.yaw, to: walker.yaw + turn, progress: 0)
    }

    private func moveRats(by dt: Float) {
        for rat in rats {
            rat.progress += dt * Self.ratSpeed
            while rat.progress >= 1 {
                rat.progress -= 1
                rat.cell = rat.cell &+ rat.heading.offset
                // Scurry on at random, only turning back at dead ends.
                let ways = layout.openHeadings(at: rat.cell).filter { $0 != rat.heading.back }
                rat.heading = ways.randomElement(using: &rng) ?? rat.heading.back
            }
            let position = center(of: rat.cell) + vector(rat.heading) * rat.progress * Self.cellSize
            rat.node.simdPosition = [position.x, 0, position.z]
            rat.node.simdEulerAngles = [0, rat.heading.yaw, 0]
        }
    }

    private func updateRoll(by dt: Float) {
        guard roll.progress < 1 else { return }
        roll.progress = min(roll.progress + dt / Self.flipDuration, 1)
        let t = roll.progress * roll.progress * (3 - 2 * roll.progress)
        roll.angle = roll.from + (roll.to - roll.from) * t
    }

    private func placeCamera() {
        var position = center(of: walker.cell)
        var yaw = walker.yaw
        switch walker.action {
        case .moving(let progress):
            position += vector(walker.heading) * progress * Self.cellSize
        case .turning(let from, let to, let progress):
            let t = progress * progress * (3 - 2 * progress)
            yaw = from + (to - from) * t
        }
        cameraNode.simdPosition = [position.x, Self.eyeHeight, position.z]
        cameraNode.simdOrientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: roll.angle, axis: [0, 0, 1])

        if settings.showsMap {
            let cells = SIMD2(position.x, position.z) / Self.cellSize
            map.update(position: cells, yaw: yaw, visiting: walker.cell)
        }
    }

    // MARK: - Building a maze

    private func startMaze() {
        buildMaze()
        walker = Walker()
        walker.cell = layout.start
        walker.heading = layout.openHeadings(at: layout.start).first ?? .north
        walker.yaw = walker.heading.yaw
        roll = Roll()
        phase = .fadingIn(progress: 0)
        fadeNode.opacity = 1
        map.show(layout)
        placeCamera()
    }

    private func buildMaze() {
        mazeRoot.childNodes.forEach { $0.removeFromParentNode() }
        let n = layout.size
        let c = Self.cellSize
        let h = Self.wallHeight
        let side = Float(n) * c
        let up = SIMD3<Float>(0, 1, 0)

        var floor = QuadBuilder()
        floor.addQuad(base: [side / 2, 0, side], normal: up, up: [0, 0, -1], width: side, height: side, repeats: [Float(n), Float(n)])
        mazeRoot.addChildNode(SCNNode(geometry: floor.geometry(material: floorMaterial)))
        var ceiling = QuadBuilder()
        ceiling.addQuad(base: [side / 2, h, 0], normal: -up, up: [0, 0, 1], width: side, height: side, repeats: [Float(n), Float(n)])
        mazeRoot.addChildNode(SCNNode(geometry: ceiling.geometry(material: ceilingMaterial)))

        // Every wall is two quads back to back, one for each side.
        var walls = QuadBuilder()
        func addWall(center: SIMD3<Float>, normal: SIMD3<Float>) {
            walls.addQuad(base: center, normal: normal, up: up, width: c, height: h)
            walls.addQuad(base: center, normal: -normal, up: up, width: c, height: h)
        }
        for y in 0..<n {
            for x in 0..<n {
                let cell = SIMD2(x, y)
                if !layout.isOpen(cell, .north) {
                    addWall(center: [(Float(x) + 0.5) * c, 0, Float(y) * c], normal: [0, 0, 1])
                }
                if !layout.isOpen(cell, .west) {
                    addWall(center: [Float(x) * c, 0, (Float(y) + 0.5) * c], normal: [1, 0, 0])
                }
            }
            addWall(center: [side, 0, (Float(y) + 0.5) * c], normal: [-1, 0, 0])
        }
        for x in 0..<n {
            addWall(center: [(Float(x) + 0.5) * c, 0, side], normal: [0, 0, -1])
        }
        mazeRoot.addChildNode(SCNNode(geometry: walls.geometry(material: wallMaterial)))

        // The finish smiley, the flippers and the rats.
        let finish = center(of: layout.finish)
        smiley.simdPosition = [finish.x, Self.eyeHeight, finish.z]
        mazeRoot.addChildNode(smiley)

        var free = (0..<(n * n)).map { SIMD2($0 % n, $0 / n) }.filter { $0 != layout.start && $0 != layout.finish }
        free.shuffle(using: &rng)
        flippers = [:]
        for cell in free.prefix(min(settings.flippers, free.count / 4)) {
            let flipper = flipperModel.clone()
            let position = center(of: cell)
            flipper.simdPosition = [position.x, Self.eyeHeight, position.z]
            mazeRoot.addChildNode(flipper)
            flippers[cell] = flipper
        }
        rats = free.suffix(settings.rats).map { cell in
            let node = ratModel.clone()
            mazeRoot.addChildNode(node)
            return Rat(node: node, cell: cell, heading: layout.openHeadings(at: cell).randomElement(using: &rng) ?? .north)
        }
    }

    /// For the harness: a camera high above the maze looking straight down (the ceiling only
    /// faces downwards, so it's invisible from above).
    func overviewCamera() -> SCNNode {
        let side = Float(layout.size) * Self.cellSize
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zFar = 200
        let node = SCNNode()
        node.camera = camera
        node.simdPosition = [side / 2, side * 0.95, side / 2]
        node.simdEulerAngles = [-.pi / 2, 0, 0]
        scene.rootNode.addChildNode(node)
        return node
    }

    private func center(of cell: SIMD2<Int>) -> SIMD3<Float> {
        [(Float(cell.x) + 0.5) * Self.cellSize, 0, (Float(cell.y) + 0.5) * Self.cellSize]
    }

    private func vector(_ heading: Heading) -> SIMD3<Float> {
        [Float(heading.offset.x), 0, Float(heading.offset.y)]
    }

    // MARK: - Scene setup

    private func setUpScene() {
        scene.background.contents = NSColor.black
        // The corridors fade into darkness in the distance.
        scene.fogColor = NSColor.black
        scene.fogStartDistance = 5
        scene.fogEndDistance = 22
        scene.rootNode.addChildNode(mazeRoot)

        let camera = SCNCamera()
        camera.fieldOfView = 70
        camera.zNear = 0.05
        camera.zFar = 60
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // A light carried with the camera, so nearby walls are brightest.
        let lamp = SCNLight()
        lamp.type = .omni
        lamp.intensity = 900
        lamp.attenuationStartDistance = 1
        lamp.attenuationEndDistance = 18
        cameraNode.light = lamp
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(white: 0.3, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Black in front of the camera, for fading between mazes.
        let curtain = SCNPlane(width: 4, height: 4)
        let black = SCNMaterial()
        black.lightingModel = .constant
        black.diffuse.contents = NSColor.black
        black.readsFromDepthBuffer = false
        black.writesToDepthBuffer = false
        curtain.materials = [black]
        fadeNode.geometry = curtain
        fadeNode.simdPosition = [0, 0, -0.2]
        fadeNode.renderingOrder = 1000
        cameraNode.addChildNode(fadeNode)
    }

    private static func texturedMaterial(_ image: CGImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = image
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.mipFilter = .linear
        return material
    }
}
