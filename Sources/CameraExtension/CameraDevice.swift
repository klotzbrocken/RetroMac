import Foundation
import CoreMediaIO
import os.log

private let logger = Logger(subsystem: "com.retromac.app.camera", category: "Device")

/// Custom CMIO property used to receive the host's global IOSurface ID across the
/// host↔extension user boundary. Key format is the DAL's required
/// `4cc_<selector>_<scope>_<element>`: selector 'sfid', global scope, main element.
/// The host writes it via CMIOObjectSetPropertyData (selector FourCharCode 'sfid').
let kSurfaceIDProperty = CMIOExtensionProperty(rawValue: "4cc_sfid_glob_0000")

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

    var availableProperties: Set<CMIOExtensionProperty> { [kSurfaceIDProperty] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let dp = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(kSurfaceIDProperty) {
            // NSString round-trips on all macOS versions (NSNumber is broken on 12.x).
            let value = NSString(string: String(streamSource?.hostSurfaceID ?? 0))
            dp.setPropertyState(CMIOExtensionPropertyState(value: value), forProperty: kSurfaceIDProperty)
        }
        return dp
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        guard let state = deviceProperties.propertiesDictionary[kSurfaceIDProperty] else { return }
        if let s = state.value as? String, let id = Int(s) {
            streamSource?.setSurfaceIDFromHost(id)
        } else if let n = state.value as? NSNumber {
            streamSource?.setSurfaceIDFromHost(n.intValue)
        }
    }
}
