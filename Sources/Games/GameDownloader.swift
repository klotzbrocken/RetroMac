import AppKit

/// Fetches a title's game data from the Internet Archive.
///
/// This is the first download path in the app that reports real bytes. Everything before it used
/// `URLSession.downloadTask(with:)` with a completion handler and an indeterminate spinner, which
/// is fine for a 5 MB bezel and useless for a 184 MB pak file.
///
/// Two properties of the source shape the design:
///
///  - Members inside an archive are extracted **on the fly** by the Archive, so those responses
///    carry no `Content-Length`. Progress is therefore reported against the size in the catalogue,
///    which was read from the archive's own index, and clamped so a slightly-off total can never
///    show more than 100%.
///  - Downloads land through the copy-then-swap dance `ThemeManager.install` uses: staging inside
///    the destination folder (same volume, so `replaceItemAt` is atomic), so an interrupted or
///    failed download can never leave a half-written WAD where a working one used to be.
final class GameDownloader: NSObject {

    static let shared = GameDownloader()
    private override init() { super.init() }

    struct Progress {
        let received: Int64
        let expected: Int64
        let memberIndex: Int
        let memberCount: Int
        var fraction: Double { expected > 0 ? min(1, Double(received) / Double(expected)) : 0 }
    }

    enum Failure: LocalizedError {
        case noDestination(String)
        /// Another title is already downloading.
        case busy(String)
        case http(Int)
        case transport(String)
        case install(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noDestination(let name): return "No folder is set for \(name)."
            case .busy(let other):         return "Still downloading \(other)."
            case .http(let code):          return "The Internet Archive answered \(code)."
            case .transport(let m):        return m
            case .install(let m):          return m
            case .cancelled:               return "Cancelled."
            }
        }
    }

    private var task: URLSessionDownloadTask?
    private var onProgress: ((Progress) -> Void)?
    private var onMemberDone: ((URL) -> Void)?
    private var onFailure: ((Failure) -> Void)?
    /// The title's whole size, and how much of it earlier members already delivered: the bar has
    /// to mean the same thing across a 40-file title as across a one-file one.
    private var titleTotal: Int64 = 0
    private var bytesBefore: Int64 = 0
    private var memberIndex = 0
    private var memberCount = 1

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 60 * 60      // a 184 MB member on a slow line
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    private(set) var activeTitleID: String?
    var isBusy: Bool { activeTitleID != nil }

    /// Set by `cancel`, cleared by `fetch`. Without it a cancel arriving after
    /// `didFinishDownloadingTo` has already dispatched `onMemberDone` was simply ignored: that
    /// block installed its member and called `next(i + 1)`, so a 40-file title carried on
    /// downloading with `activeTitleID` already nil and a card stuck on "downloading" forever.
    private var cancelled = false

    // MARK: - Public entry point

    /// Downloads every member of `title` in turn, then finishes the title off (Warcraft II needs a
    /// second, local extraction step). All callbacks land on the main queue.
    func fetch(_ title: InternetArchive.Title,
               progress: @escaping (Progress) -> Void,
               status: @escaping (String) -> Void,
               completion: @escaping (Result<Void, Failure>) -> Void) {
        // Every exit from here must call `completion`. Returning silently left the caller
        // believing a download was running: the card stayed busy, and every later press was
        // swallowed by its own "one at a time" guard. That is what made a title impossible to
        // download a second time.
        guard !isBusy else {
            completion(.failure(.busy(activeTitleID ?? "another title")))
            return
        }
        guard let folder = InternetArchive.destinationFolder(title) else {
            completion(.failure(.noDestination(title.name))); return
        }
        activeTitleID = title.id
        cancelled = false
        memberCount = title.members.count
        titleTotal = title.bytes
        bytesBefore = 0

        func finish(_ r: Result<Void, Failure>) {
            DispatchQueue.main.async {
                self.activeTitleID = nil
                completion(r)
            }
        }

        // One member after another, each into the staging dance.
        func next(_ i: Int) {
            guard !self.cancelled else { finish(.failure(.cancelled)); return }
            guard i < title.members.count else {
                DispatchQueue.main.async { status("Finishing up…") }
                self.finalise(title, stagedIn: folder) { finish($0) }
                return
            }
            let member = title.members[i]
            memberIndex = i
            guard let url = InternetArchive.downloadURL(title, member: member) else {
                finish(.failure(.transport("Could not build a URL for \(member).")))
                return
            }
            DispatchQueue.main.async {
                status(title.members.count > 1
                       ? "Downloading \((member as NSString).lastPathComponent) (\(i + 1) of \(title.members.count))…"
                       : "Downloading \((member as NSString).lastPathComponent)…")
            }
            self.download(url, to: folder, named: (member as NSString).lastPathComponent,
                          progress: progress) { result in
                switch result {
                case .success: next(i + 1)
                case .failure(let e): finish(.failure(e))
                }
            }
        }
        next(0)
    }

    func cancel() {
        cancelled = true
        task?.cancel()
        task = nil
        activeTitleID = nil
    }

    // MARK: - One member

    private func download(_ url: URL, to folder: URL, named name: String,
                          progress: @escaping (Progress) -> Void,
                          completion: @escaping (Result<Void, Failure>) -> Void) {
        onProgress = progress
        onFailure = { completion(.failure($0)) }
        onMemberDone = { [weak self] temp in
            if self?.cancelled == true {
                try? FileManager.default.removeItem(at: temp)
                completion(.failure(.cancelled))
                return
            }
            do {
                try Self.install(temp, into: folder, as: name)
                completion(.success(()))
            } catch {
                completion(.failure(.install(error.localizedDescription)))
            }
        }
        let t = session.downloadTask(with: url)
        task = t
        t.resume()
    }

    /// Copy-then-swap, the pattern `ThemeManager.install(bundleAt:into:replacing:)` uses: stage in
    /// the destination folder so the volume matches and `replaceItemAt` is atomic. A download that
    /// dies half-way therefore leaves whatever was there untouched.
    private static func install(_ src: URL, into folder: URL, as name: String) throws {
        let fm = FileManager.default
        let dest = folder.appendingPathComponent(name)
        let staging = folder.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let staged = staging.appendingPathComponent(name)
        try fm.moveItem(at: src, to: staged)
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: dest)
        }
    }

    // MARK: - After the last member

    private func finalise(_ title: InternetArchive.Title, stagedIn folder: URL,
                          completion: @escaping (Result<Void, Failure>) -> Void) {
        guard case .warcraftInstall(let wc) = title.destination else {
            completion(.success(()))
            return
        }
        // The extractor wants the DOS install directory: data.war / maindat.war beside their
        // siblings, which is exactly what was just staged.
        WarcraftGame.extract(wc, from: folder) { result in
            switch result {
            case .success(let dest):
                if wc == .warcraft2 { AppSettings.shared.warcraft2DataFolder = dest.path }
                else               { AppSettings.shared.warcraft1DataFolder = dest.path }
                try? FileManager.default.removeItem(at: folder)   // the DOS files are spent
                completion(.success(()))
            case .failure(let e):
                completion(.failure(.install(e.message)))
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

/// Every method here first checks that the callback belongs to the task the downloader is
/// currently running, because the per-job state (`onProgress`, `onMemberDone`, `onFailure`,
/// `bytesBefore`, `titleTotal`) lives on the instance and is overwritten by the next job.
///
/// A cancelled task still delivers its callbacks afterwards, and `cancel()` frees the downloader
/// immediately, so without this guard a second title could already be running when they arrive.
/// The failure case merely produced a wrong error; the finish case was worse — the first title's
/// bytes were handed to the second title's install closure and written into ITS folder under ITS
/// filename, so a cancelled Heretic member could replace a perfectly good DOOM2.WAD.
extension GameDownloader: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard downloadTask === self.task else { return }   // see the note above this extension
        // `totalBytesExpectedToWrite` is -1 for members the Archive extracts on the fly, which is
        // most of them, so the catalogue's measured total carries the bar. Earlier members are
        // counted in, otherwise Warcraft's 40 files would restart the bar forty times.
        let p = Progress(received: bytesBefore + totalBytesWritten, expected: titleTotal,
                         memberIndex: memberIndex, memberCount: memberCount)
        DispatchQueue.main.async { self.onProgress?(p) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard downloadTask === self.task else { return }   // see the note above this extension
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let code = http.statusCode
            DispatchQueue.main.async { self.onFailure?(.http(code)) }
            return
        }
        // A wrong member path does NOT answer 404: the Archive extracts nothing and returns 200
        // with an empty body, which would otherwise be installed as a perfectly valid-looking
        // zero-byte WAD. Anything far short of the expected size is treated as a failure.
        let got = ((try? FileManager.default.attributesOfItem(atPath: location.path))?[.size] as? Int64) ?? 0
        let tooSmall = got == 0 || (memberCount == 1 && titleTotal > 0 && got < titleTotal / 2)
        if tooSmall {
            DispatchQueue.main.async {
                self.onFailure?(.transport("The Internet Archive returned no data for this file (\(got) bytes)."))
            }
            return
        }
        bytesBefore += got
        // Move it out of the session's temp area synchronously, before this method returns:
        // deferring it to another queue is what made BezelStore's downloads flaky.
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent("retromac-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: keep)
        } catch {
            let m = error.localizedDescription
            DispatchQueue.main.async { self.onFailure?(.transport(m)) }
            return
        }
        DispatchQueue.main.async { self.onMemberDone?(keep) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task else { return }              // see the note above this extension
        guard let error = error as NSError? else { return }   // success already handled above
        let f: Failure = error.code == NSURLErrorCancelled ? .cancelled : .transport(error.localizedDescription)
        DispatchQueue.main.async { self.onFailure?(f) }
    }
}
