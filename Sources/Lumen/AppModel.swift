import AppKit
import Foundation
import LumenCore
import Observation
import UserNotifications

enum AppSection: String, CaseIterable, Identifiable {
    case compose
    case library

    var id: String { rawValue }
}

struct PreviewModel: Equatable {
    var source: URL
    var id: String
    var title: String
    var channel: String?
    var views: String?
    var durationText: String?
    var thumbnail: URL?
    var qualities: [Quality]
    var estimates: [Quality: Int64]
}

enum JobState: Equatable {
    case queued
    case running
    case finishing
    case completed
    case failed(String)
    case cancelled
}

struct DownloadJob: Identifiable {
    let id: UUID
    let source: URL
    let videoID: String
    var title: String
    var channel: String?
    var thumbnail: URL?
    var quality: Quality
    var folder: String
    var fraction: Double
    var detail: String
    var state: JobState
    var filePath: String?
    var pass: Int
    var bytes: Int64?
}

struct LibraryItem: Identifiable, Codable, Equatable {
    var id: UUID
    var videoID: String
    var title: String
    var channel: String?
    var thumbnailPath: String?
    var filePath: String
    var quality: String
    var bytes: Int64?
    var createdAt: Date

    var thumbnailURL: URL? {
        guard let thumbnailPath else { return nil }
        return URL(fileURLWithPath: thumbnailPath)
    }

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    var qualityTitle: String {
        Quality(rawValue: quality)?.title ?? quality
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    var section: AppSection = .compose
    var urlText = ""
    var preview: PreviewModel?
    var selectedQuality: Quality = .p1080
    var isResolving = false
    var errorBanner: String?
    var jobs: [DownloadJob] = []
    var library: [LibraryItem] = []
    var destination: URL
    var engineStatus: EngineStatus
    var isInstalling = false
    var installMessage = ""
    var installError: String?
    var pasteHint = false

    @ObservationIgnored private let engine: Engine
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var resolveToken = UUID()
    @ObservationIgnored private var workers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var askedNotifications = false

    init() {
        let engine = Engine()
        try? engine.prepare()
        let folder: URL
        if let stored = UserDefaults.standard.string(forKey: "lumen.destination"), !stored.isEmpty {
            folder = URL(fileURLWithPath: stored)
        } else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads")
            folder = downloads.appending(path: "Lumen")
        }
        self.engine = engine
        destination = folder
        engineStatus = engine.status()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        loadLibrary()
    }

    var activeCount: Int {
        jobs.filter { $0.state == .running || $0.state == .finishing || $0.state == .queued }.count
    }

    var hasManagedComponents: Bool { engine.hasManagedComponents }

    func refreshEngine() {
        engineStatus = engine.status()
    }

