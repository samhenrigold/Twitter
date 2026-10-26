import Foundation
import Testing

@testable import Models

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
