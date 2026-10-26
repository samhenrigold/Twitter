import Foundation
import Testing

@testable import Models

struct TrendParserTests {
    @Test
    func trendsFromModulesWithTheirSearchQueryAndMetadata() throws {
        let json = """
            {"data":{"explore_page":{"body":{"initialTimeline":{"timeline":{"timeline":{"instructions":[
              {"type":"TimelineAddEntries","entries":[
                {"entryId":"trends-module","content":{"entryType":"TimelineTimelineModule","items":[
                  {"entryId":"t1","item":{"itemContent":{"__typename":"TimelineTrend","name":"#WWDC",
                    "trend_url":{"url":"twitter://search/?query=%23WWDC&src=trend_click"},
                    "trend_metadata":{"domain_context":"Trending in Technology","meta_description":"52.1K posts"}}}},
                  {"entryId":"t2","item":{"itemContent":{"__typename":"TimelineTrend","name":"Swift 6.4",
                    "trend_metadata":{"domain_context":""}}}}]}}]}]}}}}}}}
            """
        let trends = TimelineParser.trends(from: try JSONSerialization.jsonObject(with: Data(json.utf8)))
        #expect(
            trends == [
                Trend(name: "#WWDC", query: "#WWDC", context: "Trending in Technology", volume: "52.1K Tweets"),
                Trend(name: "Swift 6.4")
            ]
        )
    }
}
