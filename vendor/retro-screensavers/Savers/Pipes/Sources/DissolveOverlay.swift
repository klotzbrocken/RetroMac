import SpriteKit

/// The old-school "random black blocks" wipe between screens, drawn on top of the 3D scene.
final class DissolveOverlay: SKScene {
    private var tiles: [SKSpriteNode] = []
    private var revealed = 0
    // Resizes arrive on the main thread, progress updates on SceneKit's render thread.
    private let lock = NSLock()

    /// 0 shows the scene, 1 covers it completely.
    var progress: Double = 0 {
        didSet { update() }
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        buildTiles()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        buildTiles()
    }

    private func buildTiles() {
        lock.lock()
        defer { lock.unlock() }

        removeAllChildren()
        tiles.removeAll()
        revealed = 0
        guard size.width > 0, size.height > 0 else { return }

        let side = max(4, (size.height / 24).rounded(.up))
        let columns = Int((size.width / side).rounded(.up))
        let rows = Int((size.height / side).rounded(.up))
        for row in 0..<rows {
            for column in 0..<columns {
                let tile = SKSpriteNode(color: .black, size: CGSize(width: side, height: side))
                tile.anchorPoint = .zero
                tile.position = CGPoint(x: CGFloat(column) * side, y: CGFloat(row) * side)
                tile.isHidden = true
                addChild(tile)
                tiles.append(tile)
            }
        }
        tiles.shuffle()
        applyProgress()
    }

    private func update() {
        lock.lock()
        defer { lock.unlock() }
        applyProgress()
    }

    private func applyProgress() {
        let target = Int((progress.clamped(to: 0...1) * Double(tiles.count)).rounded())
        while revealed < target {
            tiles[revealed].isHidden = false
            revealed += 1
        }
        while revealed > target {
            revealed -= 1
            tiles[revealed].isHidden = true
        }
    }
}
