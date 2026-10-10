import Foundation

public enum EngineSignal: Equatable, Sendable {
    case progress(fraction: Double, speed: String?, eta: String?)
    case output(String)
    case merging
    case extracting
    case alreadyExists(String)
}

public func interpret(_ line: String) -> EngineSignal? {
    let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if let match = text.firstMatch(of: /\[download\] (.+) has already been downloaded/) {
        return .alreadyExists(String(match.1).trimmingCharacters(in: .whitespaces))
    }

    if let match = text.firstMatch(of: /Merging formats into ["'](.+)["']/) {
        return .output(String(match.1))
    }
    if text.contains("[Merger]") || text.contains("[VideoRemuxer]") || text.contains("Merging formats into") {
        return .merging
    }

    if let match = text.firstMatch(of: /\[ExtractAudio\] Destination: (.+)/) {
        return .output(String(match.1).trimmingCharacters(in: .whitespaces))
    }
    if text.contains("[ExtractAudio]") {
        return .extracting
    }

    if let match = text.firstMatch(of: /\[download\] Destination: (.+)/) {
        return .output(String(match.1).trimmingCharacters(in: .whitespaces))
    }

    if text.hasPrefix("/") {
        return .output(text)
    }

    if text.contains("[download]"),
       text.firstMatch(of: /\[download\]\s+[\d.]+%/) != nil,
       let header = text.firstMatch(of: /\[download\]\s+([\d.]+)%/) {
        let fraction = min(max((Double(header.1) ?? 0) / 100, 0), 1)
        var speed: String?
        var eta: String?
        if let timing = text.firstMatch(of: /at\s+(\S+)\s+ETA\s+(\S+)/) {
            speed = cleanMetric(String(timing.1))
            eta = cleanMetric(String(timing.2))
        } else if let timing = text.firstMatch(of: /at\s+(\S+)/) {
            speed = cleanMetric(String(timing.1))
        }
        return .progress(fraction: fraction, speed: speed, eta: eta)
    }

    return nil
}

public func humanize(log: [String]) -> String {
    let text = log.joined(separator: "\n")
    let lower = text.lowercased()

    if lower.contains("private video") {
        return String(localized: "This is a private video — it can't be downloaded.")
    }
    if lower.contains("sign in") || lower.contains("confirm your age") || lower.contains("login required") {
        return String(localized: "The site is asking you to sign in. This video can't be downloaded that way.")
    }
    if lower.contains("not available in your country") || (lower.contains("geo") && lower.contains("restricted")) {
        return String(localized: "This video isn't available in your region.")
    }
    if lower.contains("video unavailable") || lower.contains("this video has been removed") || lower.contains("account associated") {
        return String(localized: "This video isn't available. It may have been removed, or the link is wrong.")
    }
    if lower.contains("ffmpeg") && (lower.contains("not found") || lower.contains("not installed") || lower.contains("could not find")) {
        return String(localized: "ffmpeg is needed to combine video and audio. Install it with the button below.")
    }
    if lower.contains("failed to load python shared library") || lower.contains("_internal/python") {
        return String(localized: "The downloader wasn't installed completely. Press Install again.")
    }
    if lower.contains("unsupported url") {
        return String(localized: "This link doesn't look like a video that can be downloaded.")
    }
    if lower.contains("429") || lower.contains("too many requests") {
        return String(localized: "The site is limiting requests for now. Try again in a little while.")
    }
    if lower.contains("offline") || lower.contains("network is unreachable") || lower.contains("failed to establish a new connection") || lower.contains("connection reset") || lower.contains("operation not permitted") || lower.contains("timed out") || lower.contains("timeout") {
        return String(localized: "No response from the site. If LuLu is on, it blocks the downloader and often shows no prompt. Allow this file in LuLu's rules.")
    }
    if let line = log.reversed().first(where: { $0.contains("ERROR:") }) {
        let cleaned = line.replacingOccurrences(of: "ERROR:", with: "").trimmingCharacters(in: .whitespaces)
        if !cleaned.isEmpty { return cleaned }
    }
    return String(localized: "Couldn't download. Try another quality or check the link.")
}

private func cleanMetric(_ raw: String) -> String? {
    let value = raw.trimmingCharacters(in: .whitespaces)
    if value.isEmpty || value == "Unknown" || value == "NA" || value == "N/A" {
        return nil
    }
    return value
}
