import AppKit

/// A curated Soqueroeu TV background: 4K PNG in the author's GitHub repo plus the
/// measured tube region (relative, TOP-LEFT origin: x, y, w, h) where the video goes.
struct TVBezel: Codable, Identifiable {
    var id: String { file }
    let file: String        // e.g. "G02.png"
    let name: String        // display name
    let dir: String         // repo path, e.g. "img/_Generic"
    let rect: [Double]      // tube region [x, y, w, h], relative, top-left origin
    let device: [Double]?   // TV-set bounding box (windowed mode crops the scene to this)
}

/// Curated bezel list + on-demand download. The Soqueroeu repo carries no license, so
/// RetroMac never redistributes the images — each PNG is fetched from the author's
/// GitHub on first use and cached in Application Support.
final class BezelStore {
    static let shared = BezelStore()
    private init() {}

    private let rawBase = "https://raw.githubusercontent.com/soqueroeu/Soqueroeu-TV-Backgrounds_V2.0/main"

    private(set) lazy var available: [TVBezel] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("TV/bezels.json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([TVBezel].self, from: data) else { return [] }
        return list
    }()

    func bezel(named file: String) -> TVBezel? { available.first { $0.file == file } }

    var cacheDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/TVBezels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func localURL(for bezel: TVBezel) -> URL { cacheDir.appendingPathComponent(bezel.file) }
    func isDownloaded(_ bezel: TVBezel) -> Bool { FileManager.default.fileExists(atPath: localURL(for: bezel).path) }

    /// Fetch the bezel PNG from the author's repo (5–15 MB). Completion on main.
    func download(_ bezel: TVBezel, completion: @escaping (Result<URL, Error>) -> Void) {
        let path = "\(rawBase)/\(bezel.dir)/\(bezel.file)"
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            completion(.failure(NSError(domain: "Bezel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])))
            return
        }
        let dest = localURL(for: bezel)
        URLSession.shared.downloadTask(with: url) { tmp, response, error in
            // The temp file dies the moment this handler returns — move it HERE,
            // synchronously; only the result hops to main. (Deferring the move to
            // the main queue made downloads fail depending on pure timing luck.)
            let result: Result<URL, Error>
            if let error = error {
                result = .failure(error)
            } else if let tmp = tmp, (response as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    result = .success(dest)
                } catch { result = .failure(error) }
            } else {
                result = .failure(NSError(domain: "Bezel", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))"]))
            }
            if case .failure(let e) = result { print("[Bezel] Download \(bezel.file) failed: \(e.localizedDescription)") }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
