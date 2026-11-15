import AppKit
import CryptoKit

/// One Microsoft Agent character in clippy.js's unpacked form (github.com/clippyjs/clippy.js, MIT):
/// `agent.js` holds the animations as JSON inside `clippy.ready('Name', {…})`, `map.png` the sprite
/// sheet, `sounds-mp3.js` the sounds as data URLs inside `clippy.soundsReady('Name', {…})`.
/// The characters themselves are Microsoft's (LEGAL.md).
struct AgentCharacter {
    struct Branch: Decodable, Equatable { let frameIndex: Int; let weight: Int }
    struct Branching: Decodable, Equatable { let branches: [Branch] }
    struct Frame: Decodable, Equatable {
        let duration: Int
        let images: [[Int]]?
        let sound: String?
        let exitBranch: Int?
        let branching: Branching?
    }
    struct Animation: Decodable, Equatable {
        let frames: [Frame]
        let useExitBranching: Bool?
    }
    private struct Manifest: Decodable {
        let framesize: [Int]
        let overlayCount: Int
        let animations: [String: Animation]
    }

    let name: String
    let frameSize: CGSize
    let overlayCount: Int
    let animations: [String: Animation]
    let sheet: CGImage
    let sounds: [String: Data]

    /// The object literal between the wrapper's first `{` and last `}`.
    static func objectLiteral(_ script: String) -> Substring? {
        guard let a = script.firstIndex(of: "{"), let b = script.lastIndex(of: "}"), a < b else { return nil }
        return script[a...b]
    }

    static func parseAnimations(_ script: String) -> (CGSize, Int, [String: Animation])? {
        guard let body = objectLiteral(script),
              let m = try? JSONDecoder().decode(Manifest.self, from: Data(body.utf8)),
              m.framesize.count == 2, m.framesize[0] > 0, m.framesize[1] > 0, !m.animations.isEmpty else { return nil }
        return (CGSize(width: m.framesize[0], height: m.framesize[1]), max(1, m.overlayCount), m.animations)
    }

    /// `{'1':'data:audio/mpeg;base64,…'}`: single-quoted, and base64 holds no quote, so a swap
    /// makes it JSON.
    static func parseSounds(_ script: String) -> [String: Data] {
        guard let body = objectLiteral(script),
              let raw = try? JSONDecoder().decode([String: String].self,
                                                  from: Data(body.replacingOccurrences(of: "'", with: "\"").utf8)) else { return [:] }
        return raw.compactMapValues { url in
            url.range(of: "base64,").flatMap { Data(base64Encoded: String(url[$0.upperBound...])) }
        }
    }

    static func load(name: String, from dir: URL) -> AgentCharacter? {
        guard let js = try? String(contentsOf: dir.appendingPathComponent("agent.js"), encoding: .utf8),
              let (size, overlays, animations) = parseAnimations(js),
              let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("map.png") as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let sounds = (try? String(contentsOf: dir.appendingPathComponent("sounds-mp3.js"), encoding: .utf8)).map(parseSounds) ?? [:]
        return AgentCharacter(name: name, frameSize: size, overlayCount: overlays, animations: animations,
                              sheet: sheet, sounds: sounds)
    }

    // MARK: - What the animation names mean

    /// The moments RetroMac has something to say. Every character names its animations a little
    /// differently (Clippy "Greeting", Merlin "Greet", Rover neither), so each lists candidates.
    enum Moment: CaseIterable {
        case greet, alert, explain, congratulate, think, write, search, goodbye, clipboard, trash, hide, show
        var candidates: [String] {
            switch self {
            case .greet: return ["Greeting", "Greet", "Wave"]
            case .alert: return ["GetAttention", "Alert", "Surprised", "Acknowledge"]
            case .explain: return ["Explain", "Suggest", "Announce", "Acknowledge"]
            case .congratulate: return ["Congratulate", "Pleased", "CharacterSucceeds"]
            case .think: return ["Thinking", "Think", "Processing"]
            case .write: return ["Writing", "Write"]
            case .search: return ["Searching", "Search", "ImageSearching"]
            case .goodbye: return ["GoodBye", "Goodbye", "Wave"]
            case .clipboard: return ["CheckingSomething", "Writing", "Write"]
            case .trash: return ["EmptyTrash", "Acknowledge"]
            case .hide: return ["Hide"]
            case .show: return ["Show"]
            }
        }
    }

