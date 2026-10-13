import ScreenSaver
import SceneKit

/// The screen saver's principal class (NSPrincipalClass in Savers/Starfield/Info.plist). The explicit
/// Objective-C name must be unique across the collection, since System Settings can load several
/// savers into one process.
@objc(RetroStarfieldSaverView)
final class StarfieldSaverView: RetroScreenSaverView {
    private let sceneView: SCNView
    private let starfield: StarfieldScene
    private var options: StarfieldOptions?

    override init?(frame: NSRect, isPreview: Bool) {
        sceneView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        starfield = StarfieldScene(settings: .load(), aspect: Self.aspect(of: frame.size), seed: .random(in: .min ... .max))
        super.init(frame: frame, isPreview: isPreview)

        sceneView.autoresizingMask = [.width, .height]
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = starfield.scene
        sceneView.pointOfView = starfield.cameraNode
        sceneView.delegate = starfield
        addSubview(sceneView)
        // Everything is in motion, so it stays at 60 fps unless the Mac is saving power.
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
        starfield.restart(aspect: Self.aspect(of: bounds.size))
    }

    override func animateOneFrame() {
        // SceneKit drives its own render loop; see StarfieldScene.renderer(_:updateAtTime:).
    }

    // MARK: - Options

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let options = StarfieldOptions(settings: .load()) { [weak self] settings in
            settings.save()
            self?.starfield.restart(settings: settings)
        }
        self.options = options
        return options.sheet.window
    }

    private static func aspect(of size: NSSize) -> Float {
        size.height > 0 ? Float(size.width / size.height) : 1.6
    }
}
