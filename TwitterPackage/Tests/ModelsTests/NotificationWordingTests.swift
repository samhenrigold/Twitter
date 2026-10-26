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
