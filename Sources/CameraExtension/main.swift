import Foundation
import CoreMediaIO

let providerSource = RetroMacCameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

// Keep the extension process alive — required for CMIO extensions
CFRunLoopRun()
