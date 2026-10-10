import Foundation
import Testing
@testable import CinnabarCore

@Test func acceptsWatchShortsAndShareText() {
    #expect(MediaLink.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ") != nil)
    #expect(MediaLink.parse("https://youtu.be/dQw4w9WgXcQ") != nil)
    #expect(MediaLink.parse("https://www.youtube.com/shorts/abcdefghijk") != nil)
    #expect(MediaLink.parse("смотри https://youtu.be/abcdefghijk, пожалуйста") != nil)
    #expect(MediaLink.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLxxxx") != nil)
    #expect(MediaLink.parse("https://vimeo.com/123") != nil)
    #expect(MediaLink.parse("vimeo.com/123") != nil)
    #expect(MediaLink.parse("смотри https://soundcloud.com/artist/track, пожалуйста") != nil)
    #expect(MediaLink.parse("https://www.youtube.com/feed/subscriptions") == nil)
    #expect(MediaLink.parse("https://www.youtube.com/playlist?list=PLxxxx") == nil)
    #expect(MediaLink.parse("https://vimeo.com") == nil)
    #expect(MediaLink.parse("просто текст") == nil)
}

@Test func parsesProgressAndFinalPath() {
    let progress = interpret("[download]  50.0% of   10.00MiB at  1.25MiB/s ETA 00:04")
    #expect(progress == .progress(fraction: 0.5, speed: "1.25MiB/s", eta: "00:04"))

    let done = interpret(#"[Merger] Merging formats into "/tmp/clip [abc].mp4""#)
    #expect(done == .output("/tmp/clip [abc].mp4"))

    let printed = interpret("/tmp/clip [abc].mp4")
    #expect(printed == .output("/tmp/clip [abc].mp4"))

    let existing = interpret("[download] /tmp/clip [abc].mp4 has already been downloaded")
    #expect(existing == .alreadyExists("/tmp/clip [abc].mp4"))
}

@Test func explainsPrivateVideo() {
    let message = humanize(log: ["ERROR: Private video. Sign in if you've been granted access to this video"])
    #expect(message.contains("private"))
    let broken = humanize(log: ["Failed to load Python shared library '/tmp/bin/_internal/Python'"])
    #expect(broken.contains("wasn't installed completely"))
}

@Test func offersOnlyHeightsThatExist() {
    let details = VideoDetails(
        id: "abc",
        title: "Тест",
        channel: "Канал",
        thumbnail: nil,
        duration: 12,
        viewCount: 1500,
        formats: [
            StreamFormat(height: 1080, vcodec: "avc1.640028", acodec: "none", ext: "mp4", size: 5_000_000, tbr: 2500),
            StreamFormat(height: 720, vcodec: "avc1.4d401f", acodec: "none", ext: "mp4", size: 2_000_000, tbr: 1200),
            StreamFormat(height: nil, vcodec: "none", acodec: "mp4a.40.2", ext: "m4a", size: 300_000, tbr: 128)
        ]
    )
    #expect(details.qualities(hasFFmpeg: true) == [.best, .p1080, .p720, .audio])
    #expect(details.qualities(hasFFmpeg: false) == [.best, .audio])
    #expect(details.estimate(for: .p1080) == 5_300_000)
    #expect(details.estimate(for: .audio) == 300_000)

    let fourK = VideoDetails(
        id: "abc",
        title: "4K",
        channel: nil,
        thumbnail: nil,
        duration: nil,
        viewCount: nil,
        formats: [
            StreamFormat(height: 2160, vcodec: "av01", acodec: "none", ext: "mp4", size: nil, tbr: nil),
            StreamFormat(height: 360, vcodec: "avc1", acodec: "none", ext: "mp4", size: nil, tbr: nil)
        ]
    )
    #expect(fourK.qualities(hasFFmpeg: true) == [.best, .p2160, .audio])
}

@Test func asksForTheSelectedResolution() {
    let fourK = FormatSelection.arguments(for: .p2160, hasFFmpeg: true).joined(separator: " ")
    #expect(fourK.contains("bv*[height<=2160][height>=2120][vcodec^=av01]"))
    #expect(!fourK.contains("bv*[vcodec^=avc1]"))

    let fullHD = FormatSelection.arguments(for: .p1080, hasFFmpeg: true).joined(separator: " ")
    #expect(fullHD.contains("bv*[height<=1080][height>=1040][vcodec^=avc1]"))
    #expect(fullHD.contains("b[height<=1080][height>=1040]"))
    #expect(!fullHD.contains("height<=2160"))
    let selector = FormatSelection.arguments(for: .p1080, hasFFmpeg: true)[1]
    #expect(selector.split(separator: "/").last != "b")

    #expect(FormatSelection.outputName(for: .p2160).contains("%(height)sp"))
    #expect(FormatSelection.outputName(for: .p1080) != FormatSelection.outputName(for: .audio))
    #expect(FormatSelection.outputName(for: .audio).contains(" audio."))
}

@Test func readsVideoJSON() throws {
    let json = """
    {"id":"abc","title":"Ролик","channel":"Канал","duration":65,"view_count":10,"thumbnail":"https://i.ytimg.com/vi/abc/hqdefault.jpg","formats":[{"height":720,"vcodec":"avc1","acodec":"none","ext":"mp4","filesize":100}]}
    """.data(using: .utf8)!
    let details = try VideoDetails(json: json)
    #expect(details.title == "Ролик")
    #expect(details.maxVideoHeight == 720)
    #expect(details.formats.count == 1)
}
