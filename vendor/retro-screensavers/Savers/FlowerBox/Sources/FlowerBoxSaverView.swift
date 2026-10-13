import ScreenSaver
import SceneKit

/// The screen saver's principal class (NSPrincipalClass in Savers/FlowerBox/Info.plist). The explicit
/// Objective-C name must be unique across the collection, since System Settings can load several
/// savers into one process.
@objc(RetroFlowerBoxSaverView)
final class FlowerBoxSaverView: RetroScreenSaverView {
    private let sceneView: SCNView
    private let flowerBox: FlowerBoxScene
    private var options: FlowerBoxOptions?

    override init?(frame: NSRect, isPreview: Bool) {
        sceneView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        flowerBox = FlowerBoxScene(settings: .load(), aspect: Self.aspect(of: frame.size), seed: .random(in: .min ... .max))
        super.init(frame: frame, isPreview: isPreview)

        sceneView.autoresizingMask = [.width, .height]
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = flowerBox.scene
        sceneView.pointOfView = flowerBox.cameraNode
        sceneView.delegate = flowerBox
        addSubview(sceneView)
        // The whole object keeps moving, so it stays at 60 fps unless the Mac is saving power.
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
        flowerBox.restart(aspect: Self.aspect(of: bounds.size))
    }

    override func animateOneFrame() {
        // SceneKit drives its own render loop; see FlowerBoxScene.renderer(_:updateAtTime:).
    }

    // MARK: - Options

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let options = FlowerBoxOptions(settings: .load()) { [weak self] settings in
            settings.save()
            self?.flowerBox.restart(settings: settings)
        }
        self.options = options
        return options.sheet.window
    }

    private static func aspect(of size: NSSize) -> Float {
        size.height > 0 ? Float(size.width / size.height) : 1.6
    }
}
