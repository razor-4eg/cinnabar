import Foundation

public enum MediaLink {
    public static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = extract(from: trimmed)
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              host.contains(".") else {
            return nil
        }

        if isYouTube(host) {
            return youtubeVideo(components, host: host)
        }

        let path = components.path
        let query = components.query ?? ""
        guard path.count > 1 || !query.isEmpty else { return nil }
        return components.url
    }

    private static func isYouTube(_ host: String) -> Bool {
        host == "youtu.be"
            || host.hasSuffix(".youtu.be")
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host.hasSuffix(".youtube-nocookie.com")
    }

    /// A YouTube playlist or channel page is not one video. Other sites are left to yt-dlp,
    /// which is always called with `--no-playlist`.
    private static func youtubeVideo(_ components: URLComponents, host: String) -> URL? {
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty, id != "playlist" else { return nil }
            return components.url
        }

        let path = components.path
        let query = components.query ?? ""
        let hasVideo = (path.contains("/watch") && query.contains("v="))
            || path.contains("/shorts/")
            || path.contains("/live/")
            || path.contains("/embed/")
            || path.contains("/v/")
        guard hasVideo else { return nil }
        return components.url
    }

    private static func extract(from raw: String) -> String {
        let pattern = /https?:\/\/\S+/
        let slice: String
        if let match = raw.firstMatch(of: pattern) {
            slice = String(match.output)
        } else if !raw.contains(where: \.isWhitespace), raw.contains(".") {
            slice = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://\(raw)"
        } else {
            slice = raw
        }
        return slice.trimmingCharacters(in: CharacterSet(charactersIn: ".,);»\"'"))
    }
}
