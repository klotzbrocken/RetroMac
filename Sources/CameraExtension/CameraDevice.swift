import Foundation
import CoreMediaIO
import os.log

private let logger = Logger(subsystem: "com.retromac.app.camera", category: "Device")

final class RetroMacCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    var streamSource: RetroMacCameraStreamSource!

    override init() {
        super.init()

        let deviceID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!

        device = CMIOExtensionDevice(
            localizedName: "RetroMac Cam",
            deviceID: deviceID,
            legacyDeviceID: nil,
            source: self
        )

        let formatDesc = Self.makeFormatDescription(width: 1280, height: 720)
        let streamFormat = CMIOExtensionStreamFormat(
            formatDescription: formatDesc,
            maxFrameDuration: CMTime(value: 1, timescale: 30),
            minFrameDuration: CMTime(value: 1, timescale: 30),
            validFrameDurations: nil
        )

        streamSource = RetroMacCameraStreamSource(
            localizedName: "RetroMac Cam",
            streamID: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!,
            streamFormat: streamFormat,
            device: device
        )

        do {
            try device.addStream(streamSource.stream)
            logger.info("Stream added to device")
        } catch {
            logger.error("Failed to add stream: \(error.localizedDescription)")
        }
    }

    private static func makeFormatDescription(width: Int32, height: Int32) -> CMFormatDescription {
        var desc: CMFormatDescription!
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &desc
        )
        return desc
    }

    var availableProperties: Set<CMIOExtensionProperty> { [] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        CMIOExtensionDeviceProperties(dictionary: [:])
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        // No settable properties
    }
}