    func refreshPasteHint() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        pasteHint = MediaLink.parse(text) != nil && urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func urlDidChange() {
        errorBanner = nil
        debounce?.cancel()
        refreshPasteHint()
        guard MediaLink.parse(urlText) != nil else {
            preview = nil
            return
        }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            await performResolve()
        }
    }

    func pasteAndResolve() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pasteHint = false
        Task { await resolve() }
    }

    func acceptDrop(_ raw: String) {
        guard MediaLink.parse(raw) != nil else {
            errorBanner = String(localized: "This isn't a link to a video.")
            return
        }
        urlText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await resolve() }
    }

    func resolve() async {
        debounce?.cancel()
        debounce = nil
        await performResolve()
    }

    private func performResolve() async {
        guard engineStatus.ytdlp != nil else {
            errorBanner = String(localized: "Install the download tools first.")
            return
        }
        guard let url = MediaLink.parse(urlText) else {
            errorBanner = String(localized: "Paste a link to a specific video.")
            preview = nil
            return
        }
        if preview?.source == url, preview != nil {
            return
        }

        let token = UUID()
        resolveToken = token
        isResolving = true
        errorBanner = nil
        defer {
            if resolveToken == token {
                isResolving = false
            }
        }

        do {
            let details = try await engine.probe(url: url)
            let thumb = await engine.cacheThumbnail(from: details.thumbnail, id: details.id)
            guard resolveToken == token else { return }
            let hasFFmpeg = engineStatus.ffmpeg != nil
            let qualities = details.qualities(hasFFmpeg: hasFFmpeg)
            var estimates: [Quality: Int64] = [:]
            for quality in qualities {
                if let estimate = details.estimate(for: quality) {
                    estimates[quality] = estimate
                }
            }
            preview = PreviewModel(
                source: url,
                id: details.id,
                title: details.title,
                channel: details.channel,
                views: details.viewCount.map(Formatters.views),
                durationText: details.duration.map(Formatters.duration),
                thumbnail: thumb ?? details.thumbnail,
                qualities: qualities,
                estimates: estimates
            )
            if qualities.contains(.p1080) {
                selectedQuality = .p1080
            } else if let first = qualities.first {
                selectedQuality = first
            }
        } catch is CancellationError {
            return
        } catch {
            guard resolveToken == token, !Task.isCancelled else { return }
            preview = nil
            errorBanner = (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn't open the video.")
        }
    }

    func download() {
        guard let preview else { return }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let job = DownloadJob(
            id: UUID(),
            source: preview.source,
            videoID: preview.id,
            title: preview.title,
            channel: preview.channel,
            thumbnail: preview.thumbnail,
            quality: selectedQuality,
            folder: destination.path,
            fraction: 0,
            detail: String(localized: "In queue"),
            state: .queued,
            filePath: nil,
            pass: 0,
            bytes: nil
        )
        jobs.insert(job, at: 0)
        pump()
    }

    func cancel(_ id: UUID) {
        workers[id]?.cancel()
        mutate(id) {
            $0.state = .cancelled
            $0.detail = String(localized: "Cancelled")
        }
        updateActivity()
    }

    func retry(_ id: UUID) {
        mutate(id) {
            $0.state = .queued
            $0.fraction = 0
            $0.detail = String(localized: "In queue")
            $0.filePath = nil
            $0.pass = 0
            $0.bytes = nil
        }
        pump()
    }

    func dismiss(_ id: UUID) {
        workers[id]?.cancel()
        jobs.removeAll { $0.id == id }
        updateActivity()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Where to save videos")
        panel.directoryURL = destination
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setDestination(url)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openDestination() {
        NSWorkspace.shared.open(destination)
    }

    func revealEngine() {
        guard let url = engineStatus.ytdlp else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func trash(_ item: LibraryItem) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete this video?")
        alert.informativeText = String(format: String(localized: "\"%@\" will be moved to the Trash."), item.title)
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if FileManager.default.fileExists(atPath: item.filePath) {
            try? FileManager.default.trashItem(at: item.fileURL, resultingItemURL: nil)
        }
        library.removeAll { $0.id == item.id }
        saveLibrary()
    }

    func forget(_ item: LibraryItem) {
        var hidden = UserDefaults.standard.stringArray(forKey: Self.hiddenLibraryKey) ?? []
        if !hidden.contains(item.filePath) {
            hidden.append(item.filePath)
        }
        UserDefaults.standard.set(hidden, forKey: Self.hiddenLibraryKey)
        library.removeAll { $0.id == item.id }
        saveLibrary()
    }

    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        installError = nil
        installMessage = String(localized: "Preparing…")
        Task {
            defer {
                refreshEngine()
                isInstalling = false
            }
            do {
                for try await line in engine.install() {
                    installMessage = line
                }
            } catch {
                installError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func updateComponents() {
        guard !isInstalling, activeCount == 0 else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Download the components again?")
        alert.informativeText = String(localized: "Lumen's copies of yt-dlp and ffmpeg will be replaced with fresh ones. ffmpeg installed with Homebrew stays.")
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isInstalling = true
        installError = nil
        installMessage = String(localized: "Preparing…")
        Task {
            defer {
                refreshEngine()
                isInstalling = false
            }
            do {
                try engine.removeManagedComponents()
                for try await line in engine.install() {
                    installMessage = line
                }
            } catch {
                installError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func removeComponents() {
        guard !isInstalling, activeCount == 0 else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove the components?")
        alert.informativeText = String(localized: "Lumen's copies of yt-dlp and ffmpeg will be deleted. ffmpeg installed with Homebrew stays.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Remove"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try engine.removeManagedComponents()
            installError = nil
            installMessage = String(localized: "Components removed.")
            refreshEngine()
        } catch {
            installError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setDestination(_ url: URL) {
        destination = url
        UserDefaults.standard.set(url.path, forKey: "lumen.destination")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func pump() {
        let active = jobs.filter { $0.state == .running || $0.state == .finishing }.count
        let queued = jobs.filter { $0.state == .queued }.map(\.id).reversed()
        var slots = max(0, 2 - active)
        for id in queued where slots > 0 {
            slots -= 1
            start(id)
        }
        updateActivity()
    }

    private func start(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.state == .queued else { return }
        mutate(id) {
            $0.state = .running
            $0.detail = String(localized: "Connecting…")
            $0.fraction = 0
        }
        let source = job.source
        let quality = job.quality
        let folder = URL(fileURLWithPath: job.folder)
        let hasFFmpeg = engineStatus.ffmpeg != nil
        let title = job.title

        workers[id] = Task {
            let stream = engine.download(
                url: source,
                quality: quality,
                destination: folder,
                hasFFmpeg: hasFFmpeg
            )
            do {
                for try await event in stream {
                    try Task.checkCancellation()
                    apply(event, to: id, folder: folder)
                }
                complete(id)
            } catch is CancellationError {
                markCancelled(id)
            } catch {
                if Task.isCancelled {
                    markCancelled(id)
                } else {
                    let message = (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn't download.")
                    mutate(id) {
                        $0.state = .failed(message)
                        $0.detail = message
                    }
                    notify(title: String(localized: "Couldn't download the video"), body: title)
                }
            }
            workers[id] = nil
            pump()
        }
    }

    private func apply(_ event: DownloadEvent, to id: UUID, folder: URL) {
        switch event {
        case .progress(let fraction, let speed, let eta):
            mutate(id) { job in
                if fraction + 0.05 < job.fraction {
                    job.pass += 1
                }
                job.fraction = fraction
                if job.state != .finishing {
                    job.state = .running
                }
                job.detail = progressDetail(speed: speed, eta: eta, pass: job.pass)
            }
        case .phase(.merging):
            mutate(id) {
                $0.state = .finishing
                $0.fraction = max($0.fraction, 1)
                $0.detail = String(localized: "Merging video and audio…")
            }
        case .phase(.extracting):
            mutate(id) {
                $0.state = .finishing
                $0.detail = String(localized: "Preparing audio…")
            }
        case .file(let path):
            let full = path.hasPrefix("/") ? path : folder.appending(path: path).path
            mutate(id) { $0.filePath = full }
        }
    }

    private func markCancelled(_ id: UUID) {
        mutate(id) {
            guard $0.state == .running || $0.state == .finishing || $0.state == .queued else { return }
            $0.state = .cancelled
            $0.detail = String(localized: "Cancelled")
        }
    }

    private func complete(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard job.state == .running || job.state == .finishing else { return }
        guard let path = finishedFile(for: job) else {
            let message = String(localized: "The file didn't appear after the download.")
            mutate(id) {
                $0.state = .failed(message)
                $0.detail = message
            }
            return
        }
        mutate(id) { $0.filePath = path }
        let bytes = fileSize(path)
        let sizeText = bytes.map { String(format: String(localized: "Done · %@"), Formatters.bytes($0)) } ?? String(localized: "Done")
        mutate(id) {
            $0.state = .completed
            $0.fraction = 1
            $0.bytes = bytes
            $0.detail = sizeText
        }
        let quality = qualityOnDisk(path) ?? job.quality.rawValue
        if let index = library.firstIndex(where: { $0.filePath == path }) {
            library[index].quality = quality
            library[index].bytes = bytes
            library[index].createdAt = Date()
            library[index].title = job.title
        } else {
            library.insert(LibraryItem(
                id: UUID(),
                videoID: job.videoID,
                title: job.title,
                channel: job.channel,
                thumbnailPath: job.thumbnail?.isFileURL == true ? job.thumbnail?.path : nil,
                filePath: path,
                quality: quality,
                bytes: bytes,
                createdAt: Date()
            ), at: 0)
        }
        var hidden = UserDefaults.standard.stringArray(forKey: Self.hiddenLibraryKey) ?? []
        hidden.removeAll { $0 == path }
        UserDefaults.standard.set(hidden, forKey: Self.hiddenLibraryKey)
        saveLibrary()
        notify(title: String(localized: "Video saved"), body: job.title)
        updateActivity()
    }

    private func progressDetail(speed: String?, eta: String?, pass: Int) -> String {
        var parts: [String] = []
        if pass > 0 { parts.append(String(localized: "Audio")) }
        if let speed, !speed.isEmpty { parts.append(Formatters.speed(speed)) }
        if let eta, !eta.isEmpty { parts.append(String(format: String(localized: "%@ left"), eta)) }
        if parts.isEmpty {
            return pass > 0 ? String(localized: "Downloading audio…") : String(localized: "Downloading…")
        }
        return parts.joined(separator: " · ")
    }

    private func mutate(_ id: UUID, _ body: (inout DownloadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        var job = jobs[index]
        body(&job)
        jobs[index] = job
    }

    private func updateActivity() {
        let busy = jobs.contains { $0.state == .running || $0.state == .queued || $0.state == .finishing }
        if busy, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                reason: String(localized: "Downloading video")
            )
        } else if !busy, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func finishedFile(for job: DownloadJob) -> String? {
        if let path = job.filePath, FileManager.default.fileExists(atPath: path), isPlayableFile(path) {
            return path
        }
        let folder = URL(fileURLWithPath: job.folder)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let mark = "[\(job.videoID)]"
        let token = fileToken(for: job.quality)
        let matches = files.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile != false else { return false }
            let name = url.lastPathComponent
            guard name.contains(mark), isPlayableFile(url.path) else { return false }
            if let token {
                return name.contains(" \(token).")
            }
            return true
        }
        return matches.max { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }?.path
    }

    private func fileToken(for quality: Quality) -> String? {
        switch quality {
        case .audio: "audio"
        case .p2160: "2160p"
        case .p1440: "1440p"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .best: nil
        }
    }

    private func qualityOnDisk(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.contains(" audio.") { return Quality.audio.rawValue }
        guard let match = name.firstMatch(of: /\s(\d+)p\./), let height = Int(match.1) else { return nil }
        let quality: Quality? = switch height {
        case 2000...: .p2160
        case 1400..<2000: .p1440
        case 1000..<1400: .p1080
        case 700..<1000: .p720
        case 400..<700: .p480
        default: nil
        }
        return quality?.rawValue
    }

    private func quality(fromToken token: String?) -> Quality? {
        switch token {
        case "audio": .audio
        case "2160p": .p2160
        case "1440p": .p1440
        case "1080p": .p1080
        case "720p": .p720
        case "480p": .p480
        default: nil
        }
    }

    private func isPlayableFile(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard ["mp4", "mkv", "webm", "mov", "m4a", "mp3", "opus"].contains(ext) else { return false }
        if name.contains(".part") || name.contains(".temp.") { return false }
        if name.range(of: #"\.f\d+\."#, options: .regularExpression) != nil { return false }
        return true
    }

    private func fileSize(_ path: String) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let number = attributes?[.size] as? NSNumber
        return number?.int64Value
    }

    private static let hiddenLibraryKey = "lumen.hiddenLibrary"

    private func loadLibrary() {
        if let data = try? Data(contentsOf: engine.libraryFile) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let items = try? decoder.decode([LibraryItem].self, from: data) {
                library = items.sorted { $0.createdAt > $1.createdAt }
            }
        }
        adoptFilesOnDisk()
    }

    private func adoptFilesOnDisk() {
        let hidden = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenLibraryKey) ?? [])
        let knownPaths = Set(library.map(\.filePath))
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var adopted: [LibraryItem] = []
        for url in files {
            guard isPlayableFile(url.path) else { continue }
            guard let match = url.lastPathComponent.firstMatch(of: /^(.*) \[([A-Za-z0-9_-]+)\](?: (\d+p|audio))?\.[^.]+$/) else { continue }
            let videoID = String(match.2)
            guard !knownPaths.contains(url.path), !hidden.contains(url.path), !hidden.contains(videoID) else { continue }
            let title = String(match.1).trimmingCharacters(in: .whitespaces)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let token = match.3.map(String.init)
            adopted.append(LibraryItem(
                id: UUID(),
                videoID: videoID,
                title: title.isEmpty ? videoID : title,
                channel: nil,
                thumbnailPath: nil,
                filePath: url.path,
                quality: quality(fromToken: token)?.rawValue ?? Quality.best.rawValue,
                bytes: values?.fileSize.map(Int64.init),
                createdAt: values?.contentModificationDate ?? Date()
            ))
        }
        guard !adopted.isEmpty else { return }
        library.append(contentsOf: adopted)
        library.sort { $0.createdAt > $1.createdAt }
        saveLibrary()
    }

    private func saveLibrary() {
        try? engine.prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(library) else { return }
        try? data.write(to: engine.libraryFile, options: .atomic)
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        if !askedNotifications {
            askedNotifications = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                Self.post(title: title, body: body)
            }
            return
        }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Self.post(title: title, body: body)
        }
    }

    private nonisolated static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
