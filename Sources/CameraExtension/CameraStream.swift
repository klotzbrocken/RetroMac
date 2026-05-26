import Foundation
import CoreMediaIO
import CoreVideo
import IOSurface
import os.log

/// Reads processed frames from a shared IOSurface (written by the main RetroMac app)
/// and provides them as a virtual camera stream.
final class RetroMacCameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!

    private var frameTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.retromac.camera.frames", qos: .userInteractive)
    private var isStreaming = false

    private let outputWidth = 1280
    private let outputHeight = 720
    private let _streamFormat: CMIOExtensionStreamFormat

    // Sequence counter for CMSampleBuffer timing
    private var sequenceNumber: UInt64 = 0

    // Pre-allocated pixel buffer pool for consistent IOSurface-backed buffers
    private var bufferPool: CVPixelBufferPool?

    // IOSurface ID received from main app
    private var currentSurfaceID: Int = 0

    // App Group UserDefaults — primary IPC channel for surface ID
    private let sharedDefaults = UserDefaults(suiteName: "FTJLR8JRNS.com.retromac.app")

    // Timer for polling shared config
    private var configPollTimer: DispatchSourceTimer?

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self._streamFormat = streamFormat
        super.init()

        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )

        // Pre-create pixel buffer pool
        setupBufferPool()

        // Poll IOSurface ID from App Group (secure IPC)
        startConfigPolling()

        os_log("[RetroMacCam] Stream init %{public}dx%{public}d pool=%{public}d",
               log: .default, type: .default, outputWidth, outputHeight, bufferPool != nil ? 1 : 0)
    }

    // MARK: - Pixel Buffer Pool

    private func setupBufferPool() {
        let poolAttrs: NSDictionary = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3
        ]
        let pixelBufferAttrs: NSDictionary = [
            kCVPixelBufferWidthKey: outputWidth,
            kCVPixelBufferHeightKey: outputHeight,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs, pixelBufferAttrs, &pool)
        if status == kCVReturnSuccess {
            bufferPool = pool
        } else {
            os_log("[RetroMacCam] BufferPool FAILED %{public}d", log: .default, type: .error, status)
        }
    }

    // MARK: - App Group IPC

    private func startConfigPolling() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.pollSurfaceID()
        }
        timer.resume()
        configPollTimer = timer
        os_log("[RetroMacCam] Polling started (every 1s) via App Group UserDefaults",
               log: .default, type: .default)
    }

    private func pollSurfaceID() {
        let newID = readSurfaceID()
        if newID != currentSurfaceID && newID > 0 {
            os_log("[RetroMacCam] Polled surfaceID=%{public}d (was %{public}d)",
                   log: .default, type: .default, newID, currentSurfaceID)
            currentSurfaceID = newID
        }
    }

    /// Read IOSurface ID from App Group UserDefaults (primary) or container file (fallback)
    private func readSurfaceID() -> Int {
        // Primary: App Group UserDefaults
        let defaultsID = sharedDefaults?.integer(forKey: "ioSurfaceID") ?? 0
        if defaultsID > 0 {
            return defaultsID
        }

        // Fallback: App Group container file
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "FTJLR8JRNS.com.retromac.app") {
            let configFile = groupURL.appendingPathComponent("camera_surface_id")
            if let content = try? String(contentsOf: configFile, encoding: .utf8) {
                return Int(content.components(separatedBy: "\n").first ?? "0") ?? 0
            }
        }

        return 0
    }

    // MARK: - CMIOExtensionStreamSource

    var formats: [CMIOExtensionStreamFormat] { [_streamFormat] }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> { [] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        CMIOExtensionStreamProperties(dictionary: [:])
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        os_log("[RetroMacCam] authorizedToStartStream", log: .default, type: .default)
        return true
    }

    func startStream() throws {
        guard !isStreaming else {
            os_log("[RetroMacCam] startStream: already streaming", log: .default, type: .default)
            return
        }
        isStreaming = true
        sequenceNumber = 0
        os_log("[RetroMacCam] startStream: starting timer", log: .default, type: .default)
        startFrameTimer()
    }

    func stopStream() throws {
        isStreaming = false
        frameTimer?.cancel()
        frameTimer = nil
        os_log("[RetroMacCam] stopStream", log: .default, type: .default)
    }

    // MARK: - Frame Generation

    private func startFrameTimer() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33)) // ~30fps
        timer.setEventHandler { [weak self] in
            self?.generateFrame()
        }
        timer.resume()
        frameTimer = timer
        os_log("[RetroMacCam] timer started", log: .default, type: .default)
    }

    private var debugLogCounter = 0

    private func generateFrame() {
        guard isStreaming else { return }

        // Use IOSurface ID received via DistributedNotificationCenter (cross-user IPC)
        let surfaceID = currentSurfaceID
        let ioSurface: IOSurfaceRef? = surfaceID > 0 ? IOSurfaceLookup(UInt32(surfaceID)) : nil

        debugLogCounter += 1
        if debugLogCounter == 1 {
            // Log once on first frame which path was used
            os_log("[RetroMacCam] FIRST gen sid=%{public}d surf=%{public}d pool=%{public}d",
                   log: .default, type: .default, surfaceID, ioSurface != nil ? 1 : 0, bufferPool != nil ? 1 : 0)
        }
        if debugLogCounter % 300 == 1 { // Log every ~10 seconds at 30fps
            os_log("[RetroMacCam] gen #%{public}d sid=%{public}d surf=%{public}d sent=%{public}llu",
                   log: .default, type: .default,
                   debugLogCounter, surfaceID, ioSurface != nil ? 1 : 0, sequenceNumber)
        }

        guard surfaceID > 0, let ioSurface = ioSurface else {
            sendBlackFrame()
            return
        }

        // Create CVPixelBuffer from IOSurface (zero-copy)
        var unmanagedPB: Unmanaged<CVPixelBuffer>?
        let status = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            ioSurface,
            nil,
            &unmanagedPB
        )

        guard status == kCVReturnSuccess, let pb = unmanagedPB?.takeRetainedValue() else {
            if debugLogCounter % 300 == 1 {
                os_log("[RetroMacCam] IOSurf->PB fail %{public}d", log: .default, type: .error, status)
            }
            sendBlackFrame()
            return
        }

        sendPixelBuffer(pb)
    }

    // readSurfaceID() replaced by readSurfaceIDFromFile() + polling timer above

    private func sendBlackFrame() {
        // Use pool for consistent IOSurface-backed buffers
        guard let pool = bufferPool else {
            if debugLogCounter % 300 == 1 {
                os_log("[RetroMacCam] no pool", log: .default, type: .error)
            }
            return
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            if debugLogCounter % 300 == 1 {
                os_log("[RetroMacCam] pool create fail %{public}d", log: .default, type: .error, status)
            }
            return
        }

        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            memset(base, 0, CVPixelBufferGetDataSize(pb))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        sendPixelBuffer(pb)
    }

    private func sendPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        var formatDesc: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard let desc = formatDesc else {
            os_log("[RetroMacCam] fmtDesc fail", log: .default, type: .error)
            return
        }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard let buffer = sampleBuffer else {
            os_log("[RetroMacCam] sampleBuf fail", log: .default, type: .error)
            return
        }

        let hostTime = UInt64(now.seconds * 1_000_000_000)

        // First frame needs .time + .sampleDropped discontinuity flags
        let discontinuity: CMIOExtensionStream.DiscontinuityFlags = sequenceNumber == 0
            ? [.time, .sampleDropped]
            : []

        stream.send(buffer, discontinuity: discontinuity, hostTimeInNanoseconds: hostTime)
        sequenceNumber += 1

        if sequenceNumber <= 3 || sequenceNumber % 300 == 0 {
            let hasIOSurface = CVPixelBufferGetIOSurface(pixelBuffer) != nil
            os_log("[RetroMacCam] sent #%{public}llu ios=%{public}d",
                   log: .default, type: .default, sequenceNumber, hasIOSurface ? 1 : 0)
        }
    }
}
