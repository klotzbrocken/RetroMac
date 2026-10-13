import AppKit
import QuickLookThumbnailing

/// "Display as Stack", 10.5 to 10.8: a folder in the dock shows its newest files piled up, the
/// latest on top, and the pile changes as files arrive. Pictures and documents show their Quick
/// Look preview in a white frame, everything else its icon.
final class StackPreview {
    static let shared = StackPreview()
    private init() {}

    /// Called on the main queue with a folder whose pile changed (a file arrived, a preview came in).
    var onChange: ((String) -> Void)?

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var pending: [String: DispatchWorkItem] = [:]
    private let thumbs = NSCache<NSString, NSImage>()
    private var requested = Set<String>()

    /// The pile for `folder`, or nil when it is empty (the dock then shows the folder itself).
    func icon(for folder: String, size: CGFloat) -> NSImage? {
        watch(folder)
        let newest = Self.newestFiles(in: folder, limit: 3)
        guard !newest.isEmpty else { return nil }
        let pictures = newest.map { picture(for: $0, folder: folder, size: size) }
        return Self.pile(pictures, size: size)
    }

    /// Newest first, by the date each file was added to the folder (what Downloads sorts by).
    static func newestFiles(in folder: String, limit: Int) -> [URL] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder),
                                                                        includingPropertiesForKeys: keys,
                                                                        options: [.skipsHiddenFiles]) else { return [] }
        func added(_ u: URL) -> Date {
            let v = try? u.resourceValues(forKeys: Set(keys))
            return v?.addedToDirectoryDate ?? v?.creationDate ?? .distantPast
        }
        return Array(items.map { ($0, added($0)) }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0))
    }

    /// The pile, oldest at the back: each one a little turned, the newest straight on top.
    static func pile(_ pictures: [(image: NSImage, framed: Bool)], size: CGFloat) -> NSImage {
        let tilts: [CGFloat] = [0, 5, -7]      // newest, second, third
        let shifts: [CGPoint] = [.zero, CGPoint(x: 2, y: 2), CGPoint(x: -2, y: 3)]
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            for i in pictures.indices.reversed() {
                let (img, framed) = pictures[i]
                let box = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.06)   // as full as the icons beside it
                let s = min(box.width / max(img.size.width, 1), box.height / max(img.size.height, 1))
                let w = img.size.width * s, h = img.size.height * s
                ctx.saveGState()
                ctx.translateBy(x: rect.midX + shifts[i].x * size / 64, y: rect.midY + shifts[i].y * size / 64)
                ctx.rotate(by: tilts[i] * .pi / 180)
                let r = NSRect(x: -w / 2, y: -h / 2, width: w, height: h)
                if framed {
                    let edge = max(2, size * 0.04)
                    let frame = r.insetBy(dx: -edge, dy: -edge)
                    let shadow = NSShadow(); shadow.shadowBlurRadius = size * 0.04
                    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.015); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
                    shadow.set()
                    NSColor.white.setFill(); frame.fill()
                    NSShadow().set()
                }
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                ctx.restoreGState()
            }
            return true
        }
    }

    /// A file's Quick Look preview when there is one (asked for once, in the background), its
    /// icon meanwhile and otherwise.
    private func picture(for url: URL, folder: String, size: CGFloat) -> (image: NSImage, framed: Bool) {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(mtime)" as NSString
        if let t = thumbs.object(forKey: key) { return (t, true) }
        if requested.insert(key as String).inserted {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale,
                                                   representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
                guard let self, let rep else { return }
                DispatchQueue.main.async {
                    self.thumbs.setObject(rep.nsImage, forKey: key)
                    self.onChange?(folder)
                }
            }
        }
        return (NSWorkspace.shared.icon(forFile: url.path), false)
    }

    /// The folder watched for new files; a burst of changes (a download in progress) is told once.
    private func watch(_ folder: String) {
        guard watchers[folder] == nil else { return }
        let fd = open(folder, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending[folder]?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange?(folder) }
            self.pending[folder] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers[folder] = src
    }
}