    func animation(for moment: Moment) -> String? {
        moment.candidates.first { animations[$0] != nil }
    }

    /// clippy.js picks idles by prefix; "DeepIdle" and "Idle(3)" count too.
    var idleAnimations: [String] {
        animations.keys.filter { $0.hasPrefix("Idle") || $0.hasPrefix("DeepIdle") }.sorted()
    }

    /// The sprite at one sheet position, cropped (shares the sheet's pixels).
    private static var cropCache: [String: [Int: CGImage]] = [:]
    func sprite(_ xy: [Int]) -> CGImage? {
        guard xy.count == 2 else { return nil }
        let key = xy[0] << 16 | xy[1]
        if let hit = Self.cropCache[name]?[key] { return hit }
        let img = sheet.cropping(to: CGRect(x: xy[0], y: xy[1], width: Int(frameSize.width), height: Int(frameSize.height)))
        Self.cropCache[name, default: [:]][key] = img
        return img
    }
    static func dropCache(except name: String?) { cropCache = cropCache.filter { $0.key == name } }
}

/// Steps through one animation the way clippy.js's Animator does: weighted branches, and when the
/// animation is asked to end, each frame's `exitBranch` leads the way out instead of a cut.
struct AgentAnimator {
    enum Event { case none, waiting, exited }

    let animation: AgentCharacter.Animation
    private(set) var index: Int?
    var exiting = false

    init(_ animation: AgentCharacter.Animation) { self.animation = animation }

    var frame: AgentCharacter.Frame? { index.map { animation.frames[$0] } }

    /// Moves one frame on. `roll` is a number in 0..<100.
    mutating func step(roll: Double) -> Event {
        let frames = animation.frames
        guard !frames.isEmpty else { return .exited }
        var next: Int
        if let i = index {
            let f = frames[i]
            next = i + 1
            if exiting, let e = f.exitBranch {
                next = e
            } else if let branches = f.branching?.branches {
                var r = roll
                for b in branches {
                    if r <= Double(b.weight) { next = b.frameIndex; break }
                    r -= Double(b.weight)
                }
            }
        } else {
            next = 0
        }
        next = max(0, min(next, frames.count - 1))
        let changed = index != next
        index = next
        guard changed, next == frames.count - 1 else { return .none }
        return (animation.useExitBranching == true && !exiting) ? .waiting : .exited
    }
}

/// Which characters there are and where their files come from. Clippy and Genius ship inside the
/// app; the others are fetched from clippy.js at a fixed commit when picked, checked against the
/// hashes below, and kept in Application Support. Bonzi is left out on purpose (it was adware).
enum AgentCatalog {
    static let bundled = ["Clippy", "Genius"]
    static let downloadable = ["F1", "Genie", "Links", "Merlin", "Peedy", "Rocky", "Rover"]
    static var all: [String] { bundled + downloadable }
    static let files = ["agent.js", "map.png", "sounds-mp3.js"]

    static let commit = "8bfd1f92c725c6bc3a435d538a77c3302b327c08"
    static func remoteURL(_ name: String, _ file: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/clippyjs/clippy.js/\(commit)/agents/\(name)/\(file)")!
    }

    /// What each character was in Office or Microsoft Agent, for the picker.
    static func title(_ name: String) -> String {
        switch name {
        case "Clippy": return "Clippy (Clippit)"
        case "Genius": return "The Genius"
        case "F1": return "F1 (robot)"
        case "Links": return "Links (cat)"
        case "Peedy": return "Peedy (parrot)"
        case "Rocky": return "Rocky (dog)"
        case "Rover": return "Rover (Windows XP search)"
        default: return name
        }
    }

