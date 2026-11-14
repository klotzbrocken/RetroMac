import AppKit
import WebKit

/// The BIOS setup's settings. Two of them do something (Quick POST, the floppy seek), the
/// rest are kept as set and shown again next time, as CMOS did.
struct BIOSPrefs: Codable, Equatable {
    var quickPOST = true
    var floppySeek = true
    /// Every other field of every BIOS, by "profile/field".
    var values: [String: String] = [:]
}

/// What the firmware and OS boot pages show of this Mac, read once per boot. Real values,
/// labelled as such on the page: an Apple Silicon Mac has no Award BIOS, so nothing here
/// pretends to be a 1996 board.
enum BootHostData {
    static func current(now: Date = Date()) -> [String: Any] {
        let memory = SystemSampler.sysctlUInt64("hw.memsize") ?? 0
        let date = DateFormatter(), time = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX"); time.locale = date.locale
        date.dateFormat = "MM/dd/yyyy"; time.dateFormat = "HH:mm:ss"
        return [
            "model": sysctlString("hw.model") ?? "Mac",
            "cpu": ClassicAbout.processor,
            "cores": Int(SystemSampler.sysctlUInt64("hw.ncpu") ?? 1),
            "memoryKiB": Int(memory / 1024),
            "date": date.string(from: now),
            "time": time.string(from: now),
        ]
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

/// Forwards the boot page's messages; a separate object because the content controller keeps
/// a strong reference to its handler.
final class BootPageHandler: NSObject, WKScriptMessageHandler {
    let onMessage: ([String: Any]) -> Void
    init(_ onMessage: @escaping ([String: Any]) -> Void) { self.onMessage = onMessage }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { onMessage(body) }
    }
}

/// The boot page's web view: it takes the keyboard (DEL, the setup's arrows) and the clicks.
final class BootWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
