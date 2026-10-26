import Foundation
import Testing

@testable import Models

struct ListParserTests {
    @Test
    func listsOnTheirOwnAndInModulesWithTheLastPageCursorDropped() throws {
        let json = """
            {"data":{"user":{"result":{"timeline":{"timeline":{"instructions":[{"type":"TimelineAddEntries","entries":[
              {"entryId":"list-1","content":{"entryType":"TimelineTimelineItem","itemContent":{
                "__typename":"TimelineTwitterList","list":{"id_str":"1","name":"Swift","description":"Swifty",
                "member_count":48,"subscriber_count":1204,"mode":"Public"}}}},
              {"entryId":"owned-module","content":{"entryType":"TimelineTimelineModule","items":[
                {"entryId":"list-2","item":{"itemContent":{"__typename":"TimelineTwitterList",
                  "list":{"id_str":"2","name":"Friends","member_count":12,"mode":"Private"}}}},
                {"entryId":"list-1-again","item":{"itemContent":{"__typename":"TimelineTwitterList",
                  "list":{"id_str":"1","name":"Swift"}}}}]}},
              {"entryId":"cursor-bottom","content":{"entryType":"TimelineTimelineCursor","cursorType":"Bottom",
                "value":"0|123"}}]}]}}}}}}
            """
        let page = TimelineParser.listPage(from: try JSONSerialization.jsonObject(with: Data(json.utf8)))
        #expect(page.lists.map(\.id) == ["1", "2"])
        #expect(page.lists[0].memberCount == 48)
        #expect(page.lists[0].subscriberCount == 1204)
        #expect(!page.lists[0].isPrivate)
        #expect(page.lists[1].isPrivate)
        #expect(page.bottomCursor == nil)
    }
}

struct TypeaheadParserTests {
    @Test
    func usersFromTheFlatV1Shape() throws {
        let json = """
            {"num_results":2,"users":[
              {"id":12,"id_str":"12","name":"Point-Free","screen_name":"pointfreeco",
               "profile_image_url_https":"https://pbs.twimg.com/a.jpg","is_blue_verified":true},
              {"id_str":"34","name":"Brandon","screen_name":"mbrandonw"}],"topics":[],"hashtags":[]}
            """
        let users = TimelineParser.typeaheadUsers(from: try JSONSerialization.jsonObject(with: Data(json.utf8)))
        #expect(users.map(\.screenName) == ["pointfreeco", "mbrandonw"])
        #expect(users[0].isVerified)
        #expect(users[0].avatarURL != nil)
    }
}
