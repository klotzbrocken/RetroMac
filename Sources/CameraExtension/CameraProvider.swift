import Foundation
import CoreMediaIO
import os.log

private let logger = Logger(subsystem: "com.retromac.app.camera", category: "Provider")

final class RetroMacCameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: RetroMacCameraDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = RetroMacCameraDeviceSource()

        do {
            try provider.addDevice(deviceSource.device)
            logger.info("RetroMac Camera device added successfully")
        } catch {
            logger.error("Failed to add camera device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        os_log("[RetroMacCam] Client connected", log: .default, type: .default)
    }

    func disconnect(from client: CMIOExtensionClient) {
        os_log("[RetroMacCam] Client disconnected", log: .default, type: .default)
    }

    var availableProperties: Set<CMIOExtensionProperty> { [] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        CMIOExtensionProviderProperties(dictionary: [:])
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // No settable properties
    }
}
