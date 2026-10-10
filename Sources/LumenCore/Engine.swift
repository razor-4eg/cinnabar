import CoreServices
import Foundation
import os

private let helperInfoPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleExecutable</key><string>yt-dlp</string>
<key>CFBundleIdentifier</key><string>app.lumen.downloader.ytdlp</string>
<key>CFBundleName</key><string>Lumen</string>
<key>CFBundleDisplayName</key><string>Lumen</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict>
</plist>
"""

private enum YtDlpRegistration {
    private static let state = OSAllocatedUnfairLock(initialState: false)

    static func register(_ app: URL, force: Bool = false) {
        let shouldRegister = state.withLock { done -> Bool in
            if done, !force { return false }
            done = true
            return true
        }
        guard shouldRegister else { return }
        LSRegisterURL(app as CFURL, true)
    }
}

public struct Engine: Sendable {
    public let supportRoot: URL

    public var binDirectory: URL { supportRoot.appending(path: "bin") }
    public var thumbnailDirectory: URL { supportRoot.appending(path: "Thumbnails") }
    public var libraryFile: URL { supportRoot.appending(path: "library.json") }

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        supportRoot = base.appending(path: "Lumen")
    }

    public var hasManagedComponents: Bool {
        let manager = FileManager.default
        let owned = ["yt-dlp", "_internal", "ffmpeg", "ffprobe"].contains { name in
            manager.fileExists(atPath: binDirectory.appending(path: name).path)
        }
        return owned || manager.fileExists(atPath: embeddedHelperURL.path)
    }

    public func removeManagedComponents() throws {
        let manager = FileManager.default
        var failure: Error?
        for name in ["yt-dlp", "_internal", "ffmpeg", "ffprobe"] {
            let url = binDirectory.appending(path: name)
            guard manager.fileExists(atPath: url.path) else { continue }
            do {
                try manager.removeItem(at: url)
            } catch {
                if failure == nil { failure = error }
            }
        }
        if manager.fileExists(atPath: embeddedHelperURL.path) {
            do {
                try manager.removeItem(at: embeddedHelperURL)
            } catch {
                if failure == nil { failure = error }
            }
        }
        if let failure {
            throw EngineFailure(message: String(format: String(localized: "Couldn't remove the components. %@"), failure.localizedDescription))
        }
    }

    private var embeddedHelperURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/YtDlp.app")
    }

    public func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
    }

    public func status() -> EngineStatus {
        EngineStatus(
            ytdlp: resolve(tool: "yt-dlp"),
            ffmpeg: resolve(tool: "ffmpeg"),
            ffprobe: resolve(tool: "ffprobe")
        )
    }

    public func probe(url: URL) async throws -> VideoDetails {
        guard let binary = status().ytdlp else {
            throw EngineFailure(message: String(localized: "Install yt-dlp first."))
        }
        let arguments = [
            "--dump-single-json",
            "--no-playlist",
            "--no-warnings",
            "--ignore-config",
            "--skip-download",
            "--socket-timeout", "20",
            "--retries", "2",
            url.absoluteString
        ]
        let environment = environment()
        let result = try await withThrowingTaskGroup(of: (String, String, Int32).self) { group in
            group.addTask {
                try await CommandRunner.collect(
                    executable: binary,
                    arguments: arguments,
                    environment: environment
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(40))
                throw EngineFailure(message: String(localized: "No response from the site. If LuLu is on, it blocks the downloader and often shows no prompt. Allow this file in LuLu's rules."))
            }
            do {
                guard let value = try await group.next() else {
                    throw EngineFailure(message: String(localized: "No response from the site. If LuLu is on, it blocks the downloader and often shows no prompt. Allow this file in LuLu's rules."))
                }
                group.cancelAll()
                while !group.isEmpty {
                    _ = try? await group.next()
                }
                return value
            } catch {
                group.cancelAll()
                while !group.isEmpty {
                    _ = try? await group.next()
                }
                throw error
            }
        }
        let (stdout, stderr, code) = result
        guard code == 0 else {
            let log = stderr.split(separator: "\n").map(String.init) + stdout.split(separator: "\n").map(String.init)
            throw EngineFailure(message: humanize(log: log))
        }
        guard let data = extractJSONObject(stdout) else {
            throw EngineFailure(message: String(localized: "Couldn't read the video details."))
        }
        do {
            return try VideoDetails(json: data)
        } catch let failure as EngineFailure {
            throw failure
        } catch {
            throw EngineFailure(message: String(localized: "Couldn't read the video details."))
        }
    }

    public func download(
        url: URL,
        quality: Quality,
        destination: URL,
        hasFFmpeg: Bool
    ) -> AsyncThrowingStream<DownloadEvent, Error> {
        let binary = status().ytdlp
        let template = destination.appending(path: FormatSelection.outputName(for: quality)).path
        var arguments = [
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-mtime",
            "--socket-timeout", "30",
            "--retries", "3",
            "--fragment-retries", "3",
            "-o", template,
            "--print", "after_move:filepath"
        ]
        arguments += FormatSelection.arguments(for: quality, hasFFmpeg: hasFFmpeg)
        if let ffmpeg = status().ffmpeg {
            arguments += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }
        arguments.append(url.absoluteString)

        return AsyncThrowingStream { continuation in
            guard let binary else {
                continuation.finish(throwing: EngineFailure(message: String(localized: "Install yt-dlp first.")))
                return
            }
            let lines = LineProcess().stream(
                executable: binary,
                arguments: arguments,
                environment: self.environment(),
                directory: destination
            )
            let task = Task {
                var log: [String] = []
                do {
                    for try await line in lines {
                        log.append(line)
                        if log.count > 80 { log.removeFirst(log.count - 80) }
                        if line.contains("[Merger]") || line.contains("Merging formats") || line.contains("[VideoRemuxer]") {
                            continuation.yield(.phase(.merging))
                        } else if line.contains("[ExtractAudio]") {
                            continuation.yield(.phase(.extracting))
                        }
                        switch interpret(line) {
                        case .progress(let fraction, let speed, let eta):
                            continuation.yield(.progress(fraction: fraction, speed: speed, eta: eta))
                        case .output(let path), .alreadyExists(let path):
                            continuation.yield(.file(path))
                        case .merging:
                            continuation.yield(.phase(.merging))
                        case .extracting:
                            continuation.yield(.phase(.extracting))
                        case nil:
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: EngineFailure(message: humanize(log: log)))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func cacheThumbnail(from remote: URL?, id: String) async -> URL? {
        guard let remote else { return nil }
        try? prepare()
        let safeID = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let dest = thumbnailDirectory.appending(path: "\(safeID.isEmpty ? UUID().uuidString : safeID).jpg")
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        do {
            var request = URLRequest(url: remote)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 32 else {
                return nil
            }
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    public func install() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    try self.prepare()
                    if self.status().ytdlp == nil {
                        continuation.yield(String(localized: "Downloading yt-dlp…"))
                        try await self.downloadTool(
                            from: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!,
                            named: "yt-dlp"
                        )
                        continuation.yield(String(localized: "yt-dlp is installed"))
                    } else {
                        continuation.yield(String(localized: "yt-dlp is already here"))
                    }

                    if self.status().ffmpeg == nil {
                        continuation.yield(String(localized: "Downloading ffmpeg…"))
                        do {
                            try await self.downloadTool(
                                from: URL(string: "https://evermeet.cx/ffmpeg/getrelease/zip")!,
                                named: "ffmpeg"
                            )
                            continuation.yield(String(localized: "ffmpeg is installed"))
                        } catch {
                            try await self.installFFmpegWithBrew(continuation)
                        }
                    }

                    if self.status().ffprobe == nil,
                       self.status().ffmpeg?.deletingLastPathComponent().path == self.binDirectory.path {
                        continuation.yield(String(localized: "Downloading ffprobe…"))
                        do {
                            try await self.downloadTool(
                                from: URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip")!,
                                named: "ffprobe"
                            )
                        } catch {
                            continuation.yield(String(localized: "ffprobe didn't install — downloads still work"))
                        }
                    }

                    continuation.yield(String(localized: "Done"))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    continuation.finish(throwing: EngineFailure(message: message))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func installFFmpegWithBrew(_ continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        guard let brew = brewExecutable() else {
            throw EngineFailure(message: String(localized: "Couldn't download ffmpeg. Install it with brew install ffmpeg and open Lumen again."))
        }
        continuation.yield(String(localized: "Trying Homebrew — this can take a few minutes…"))
        let lines = LineProcess().stream(
            executable: brew,
            arguments: ["install", "ffmpeg"],
            environment: environment(extra: ["HOMEBREW_NO_AUTO_UPDATE": "1", "NONINTERACTIVE": "1"]),
            directory: nil
        )
        var log: [String] = []
        do {
            for try await line in lines {
                log.append(line)
                continuation.yield(line)
            }
        } catch {
            throw EngineFailure(message: String(format: String(localized: "Homebrew couldn't install ffmpeg. %@"), log.last ?? ""))
        }
    }

    private func downloadTool(from url: URL, named name: String) async throws {
        let session = makeSession()
        let (file, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EngineFailure(message: String(format: String(localized: "Couldn't download %@."), name))
        }
        let tempRoot = FileManager.default.temporaryDirectory.appending(path: "lumen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let payload = tempRoot.appending(path: "payload")
        try FileManager.default.moveItem(at: file, to: payload)
        if name == "yt-dlp" {
            try installYtDlpBundle(payload: payload, in: tempRoot)
            return
        }
        let binary = try unpackedBinary(payload: payload, named: name, in: tempRoot)
        let destination = binDirectory.appending(path: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: binary, to: destination)
        try bless(destination)
    }

    private func installYtDlpBundle(payload: URL, in root: URL) throws {
        let extracted = root.appending(path: "out")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-xk", payload.path, extracted.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0, let binary = findBinary(in: extracted, named: "yt-dlp") else {
            throw EngineFailure(message: String(localized: "Couldn't unpack yt-dlp."))
        }
        let runtime = binary.deletingLastPathComponent().appending(path: "_internal")
        guard FileManager.default.fileExists(atPath: runtime.path) else {
            throw EngineFailure(message: String(localized: "The yt-dlp archive is missing its support files."))
        }

        let destination = binDirectory.appending(path: "yt-dlp")
        let destinationRuntime = binDirectory.appending(path: "_internal")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        if FileManager.default.fileExists(atPath: destinationRuntime.path) {
            try FileManager.default.removeItem(at: destinationRuntime)
        }
        try FileManager.default.copyItem(at: binary, to: destination)
        try FileManager.default.copyItem(at: runtime, to: destinationRuntime)
        try bless(destination)
        clearQuarantine(binDirectory)
        embedHelper(binary: destination, runtime: destinationRuntime)
    }

    private func embedHelper(binary: URL, runtime: URL) {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return }
        let helper = app.appending(path: "Contents/Helpers/YtDlp.app")
        let macOS = helper.appending(path: "Contents/MacOS")
        let resources = helper.appending(path: "Contents/Resources")
        let destination = macOS.appending(path: "yt-dlp")
        let destinationRuntime = macOS.appending(path: "_internal")
        do {
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let info = helper.appending(path: "Contents/Info.plist")
            try? FileManager.default.removeItem(at: info)
            if let bundledInfo = Bundle.main.url(forResource: "HelperInfo", withExtension: "plist") {
                try FileManager.default.copyItem(at: bundledInfo, to: info)
            } else {
                try Data(helperInfoPlist.utf8).write(to: info)
            }
            if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                let iconDestination = resources.appending(path: "AppIcon.icns")
                try? FileManager.default.removeItem(at: iconDestination)
                try? FileManager.default.copyItem(at: icon, to: iconDestination)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            if FileManager.default.fileExists(atPath: destinationRuntime.path) {
                try FileManager.default.removeItem(at: destinationRuntime)
            }
            let signed = FileManager.default.temporaryDirectory.appending(path: "lumen-ytdlp-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: binary, to: signed)
            try bless(signed, identifier: "app.lumen.downloader.ytdlp")
            try FileManager.default.copyItem(at: signed, to: destination)
            try? FileManager.default.removeItem(at: signed)
            try FileManager.default.copyItem(at: runtime, to: destinationRuntime)
            let link = Process()
            link.currentDirectoryURL = helper.appending(path: "Contents")
            link.executableURL = URL(fileURLWithPath: "/bin/ln")
            link.arguments = ["-sfn", "MacOS/_internal", "Frameworks"]
            try link.run()
            link.waitUntilExit()
            clearQuarantine(helper)
            YtDlpRegistration.register(helper, force: true)
        } catch {
            return
        }
    }

    private func unpackedBinary(payload: URL, named name: String, in root: URL) throws -> URL {
        let header = try Data(contentsOf: payload, options: [.mappedIfSafe]).prefix(2)
        if header == Data([0x50, 0x4B]) {
            let extracted = root.appending(path: "out")
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", payload.path, extracted.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0, let found = findBinary(in: extracted, named: name) else {
                throw EngineFailure(message: String(format: String(localized: "The %@ archive didn't contain the program."), name))
            }
            return found
        }
        return payload
    }

    private func findBinary(in root: URL, named name: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let file as URL in enumerator {
            if file.path.contains("__MACOSX") { continue }
            let fileName = file.lastPathComponent
            let matches = fileName == name || fileName == "\(name)_macos" || fileName.hasPrefix("\(name)-")
            guard matches else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            return file
        }
        return nil
    }

    private func bless(_ url: URL, identifier: String? = nil) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        clearQuarantine(url)
        var arguments = ["--force", "--sign", "-"]
        if let identifier {
            arguments += ["--identifier", identifier]
        }
        arguments.append(url.path)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = arguments
        try? sign.run()
        sign.waitUntilExit()
    }

    private func clearQuarantine(_ url: URL) {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? xattr.run()
        xattr.waitUntilExit()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }

    func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let prefixes = [binDirectory.path, "/opt/homebrew/bin", "/usr/local/bin"]
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (prefixes + [current]).joined(separator: ":")
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    private func resolve(tool: String) -> URL? {
        var candidates = [
            binDirectory.appending(path: tool),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(tool)"),
            URL(fileURLWithPath: "/usr/local/bin/\(tool)"),
            URL(fileURLWithPath: "/usr/bin/\(tool)")
        ]
        if tool == "yt-dlp", let embedded = embeddedYtDlp() {
            candidates.insert(embedded, at: 0)
        }
        return candidates.first { url in
            guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
            if tool == "yt-dlp" {
                return bundledYtDlpIsComplete(url)
            }
            return true
        }
    }

    private func embeddedYtDlp() -> URL? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return nil }
        let helper = app.appending(path: "Contents/Helpers/YtDlp.app")
        let url = helper.appending(path: "Contents/MacOS/yt-dlp")
        let runtime = url.deletingLastPathComponent().appending(path: "_internal/Python")
        let frameworks = helper.appending(path: "Contents/Frameworks/Python")
        guard FileManager.default.isExecutableFile(atPath: url.path),
              FileManager.default.fileExists(atPath: runtime.path),
              FileManager.default.fileExists(atPath: frameworks.path) else {
            return nil
        }
        YtDlpRegistration.register(helper)
        return url
    }

    private func bundledYtDlpIsComplete(_ url: URL) -> Bool {
        guard url.deletingLastPathComponent().path == binDirectory.path else { return true }
        return FileManager.default.fileExists(atPath: binDirectory.appending(path: "_internal/Python").path)
    }

    private func brewExecutable() -> URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

extension VideoDetails {
    init(json: Data) throws {
        let raw = try JSONDecoder().decode(RawVideo.self, from: json)
        guard let id = raw.id, !id.isEmpty else {
            throw EngineFailure(message: String(localized: "Couldn't read the video details."))
        }
        let title = [raw.title, raw.fulltitle].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.first ?? String(localized: "Untitled")
        let channel = [raw.channel, raw.uploader].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.first
        let thumbnail = raw.thumbnail.flatMap(URL.init(string:))
        self.init(
            id: id,
            title: title,
            channel: channel,
            thumbnail: thumbnail,
            duration: raw.duration,
            viewCount: raw.viewCount,
            formats: raw.formats ?? []
        )
    }
}

private struct RawVideo: Decodable {
    var id: String?
    var title: String?
    var fulltitle: String?
    var thumbnail: String?
    var channel: String?
    var uploader: String?
    var duration: Double?
    var viewCount: Int?
    var formats: [StreamFormat]?

    enum CodingKeys: String, CodingKey {
        case id, title, fulltitle, thumbnail, channel, uploader, duration, formats
        case viewCount = "view_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.string(container, .id)
        title = Self.string(container, .title)
        fulltitle = Self.string(container, .fulltitle)
        thumbnail = Self.string(container, .thumbnail)
        channel = Self.string(container, .channel)
        uploader = Self.string(container, .uploader)
        if let value = Self.double(container, .duration) {
            duration = value
        } else if let value = Self.int(container, .duration) {
            duration = Double(value)
        }
        if let value = Self.int(container, .viewCount) {
            viewCount = value
        } else if let value = Self.double(container, .viewCount) {
            viewCount = Int(value)
        }
        formats = try? container.decodeIfPresent([RawFormat].self, forKey: .formats)?.map(\.format)
    }

    private static func string(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        try? container.decodeIfPresent(String.self, forKey: key)
    }

    private static func int(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        return nil
    }

    private static func double(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        return nil
    }
}

private struct RawFormat: Decodable {
    var format: StreamFormat

    enum CodingKeys: String, CodingKey {
        case height, vcodec, acodec, ext, filesize, tbr
        case filesizeApprox = "filesize_approx"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = StreamFormat(
            height: Self.int(container, .height),
            vcodec: try? container.decodeIfPresent(String.self, forKey: .vcodec) ?? nil,
            acodec: try? container.decodeIfPresent(String.self, forKey: .acodec) ?? nil,
            ext: try? container.decodeIfPresent(String.self, forKey: .ext) ?? nil,
            size: Self.int64(container, .filesize) ?? Self.int64(container, .filesizeApprox),
            tbr: Self.double(container, .tbr)
        )
    }

    private static func int(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        return nil
    }

    private static func int64(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        return nil
    }

    private static func double(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        return nil
    }
}

func extractJSONObject(_ text: String) -> Data? {
    guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
        return nil
    }
    return Data(text[start...end].utf8)
}
