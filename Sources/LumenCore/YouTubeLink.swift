import Foundation

public enum YouTubeLink {
    public static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = extract(from: trimmed)
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased() else {
            return nil
        }

        let hostOK = host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host.hasSuffix(".youtube-nocookie.com")
        guard hostOK else { return nil }

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
        guard hasVideo, let url = components.url else { return nil }
        return url
    }

    private static func extract(from raw: String) -> String {
        let pattern = /https?:\/\/\S+/
        let slice: String
        if let match = raw.firstMatch(of: pattern) {
            slice = String(match.output)
        } else if raw.contains("youtube.com") || raw.contains("youtu.be") {
            slice = raw.hasPrefix("http") ? raw : "https://\(raw)"
        } else {
            slice = raw
        }
        return slice.trimmingCharacters(in: CharacterSet(charactersIn: ".,);»\"'"))
    }
}
