import ScreenSaver
import SceneKit

/// The screen saver's principal class (NSPrincipalClass in Savers/Text3D/Info.plist). The explicit
/// Objective-C name must be unique across the collection, since System Settings can load several
/// savers into one process.
@objc(RetroText3DSaverView)
final class Text3DSaverView: RetroScreenSaverView {
    private let sceneView: SCNView
    private let text3D: Text3DScene
    private var options: Text3DOptions?

    override init?(frame: NSRect, isPreview: Bool) {
        sceneView = SCNView(frame: NSRect(origin: .zero, size: frame.size))
        text3D = Text3DScene(settings: .load(), aspect: Self.aspect(of: frame.size), seed: .random(in: .min ... .max))
        super.init(frame: frame, isPreview: isPreview)

        sceneView.autoresizingMask = [.width, .height]
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = text3D.scene
        sceneView.pointOfView = text3D.cameraNode
        sceneView.delegate = text3D
        addSubview(sceneView)
        // Turning text stutters below 60 fps, so it only drops when the Mac is saving power.
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
        text3D.restart(aspect: Self.aspect(of: bounds.size))
    }

    override func animateOneFrame() {
        // SceneKit drives its own render loop; see Text3DScene.renderer(_:updateAtTime:).
    }

    // MARK: - Options

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let options = Text3DOptions(settings: .load()) { [weak self] settings in
            settings.save()
            self?.text3D.restart(settings: settings)
        }
        self.options = options
        return options.sheet.window
    }

    private static func aspect(of size: NSSize) -> Float {
        size.height > 0 ? Float(size.width / size.height) : 1.6
    }
}
