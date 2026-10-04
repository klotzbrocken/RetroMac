import XCTest
import SwiftUI
@testable import RetroMac

/// The What's New page of the welcome flow (the one users see) lays out in its fixed size; set RETROMAC_SNAPSHOT_DIR to keep a picture
/// of it, drawn the way AppKit draws it on screen (an off-screen window, never shown).
final class WhatsNewSnapshotTests: XCTestCase {
    @MainActor
    func testWhatsNewRenders() throws {
        let size = NSSize(width: WelcomePage.windowWidth, height: WelcomePage.windowHeight)
        let host = NSHostingView(rootView: WelcomeFlowView(pages: [.whatsNew], onFinish: { _ in }).frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DARK"] != nil ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(host.fittingSize, size)
        guard let dir = ProcessInfo.processInfo.environment["RETROMAC_SNAPSHOT_DIR"],
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        // The window's own background under the view, as on screen.
        let full = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        full.size = rep.size
        host.cacheDisplay(in: host.bounds, to: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: full)
        window.appearance?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill(); NSRect(origin: .zero, size: rep.size).fill()
        }
        rep.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()
        try full.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("whatsnew.png"))
    }
}
