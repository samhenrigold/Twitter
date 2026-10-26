import Foundation
import Testing

@testable import Models

/// Which of a video's variants the viewer and the timeline play.
struct MediaParserTests {
    @Test
    func videoPlaysTheSharpestMP4FullScreenAndALighterOneInline() throws {
        let media = try #require(
            try parse(
                type: "video",
                variants: [
                    ["content_type": "application/x-mpegURL", "url": "https://video.twimg.com/v/pl/a.m3u8"],
                    ["content_type": "video/mp4", "bitrate": 832_000, "url": "https://video.twimg.com/v/480.mp4"],
                    ["content_type": "video/mp4", "bitrate": 10_368_000, "url": "https://video.twimg.com/v/1080.mp4"],
                    ["content_type": "video/mp4", "bitrate": 2_176_000, "url": "https://video.twimg.com/v/720.mp4"]
                ]))
        #expect(media.kind == .video)
        #expect(media.videoURL?.lastPathComponent == "1080.mp4")
        #expect(media.inlineVideoURL?.lastPathComponent == "720.mp4")
        #expect(media.durationMillis == 12_345)
    }

    @Test
    func gifIsItsOneSilentMP4() throws {
        let media = try #require(
            try parse(
                type: "animated_gif",
                variants: [
                    ["content_type": "video/mp4", "bitrate": 0, "url": "https://video.twimg.com/tweet_video/a.mp4"]
                ]
            ))
        #expect(media.kind == .gif)
        #expect(media.videoURL == media.inlineVideoURL)
        #expect(media.videoURL?.lastPathComponent == "a.mp4")
    }

    @Test
    func streamOnlyVideoPlaysItsPlaylist() throws {
        let media = try #require(
            try parse(
                type: "video",
                variants: [["content_type": "application/x-mpegURL", "url": "https://video.twimg.com/v/pl/a.m3u8"]]))
        #expect(media.videoURL?.pathExtension == "m3u8")
        #expect(media.inlineVideoURL == media.videoURL)
    }

    private func parse(type: String, variants: [[String: Any]]) throws -> Media? {
        let entry: [String: Any] = [
            "id_str": "m1",
            "type": type,
            "media_url_https": "https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/a.jpg",
            "original_info": ["width": 1920, "height": 1080],
            "video_info": ["duration_millis": 12_345, "variants": variants]
        ]
        let raw: [String: Any] = [
            "__typename": "Tweet",
            "rest_id": "1",
            "core": [
                "user_results": ["result": ["rest_id": "u1", "core": ["screen_name": "author", "name": "Author"]]]
            ],
            "legacy": ["full_text": "", "id_str": "1", "extended_entities": ["media": [entry]]]
        ]
        // Round-trip through JSON so values are the Foundation types Twitter's responses decode to.
        let json = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: raw))
        return TimelineParser.tweet(from: try #require(json as? [String: Any]))?.media.first
    }
}
