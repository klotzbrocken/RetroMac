import AppKit
import AVFoundation
import CoreVideo
import IOSurface
import Metal
import SystemExtensions
import os.log

private let logger = Logger(subsystem: "com.retromac.app", category: "VirtualCamera")

/// Manages the virtual camera pipeline:
/// 1. Activates CMIOExtension (Camera Extension) as a SystemExtension
/// 2. Captures real webcam via AVCaptureSession
/// 3. Applies CRT shader via RetroRenderer
/// 4. Publishes processed frames to a shared IOSurface (read by Camera Extension)
final class VirtualCameraManager: NSObject, ObservableObject {
    static let shared = VirtualCameraManager()

    @Published var isRunning = false
    @Published var extensionActivated = false
    @Published var selectedShader: String = "vhs"
    @Published var shaderIntensity: Float = 0.8

    private static let extensionBundleID = "com.retromac.app.camera"

    // Webcam capture
    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "com.retromac.webcam", qos: .userInteractive)
    private var videoOutput: AVCaptureVideoDataOutput?

    // Metal rendering
    private var metalDevice: MTLDevice?
    private var renderer: RetroRenderer?
    private var textureCache: CVMetalTextureCache?

    // IOSurface for sharing with Camera Extension
    private var outputSurface: IOSurfaceRef?
    private var outputTexture: MTLTexture?
    private let outputWidth = 1280
    private let outputHeight = 720

    // Settings shared with Camera Extension via App Group
    private let sharedDefaults = UserDefaults(suiteName: "FTJLR8JRNS.com.retromac.app")

    // Lower-third overlay
    private var lowerThirdRenderer: LowerThirdRenderer?

    // Frame counter for periodic logging
    private var frameCount = 0

    // Timer to periodically re-post IOSurface ID for late-starting extensions
    private var surfaceIDTimer: DispatchSourceTimer?

    // Whether start() should be called after extension activation
    private var startAfterActivation = false

    private override init() {
        super.init()
        setupMetal()
        logger.info("VirtualCameraManager initialized — Metal: \(self.metalDevice != nil ? "OK" : "unavailable")")
    }

    // MARK: - Public API

    private var pendingReactivation = false

    func installExtension() {
        activateExtension()
    }

    /// Deactivate then reactivate to force CMIO to re-register the launchd job
    func reinstallExtension() {
        logger.info("Reinstalling Camera Extension (deactivate → reactivate)…")
        pendingReactivation = true
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func activateExtension() {
        logger.info("Requesting Camera Extension activation…")
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func start() {
        guard !isRunning else { return }

        // Check Camera permission before attempting capture.
        // After a build/update the code signature changes and macOS
        // revokes the Camera permission — same as Screen Recording.
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .denied || cameraStatus == .restricted {
            logger.error("Camera permission denied — showing alert")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Camera Permission"
                alert.informativeText = """
                    After an update you need to re-grant Camera access:

                    1. Remove RetroMac with the minus (\u{2212}) button
                    2. Re-add RetroMac with the plus (+) button
                    """
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return
        }
        if cameraStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.start() }
                }
            }
            return
        }

        logger.info("Starting virtual camera pipeline…")

        // Activate extension (handles version upgrades via replacement delegate)
        if !extensionActivated {
            startAfterActivation = true
            activateExtension()
            return
        }

        // Setup IOSurface for frame sharing
        setupIOSurface()

        // Setup renderer with selected shader
        if let device = metalDevice, renderer == nil {
            do {
                renderer = try RetroRenderer(device: device)
            } catch {
                logger.error("Renderer creation failed: \(error.localizedDescription)")
            }
        }
        do {
            try renderer?.loadShader(named: selectedShader)
        } catch {
            logger.error("Shader '\(self.selectedShader)' load failed: \(error.localizedDescription)")
        }
        renderer?.intensity = shaderIntensity

        // Start webcam capture
        guard startWebcamCapture() else {
            logger.error("Webcam capture failed — not marking as running")
            sharedDefaults?.set(0, forKey: "ioSurfaceID")
            publishSurfaceID(0)
            outputSurface = nil
            outputTexture = nil
            return
        }

        isRunning = true
        frameCount = 0

        // Start periodic re-posting of IOSurface ID for late-starting extensions
        startSurfaceIDTimer()

        logger.info("Virtual camera started — shader: \(self.selectedShader), surface: \(self.outputSurface != nil)")

        // Notify UI to rebuild menu (isRunning changed)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .virtualCameraStateChanged, object: nil)
        }
    }

    func stop() {
        guard isRunning else { return }

        stopSurfaceIDTimer()

        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil

        // Clear IOSurface ID so extension sends black frames
        sharedDefaults?.set(0, forKey: "ioSurfaceID")
        publishSurfaceID(0)
        outputSurface = nil
        outputTexture = nil

        isRunning = false
        logger.info("Virtual camera stopped")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .virtualCameraStateChanged, object: nil)
        }
    }

    func changeShader(_ name: String) {
        selectedShader = name
        // Load shader on the capture queue to avoid racing with renderToTexture
        captureQueue.async { [weak self] in
            do {
                try self?.renderer?.loadShader(named: name)
                logger.info("Shader changed to: \(name)")
            } catch {
                logger.error("Failed to load shader '\(name)': \(error.localizedDescription)")
            }
        }
    }

    func updateIntensity(_ value: Float) {
        shaderIntensity = value
        renderer?.intensity = value
    }

    // MARK: - Metal Setup

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("No Metal device available")
            return
        }
        metalDevice = device
        lowerThirdRenderer = LowerThirdRenderer(device: device)

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        textureCache = cache
    }

    // MARK: - IOSurface

    private func setupIOSurface() {
        let props: [String: Any] = [
            kIOSurfaceWidth as String: outputWidth,
            kIOSurfaceHeight as String: outputHeight,
            kIOSurfaceBytesPerElement as String: 4,
            kIOSurfaceBytesPerRow as String: outputWidth * 4,
            kIOSurfacePixelFormat as String: kCVPixelFormatType_32BGRA,
            "IOSurfaceIsGlobal" as String: true  // Make surface findable via IOSurfaceLookup across processes
        ]

        guard let surface = IOSurfaceCreate(props as CFDictionary) else {
            logger.error("Failed to create IOSurface")
            return
        }
        outputSurface = surface

        // Create Metal texture backed by IOSurface
        guard let device = metalDevice else { return }
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: outputWidth,
            height: outputHeight,
            mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared

        guard let tex = device.makeTexture(descriptor: texDesc, iosurface: surface, plane: 0) else {
            logger.error("Failed to create IOSurface-backed texture")
            return
        }
        outputTexture = tex

        // Publish IOSurface ID so the Camera Extension can find it
        let surfaceID = IOSurfaceGetID(surface)
        // Write via UserDefaults (works for same-user)
        sharedDefaults?.set(Int(surfaceID), forKey: "ioSurfaceID")
        sharedDefaults?.set(outputWidth, forKey: "width")
        sharedDefaults?.set(outputHeight, forKey: "height")
        // Also write to a world-readable file (for cross-user access by _cmiodalassistants)
        publishSurfaceID(Int(surfaceID))
        logger.info("IOSurface created — ID: \(surfaceID), size: \(self.outputWidth)×\(self.outputHeight)")
    }

    /// Write IOSurface ID to the App Group container file and legacy paths.
    /// The new camera extension reads via App Group UserDefaults (primary) or the
    /// container file (fallback). The old installed extension reads from
    /// /Library/Application Support/RetroMac/surface_id — kept for compatibility
    /// until the extension is replaced.
    private func publishSurfaceID(_ surfaceID: Int) {
        let content = "\(surfaceID)\n\(outputWidth)\n\(outputHeight)\n"

        // App Group container (new extension, owner-only)
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "FTJLR8JRNS.com.retromac.app") {
            let configFile = groupURL.appendingPathComponent("camera_surface_id")
            do {
                try content.write(to: configFile, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
                logger.info("Published surface ID \(surfaceID) to group container")
            } catch {
                logger.error("Group container write failed: \(error.localizedDescription)")
            }
        }

        // Legacy path for already-installed extension that hasn't been replaced yet
        let legacyDir = "/Library/Application Support/RetroMac"
        let legacyFile = legacyDir + "/surface_id"
        do {
            try FileManager.default.createDirectory(atPath: legacyDir, withIntermediateDirectories: true)
            try content.write(toFile: legacyFile, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacyFile)
        } catch {
            // Not critical — only needed for old extension
            logger.warning("Legacy surface_id write failed: \(error.localizedDescription)")
        }
    }

    /// Re-publish IOSurface ID periodically for the first few seconds to catch late-starting extensions
    private func startSurfaceIDTimer() {
        guard let surface = outputSurface else { return }
        let surfaceID = Int(IOSurfaceGetID(surface))
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 2.0)
        var ticks = 0
        timer.setEventHandler { [weak self] in
            ticks += 1
            self?.publishSurfaceID(surfaceID)
            if ticks >= 5 { // Stop after ~10 seconds
                self?.surfaceIDTimer?.cancel()
                self?.surfaceIDTimer = nil
            }
        }
        timer.resume()
        surfaceIDTimer = timer
    }

    private func stopSurfaceIDTimer() {
        surfaceIDTimer?.cancel()
        surfaceIDTimer = nil
    }

    // MARK: - Webcam Capture

    @discardableResult
    private func startWebcamCapture() -> Bool {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        // Find default webcam — skip virtual cameras to avoid feedback loop
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        guard let camera = discovery.devices.first(where: { !$0.localizedName.contains("RetroMac") })
                ?? AVCaptureDevice.default(for: .video) else {
            logger.error("No webcam found")
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            logger.error("Failed to create camera input: \(error.localizedDescription)")
            return false
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        videoOutput = output
        captureSession = session
        session.startRunning()

        guard session.isRunning else {
            logger.error("AVCaptureSession failed to start")
            captureSession = nil
            videoOutput = nil
            return false
        }

        logger.info("Webcam capture started: \(camera.localizedName)")
        return true
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension VirtualCameraManager: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        logger.info("Replacing existing extension v\(existing.bundleShortVersion) with v\(ext.bundleShortVersion)")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("Camera Extension needs user approval — check System Settings → General → Login Items & Extensions → Camera Extensions")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            if pendingReactivation {
                logger.info("Camera Extension deactivated — now reactivating…")
                pendingReactivation = false
                extensionActivated = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startAfterActivation = true
                    self.activateExtension()
                }
            } else {
                logger.info("Camera Extension activated successfully")
                DispatchQueue.main.async {
                    self.extensionActivated = true
                    if self.startAfterActivation {
                        self.startAfterActivation = false
                        // Small delay to let extension start polling before we publish IOSurface
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.start()
                        }
                    }
                }
            }
        case .willCompleteAfterReboot:
            logger.info("Camera Extension will activate after reboot")
        @unknown default:
            logger.info("Camera Extension activation result: \(String(describing: result))")
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("Camera Extension activation failed: \(error.localizedDescription)")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VirtualCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRunning,
              let renderer = renderer,
              let textureCache = textureCache,
              let outputTexture = outputTexture else { return }

        // Get pixel buffer from webcam frame
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Create Metal texture from webcam pixel buffer
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTex = cvTexture,
              let sourceTexture = CVMetalTextureGetTexture(cvTex) else { return }

        // Render shader to IOSurface-backed texture (zero-copy to Camera Extension)
        let viewportSize = CGSize(width: outputWidth, height: outputHeight)
        renderer.renderToTexture(sourceTexture: sourceTexture, target: outputTexture, viewportSize: viewportSize)

        // Lower-third overlay (only for Late Night CRT / Newsroom 1987)
        if let ltRenderer = lowerThirdRenderer {
            let settings = AppSettings.shared
            let shaderSupportsLT = selectedShader == "late-night-crt" || selectedShader == "newsroom-1987"
            let enabled = shaderSupportsLT && settings.lowerThirdEnabled && !settings.lowerThirdName.isEmpty
            ltRenderer.tick(enabled: enabled)

            if ltRenderer.hasContent, let pipeline = ltRenderer.compositePipeline {
                let style = selectedShader == "newsroom-1987" ? "newsroom" : "latenight"
                if let ltTexture = ltRenderer.texture(
                    name: settings.lowerThirdName,
                    title: settings.lowerThirdTitle,
                    style: style,
                    width: outputWidth, height: outputHeight
                ) {
                    renderer.compositeLowerThird(
                        texture: ltTexture,
                        pipeline: pipeline,
                        target: outputTexture,
                        viewportSize: viewportSize,
                        slideOffset: Float(ltRenderer.slideOffset)
                    )
                }
            }
        }

        frameCount += 1
    }
}