    static let sha256: [String: String] = [
        "F1/agent.js": "055d6866bbba1093230a126dd85d61a247a53ed378bdbee018f7c7f83b92c9b3",
        "F1/map.png": "bab75daa14177b3f5d8c29ca1b42f8b22642bf0992819860c7121cae4712595a",
        "F1/sounds-mp3.js": "9e10b233b7a717d15727b6e2fe8935ef90759e8dcc63c0bf08119bd3cd716134",
        "Genie/agent.js": "ff4492899da88339e14e93db33d911c8d884fa765164d223cc2f06f3f68b3482",
        "Genie/map.png": "1c613b999b035eaed07db5f0f272e868df1935b03ec0e26d5af983c673d9348d",
        "Genie/sounds-mp3.js": "220b506f0925aafefcced16b5dc17db84cd041617983172d269e2cacf473e9c6",
        "Links/agent.js": "ceec156ee32a0c7d699fee78378546a6137ca7af872aa4745b0fac87d005db18",
        "Links/map.png": "f5a8624241942db98b67a0329560d66f992e3b20fb7e1e52b6e1a12ca3a5952c",
        "Links/sounds-mp3.js": "37ee78cb41ae7380ff9aa7f5c7426594d3c97465a2b319a446cf704fe7e8dab8",
        "Merlin/agent.js": "a5d1496ebfe46efb72e7db2dce1f8748886ddc536429235e25660c176f9b0fbd",
        "Merlin/map.png": "075a09c616f8c327a03f19b932f7ffe27db1e4e94643844fe4cc8e5aff6e5894",
        "Merlin/sounds-mp3.js": "a0d25d3e1b1d06024d71b3a473c09eb1ab5a22a9f9919414c9d44a97227e7b81",
        "Peedy/agent.js": "4d8ec0fc3cce6acc8dbdba03c9f1a292ae0c211a044f640bfbc9aadbf546e858",
        "Peedy/map.png": "d7d55a8637fea52eb0aeb7729427acc84e5e22661df863e2cecae51b5b395b53",
        "Peedy/sounds-mp3.js": "55ba96ca5a45065a0cd2b023dfa0274010505da8619ab9424f243461e0bdd81a",
        "Rocky/agent.js": "00ee4d0be900ead5ba5637acea6a3d8875de4c1f3c196d4d9477921716e6dc5c",
        "Rocky/map.png": "a11451edad2b5d9739af320068e89982aad9f3639378c23b5d28c9757835e1f5",
        "Rocky/sounds-mp3.js": "b0c9643b24c68b4dfccffeada13db6e627f4940714e8e449b6bdda3560900897",
        "Rover/agent.js": "89c7e644bda5bfc3e59f3f566506779a49b771a9a93407cd9870e20f6a8121ef",
        "Rover/map.png": "dfa1d61a77f7237dc4cd439fc8b0d14e92608fe89d24cb332ad89f3194433cfa",
        "Rover/sounds-mp3.js": "a662385e39ce33bc54efd3ee7806131db3b2a4a3276a0165f49b1b289cf7ac07",
    ]

    static var cacheRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroMac/Agents")
    }

    /// Where the character's three files are, or nil while it is not downloaded.
    static func directory(for name: String) -> URL? {
        let dir = bundled.contains(name)
            ? Bundle.main.resourceURL?.appendingPathComponent("Agents/\(name)")
            : cacheRoot.appendingPathComponent(name)
        guard let dir, files.allSatisfy({ FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }) else { return nil }
        return dir
    }

    static func isAvailable(_ name: String) -> Bool { directory(for: name) != nil }

    static func verify(_ data: Data, path: String) -> Bool {
        guard let want = sha256[path] else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == want
    }

    private static var running: Set<String> = []

    /// Fetches all three files; nothing is kept unless every one matches its hash.
    static func download(_ name: String, completion: @escaping (Bool) -> Void) {
        guard downloadable.contains(name), !running.contains(name) else { completion(isAvailable(name)); return }
        running.insert(name)
        let group = DispatchGroup()
        var got: [String: Data] = [:]
        let lock = NSLock()
        for file in files {
            group.enter()
            URLSession.shared.dataTask(with: remoteURL(name, file)) { data, response, _ in
                if let data, (response as? HTTPURLResponse)?.statusCode == 200, verify(data, path: "\(name)/\(file)") {
                    lock.lock(); got[file] = data; lock.unlock()
                }
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) {
            running.remove(name)
            guard got.count == files.count else {
                NSLog("[Companion] download of \(name) failed (\(got.count)/\(files.count) verified)")
                completion(false); return
            }
            let dir = cacheRoot.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for (file, data) in got { try data.write(to: dir.appendingPathComponent(file), options: .atomic) }
                completion(true)
            } catch {
                NSLog("[Companion] could not save \(name): \(error.localizedDescription)")
                completion(false)
            }
        }
    }
}
