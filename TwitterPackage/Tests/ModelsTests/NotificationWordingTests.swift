import Foundation
import Testing

@testable import Models

struct NotificationWordingTests {
    @Test
    func postsAndRepostsBecomeTweetsAndRetweets() {
        #expect(TimelineParser.tweetWording("liked your post") == "liked your Tweet")
        #expect(TimelineParser.tweetWording("liked your repost") == "liked your Retweet")
        #expect(TimelineParser.tweetWording("reposted your post") == "Retweeted your Tweet")
        #expect(TimelineParser.tweetWording("liked 3 of your posts") == "liked 3 of your Tweets")
        #expect(TimelineParser.tweetWording("New post notifications") == "New Tweet notifications")
        #expect(TimelineParser.tweetWording("a postcard and a signpost") == "a postcard and a signpost")
    }

    @Test
    func namesStayAsTheyAreAndKeepTheirBold() {
        // "Post Malone" is bold: a name, not a Tweet.
        let worded = TimelineParser.tweetWording(
            "Post Malone and Poster reposted your post", boldRanges: [0..<11, 16..<22])
        #expect(worded.text == "Post Malone and Poster Retweeted your Tweet")
        #expect(worded.boldRanges == [0..<11, 16..<22])

        let moved = TimelineParser.tweetWording("Your post was liked by Ana", boldRanges: [23..<26])
        #expect(moved.text == "Your Tweet was liked by Ana")
        #expect(moved.boldRanges == [24..<27])
    }
}

struct NotificationUnreadTests {
    @Test
    func entriesSortedAboveTheUnreadMarkerAreUnread() throws {
        let json = """
            {"data":{"viewer_v2":{"user_results":{"result":{"notification_timeline":{"timeline":{"instructions":[
              {"type":"TimelineAddEntries","entries":[
                {"entryId":"notification-1","sortIndex":"1761470000000","content":{"entryType":"TimelineTimelineItem",
                  "itemContent":{"itemType":"TimelineNotification","id":"n1","notification_icon":"heart_icon",
                    "rich_message":{"text":"Ana liked your post","entities":[{"fromIndex":0,"toIndex":3}]}}}},
                {"entryId":"notification-2","sortIndex":"1761460000000","content":{"entryType":"TimelineTimelineItem",
                  "itemContent":{"itemType":"TimelineNotification","id":"n2","notification_icon":"person_icon",
                    "rich_message":{"text":"Bo followed you","entities":[]}}}}]},
              {"type":"TimelineMarkEntriesUnreadGreaterThanSortIndex","sort_index":"1761465000000"}]}}}}}}}
            """
        let page = TimelineParser.page(from: try JSONSerialization.jsonObject(with: Data(json.utf8)))
        #expect(page.items.map(\.isUnread) == [true, false])
        #expect(TimelineParser.isSortIndex("10", above: "9"))
        #expect(!TimelineParser.isSortIndex("9", above: "10"))
    }
}
