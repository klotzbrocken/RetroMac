import ScreenSaver
import SceneKit

/// The screen saver's principal class (NSPrincipalClass in Savers/Maze/Info.plist). The explicit
/// Objective-C name must be unique across the collection, since System Settings can load several
/// savers into one process.
@objc(RetroMazeSaverView)
final class MazeSaverView: RetroScreenSaverView {
    private let sceneView: SCNView
    private let maze: MazeScene
    private var options: MazeOptions?

    override init?(frame: NSRect, isPreview: Bool) {
        sceneView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        maze = MazeScene(settings: .load(), seed: .random(in: .min ... .max))
        super.init(frame: frame, isPreview: isPreview)

        sceneView.autoresizingMask = [.width, .height]
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = maze.scene
        sceneView.pointOfView = maze.cameraNode
        sceneView.delegate = maze
        maze.setViewSize(frame.size)
        addSubview(sceneView)
        // The camera is always moving, so it stays at 60 fps unless the Mac is saving power.
        frameRateDidChange()
        setAnimating(true)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func frameRateDidChange() {
        sceneView.preferredFramesPerSecond = frameRate
    }

    override func setAnimating(_ isAnimating: Bool) {
        sceneView.rendersContinuously = isAnimating
        sceneView.isPlaying = isAnimating
    }

    override func sizeDidSettle() {
        maze.setViewSize(bounds.size)
    }

    override func animateOneFrame() {
        // SceneKit drives its own render loop; see MazeScene.renderer(_:updateAtTime:).
    }

    // MARK: - Options

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let options = MazeOptions(settings: .load()) { [weak self] settings in
            settings.save()
            self?.maze.restart(settings: settings)
        }
        self.options = options
        return options.sheet.window
    }
}
