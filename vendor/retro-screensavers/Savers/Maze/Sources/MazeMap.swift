import SpriteKit

/// The optional overlay map in the top-left corner: the maze's walls, the path walked so far,
/// the finish, and an arrow for where you are.
final class MazeMap: SKScene {
    private let content = SKNode()
    private let walls = SKShapeNode()
    private let trail = SKShapeNode()
    private let finish = SKShapeNode()
    private let walker = SKShapeNode()
    private let backdrop = SKShapeNode()
    private var mazeSize = 1
    private var visited: [SIMD2<Int>] = []
    private var wallSegments: [(SIMD2<Int>, SIMD2<Int>)] = []
    private var finishCell = SIMD2<Int>(0, 0)
    /// Map points per maze cell.
    private var cellSize: CGFloat = 10
    /// Where the walker is, in cells, kept so a new layout can place it again.
    private var walkerPosition = SIMD2<Float>(0.5, 0.5)
    // Resizes arrive on the main thread, updates on SceneKit's render thread.
    private let lock = NSLock()

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        backdrop.fillColor = NSColor(white: 0, alpha: 0.55)
        backdrop.strokeColor = .clear
        walls.strokeColor = NSColor(white: 0.85, alpha: 0.9)
        walls.lineWidth = 1.5
        trail.strokeColor = NSColor(srgbRed: 0.35, green: 0.75, blue: 1, alpha: 0.8)
        trail.lineWidth = 2
        finish.fillColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.1, alpha: 1)
        finish.strokeColor = .clear
        walker.fillColor = NSColor(srgbRed: 1, green: 0.3, blue: 0.25, alpha: 1)
        walker.strokeColor = .clear
        for node in [backdrop, walls, trail, finish, walker] {
            content.addChild(node)
        }
        addChild(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        lock.lock()
        defer { lock.unlock() }
        layOut()
    }

    func show(_ layout: MazeLayout) {
        lock.lock()
        defer { lock.unlock() }
        mazeSize = layout.size
        finishCell = layout.finish
        visited = []
        wallSegments = []
        let n = layout.size
        for y in 0..<n {
            for x in 0..<n {
                let cell = SIMD2(x, y)
                if !layout.isOpen(cell, .north) { wallSegments.append((SIMD2(x, y), SIMD2(x + 1, y))) }
                if !layout.isOpen(cell, .west) { wallSegments.append((SIMD2(x, y), SIMD2(x, y + 1))) }
            }
            wallSegments.append((SIMD2(n, y), SIMD2(n, y + 1)))
        }
        for x in 0..<n {
            wallSegments.append((SIMD2(x, n), SIMD2(x + 1, n)))
        }
        layOut()
    }

    /// `position` is in cells (cell centres at .5), `yaw` the walker's facing.
    func update(position: SIMD2<Float>, yaw: Float, visiting cell: SIMD2<Int>) {
        lock.lock()
        defer { lock.unlock() }
        if visited.last != cell {
            visited.append(cell)
            trail.path = path(through: visited.map { SIMD2(Float($0.x) + 0.5, Float($0.y) + 0.5) })
        }
        walkerPosition = position
        walker.position = point(position)
        walker.zRotation = CGFloat(yaw)
    }

    private func layOut() {
        // Draw in screen points: SpriteKit renders shapes at their own size before any scaling,
        // so shapes drawn in cell units and scaled up come out blurred.
        let side = min(size.height * 0.3, 260)
        let margin = max(16, size.height * 0.03)
        cellSize = side / CGFloat(mazeSize)
        content.position = CGPoint(x: margin, y: size.height - margin - side)
        backdrop.path = CGPath(rect: CGRect(x: -6, y: -6, width: side + 12, height: side + 12), transform: nil)
        let wallPath = CGMutablePath()
        for (from, to) in wallSegments {
            wallPath.move(to: point(SIMD2(Float(from.x), Float(from.y))))
            wallPath.addLine(to: point(SIMD2(Float(to.x), Float(to.y))))
        }
        walls.path = wallPath
        trail.path = path(through: visited.map { SIMD2(Float($0.x) + 0.5, Float($0.y) + 0.5) })
        finish.path = CGPath(ellipseIn: CGRect(x: -cellSize * 0.22, y: -cellSize * 0.22, width: cellSize * 0.44, height: cellSize * 0.44), transform: nil)
        finish.position = point(SIMD2(Float(finishCell.x) + 0.5, Float(finishCell.y) + 0.5))
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 0, y: cellSize * 0.35))
        arrow.addLine(to: CGPoint(x: -cellSize * 0.25, y: -cellSize * 0.25))
        arrow.addLine(to: CGPoint(x: cellSize * 0.25, y: -cellSize * 0.25))
        arrow.closeSubpath()
        walker.path = arrow
        walker.position = point(walkerPosition)
    }

    /// Maze cells to map points: y grows southwards in the maze, upwards in SpriteKit.
    private func point(_ cell: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(cell.x) * cellSize, y: (CGFloat(mazeSize) - CGFloat(cell.y)) * cellSize)
    }

    private func path(through points: [SIMD2<Float>]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: point(first))
        for next in points.dropFirst() {
            path.addLine(to: point(next))
        }
        return path
    }
}
