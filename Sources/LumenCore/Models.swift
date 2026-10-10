import Foundation

public enum Quality: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case best
    case p2160
    case p1440
    case p1080
    case p720
    case p480
    case audio

    public var id: String { rawValue }

    public var ceiling: Int? {
        switch self {
        case .best, .audio: nil
        case .p2160: 2160
        case .p1440: 1440
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        }
    }
}

public struct StreamFormat: Equatable, Sendable {
    public var height: Int?
    public var vcodec: String?
    public var acodec: String?
    public var ext: String?
    public var size: Int64?
    public var tbr: Double?

    public init(height: Int?, vcodec: String?, acodec: String?, ext: String?, size: Int64?, tbr: Double?) {
        self.height = height
        self.vcodec = vcodec
        self.acodec = acodec
        self.ext = ext
        self.size = size
        self.tbr = tbr
    }

    public var isVideo: Bool {
        guard let vcodec, vcodec != "none", (height ?? 0) > 0 else { return false }
        return true
    }

    public var isAudio: Bool {
        guard let acodec, acodec != "none" else { return false }
        if let vcodec, vcodec != "none" { return false }
        return true
    }
}

public struct VideoDetails: Equatable, Sendable {
    public var id: String
    public var title: String
    public var channel: String?
    public var thumbnail: URL?
    public var duration: Double?
    public var viewCount: Int?
    public var formats: [StreamFormat]

    public init(
        id: String,
        title: String,
        channel: String?,
        thumbnail: URL?,
        duration: Double?,
        viewCount: Int?,
        formats: [StreamFormat]
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.thumbnail = thumbnail
        self.duration = duration
        self.viewCount = viewCount
        self.formats = formats
    }

    public var maxVideoHeight: Int {
        formats.compactMap { $0.isVideo ? $0.height : nil }.max() ?? 0
    }

    public func qualities(hasFFmpeg: Bool) -> [Quality] {
        var list: [Quality] = [.best]
        if hasFFmpeg {
            let maxHeight = maxVideoHeight
            if maxHeight == 0 {
                list.append(contentsOf: [.p1080, .p720])
            } else {
                for tier in [Quality.p2160, .p1440, .p1080, .p720, .p480] {
                    guard let ceiling = tier.ceiling else { continue }
                    if maxHeight >= ceiling - 20 {
                        list.append(tier)
                    }
                }
            }
        }
        list.append(.audio)
        return list
    }

    public func estimate(for quality: Quality) -> Int64? {
        switch quality {
        case .audio:
            return bestAudio()?.size
        default:
            guard let video = bestVideo(ceiling: quality.ceiling), let videoSize = video.size else {
                return nil
            }
            return videoSize + (bestAudio()?.size ?? 0)
        }
    }

    private func bestAudio() -> StreamFormat? {
        formats
            .filter(\.isAudio)
            .max { lhs, rhs in (lhs.tbr ?? 0, lhs.size ?? 0) < (rhs.tbr ?? 0, rhs.size ?? 0) }
    }

    private func bestVideo(ceiling: Int?) -> StreamFormat? {
        let videos = formats.filter { format in
            guard format.isVideo else { return false }
            if let ceiling, (format.height ?? 0) > ceiling { return false }
            return true
        }
        return videos.max { lhs, rhs in
            let left = (lhs.height ?? 0, lhs.size ?? 0, lhs.tbr ?? 0)
            let right = (rhs.height ?? 0, rhs.size ?? 0, rhs.tbr ?? 0)
            return left < right
        }
    }
}

public struct EngineStatus: Equatable, Sendable {
    public var ytdlp: URL?
    public var ffmpeg: URL?
    public var ffprobe: URL?

    public var isReady: Bool { ytdlp != nil }

    public init(ytdlp: URL?, ffmpeg: URL?, ffprobe: URL?) {
        self.ytdlp = ytdlp
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }
}

public struct EngineFailure: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum DownloadEvent: Sendable, Equatable {
    case progress(fraction: Double, speed: String?, eta: String?)
    case phase(Phase)
    case file(String)

    public enum Phase: String, Sendable, Equatable {
        case merging
        case extracting
    }
}

enum FormatSelection {
    static func outputName(for quality: Quality) -> String {
        if quality == .audio {
            return "%(title).160B [%(id)s] audio.%(ext)s"
        }
        return "%(title).160B [%(id)s] %(height)sp.%(ext)s"
    }

    static func arguments(for quality: Quality, hasFFmpeg: Bool) -> [String] {
        if !hasFFmpeg {
            if quality == .audio {
                return ["-f", "ba[ext=m4a]/ba[acodec^=mp4a]/ba"]
            }
            return ["-f", "b[ext=mp4]/b"]
        }

        var args = ["-f", selector(for: quality)]
        if let sort = sort(for: quality) {
            args += ["-S", sort]
        }
        if quality != .audio {
            args += ["--merge-output-format", "mp4"]
        }
        return args
    }

    private static func selector(for quality: Quality) -> String {
        switch quality {
        case .audio:
            return "ba[acodec^=mp4a][ext=m4a]/ba[ext=m4a]/ba"
        case .best:
            return "bv*+ba[acodec^=mp4a]/bv*+ba/b"
        default:
            let height = quality.ceiling ?? 1080
            let floor = max(height - 40, 1)
            let tier = "bv*[height<=\(height)][height>=\(floor)]"
            return [
                "\(tier)[vcodec^=avc1]+ba[acodec^=mp4a]",
                "\(tier)[vcodec^=avc1]+ba",
                "\(tier)[vcodec^=av01]+ba[acodec^=mp4a]",
                "\(tier)[vcodec^=av01]+ba",
                "\(tier)[vcodec^=vp09]+ba[acodec^=mp4a]",
                "\(tier)[vcodec^=vp9]+ba[acodec^=mp4a]",
                "\(tier)+ba",
                "bv*[height<=\(height)]+ba",
                "b[height<=\(height)]",
                "b"
            ].joined(separator: "/")
        }
    }

    /// YouTube stores 1440p and 4K as AV1 or VP9. H.264 usually stops at 1080p,
    /// so a global H.264 preference would ignore the higher resolution.
    private static func sort(for quality: Quality) -> String? {
        guard quality == .best else { return nil }
        return "res,vcodec:av1:h264:hevc:vp9,acodec:aac"
    }
}
