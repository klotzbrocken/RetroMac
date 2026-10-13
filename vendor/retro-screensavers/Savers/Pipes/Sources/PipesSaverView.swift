import ScreenSaver
import SceneKit

/// The screen saver's principal class (NSPrincipalClass in Savers/Pipes/Info.plist). The explicit
/// Objective-C name must be unique across the collection, since System Settings can load several
/// savers into one process.
@objc(RetroPipesSaverView)
final class PipesSaverView: RetroScreenSaverView {
    private let sceneView: SCNView
    private let pipes: PipesScene
    private var options: PipesOptions?

    override init?(frame: NSRect, isPreview: Bool) {
        sceneView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        pipes = PipesScene(settings: .load(), aspect: Self.aspect(of: frame.size), seed: .random(in: .min ... .max))
        super.init(frame: frame, isPreview: isPreview)

        sceneView.autoresizingMask = [.width, .height]
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = pipes.scene
        sceneView.pointOfView = pipes.cameraNode
        sceneView.delegate = pipes
        pipes.setViewSize(frame.size)
        addSubview(sceneView)
        // The scene is nearly still; only the pipe tips move, slowly. 30 fps looks the same at half the cost.
        fullFrameRate = 30
        frameRateDidChange()
        setAnimating(true)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Lets the harness make teapots common enough to test.
    var teapotChance: Float {
        get { pipes.teapotChance }
        set { pipes.teapotChance = newValue }
    }

    override func frameRateDidChange() {
        sceneView.preferredFramesPerSecond = frameRate
    }

    override func setAnimating(_ isAnimating: Bool) {
        sceneView.rendersContinuously = isAnimating
        sceneView.isPlaying = isAnimating
    }

    override func sizeDidSettle() {
        pipes.setViewSize(bounds.size)
        pipes.restart(aspect: Self.aspect(of: bounds.size))
    }

    override func animateOneFrame() {
        // SceneKit drives its own render loop; see PipesScene.renderer(_:updateAtTime:).
    }

    // MARK: - Options

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let options = PipesOptions(settings: .load()) { [weak self] settings in
            settings.save()
            self?.pipes.restart(settings: settings)
        }
        self.options = options
        return options.sheet.window
    }

    private static func aspect(of size: NSSize) -> Float {
        size.height > 0 ? Float(size.width / size.height) : 1.6
    }
}
