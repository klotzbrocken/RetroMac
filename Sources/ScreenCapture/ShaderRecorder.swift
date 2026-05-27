import AVFoundation
import Metal
import AppKit

/// Records shader-processed frames as a video file (.mov).
///
/// Inspired by RetroVisor's video recording with effects applied.
/// Takes MTLTexture frames from the existing capture/render pipeline
/// and writes them to disk using AVAssetWriter.
///
/// Usage:
///   let recorder = ShaderRecorder(device: device)
///   try recorder.startRecording(width: 1920, height: 1080)
///   // In render loop:
///   recorder.addFrame(texture: renderedTexture)
///   // When done:
///   recorder.stopRecording { url in print("Saved: \(url)") }
final class ShaderRecorder {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var frameCount: Int = 0
    private var targetFPS: Int = 30

    private(set) var isRecording = false
    private(set) var outputURL: URL?
    private(set) var duration: TimeInterval = 0

    /// Notification posted when recording state changes.
    static let stateChangedNotification = Notification.Name("ShaderRecorderStateChanged")

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }

    /// Start recording to a temporary file.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels
    ///   - height: Frame height in pixels
    ///   - fps: Target frames per second (default 30)
    func startRecording(width: Int, height: Int, fps: Int = 30) throws {
        guard !isRecording else { return }

        targetFPS = fps
        frameCount = 0
        startTime = nil
        duration = 0

        // Create output URL in temp directory
        let timestamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetroMac_\(timestamp).mov")
        self.outputURL = url

        // Remove existing file if present
        try? FileManager.default.removeItem(at: url)

        // Setup AVAssetWriter
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,  // ~4 bpp
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        writer.add(input)

        guard writer.startWriting() else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "Unknown")
        }

        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.isRecording = true

        NotificationCenter.default.post(name: Self.stateChangedNotification, object: nil)
        print("[Recorder] Started: \(width)x\(height) @\(fps)fps → \(url.lastPathComponent)")
    }

    /// Add a rendered frame from a Metal texture.
    /// Call this from your render loop after the shader has been applied.
    func addFrame(texture: MTLTexture) {
        guard isRecording,
              let input = videoInput,
              let adaptor = pixelBufferAdaptor,
              input.isReadyForMoreMediaData else { return }

        let now = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(targetFPS))
        if startTime == nil { startTime = now }

        // Get pixel buffer from pool
        guard let pool = adaptor.pixelBufferPool else {
            print("[Recorder] No pixel buffer pool available")
            return
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            print("[Recorder] Pixel buffer creation failed: \(status)")
            return
        }

        // Copy Metal texture to pixel buffer
        copyTextureToPixelBuffer(texture: texture, pixelBuffer: pb)

        // Append
        adaptor.append(pb, withPresentationTime: now)

        frameCount += 1
        duration = Double(frameCount) / Double(targetFPS)
    }

    /// Stop recording and finalize the video file.
    /// - Parameter completion: Called with the output URL on success, nil on failure.
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording, let writer = assetWriter else {
            completion(nil)
            return
        }

        isRecording = false
        videoInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            let url = self.outputURL

            DispatchQueue.main.async {
                if writer.status == .completed, let url = url {
                    print("[Recorder] Finished: \(self.frameCount) frames, \(String(format: "%.1f", self.duration))s → \(url.lastPathComponent)")
                    NotificationCenter.default.post(name: Self.stateChangedNotification, object: nil)
                    completion(url)
                } else {
                    print("[Recorder] Failed: \(writer.error?.localizedDescription ?? "unknown")")
                    NotificationCenter.default.post(name: Self.stateChangedNotification, object: nil)
                    completion(nil)
                }
            }
        }
    }

    /// Stop recording and save to user-chosen location via NSSavePanel.
    func stopAndSave() {
        stopRecording { [weak self] tempURL in
            guard let tempURL = tempURL else { return }
            self?.showSavePanel(tempURL: tempURL)
        }
    }

    // MARK: - Private

    private func copyTextureToPixelBuffer(texture: MTLTexture, pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = min(texture.width, CVPixelBufferGetWidth(pixelBuffer))
        let height = min(texture.height, CVPixelBufferGetHeight(pixelBuffer))

        // Use Metal blit for GPU→CPU if texture is in shared/managed storage,
        // otherwise fall back to getBytes
        texture.getBytes(
            baseAddress,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: .init(), size: .init(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )
    }

    private func showSavePanel(tempURL: URL) {
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.nameFieldStringValue = "RetroMac Recording.mov"
        panel.allowedContentTypes = [.movie]
        panel.canCreateDirectories = true

        // Default to Desktop
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        panel.begin { response in
            if response == .OK, let targetURL = panel.url {
                do {
                    try? FileManager.default.removeItem(at: targetURL)
                    try FileManager.default.moveItem(at: tempURL, to: targetURL)
                    print("[Recorder] Saved to: \(targetURL.path)")

                    // Reveal in Finder
                    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                } catch {
                    print("[Recorder] Save failed: \(error)")
                    let alert = NSAlert()
                    alert.messageText = "Save Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            } else {
                // Clean up temp file if user cancels
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    enum RecorderError: Error, LocalizedError {
        case writerFailed(String)
        var errorDescription: String? {
            switch self {
            case .writerFailed(let reason): return "Video writer failed: \(reason)"
            }
        }
    }
}
