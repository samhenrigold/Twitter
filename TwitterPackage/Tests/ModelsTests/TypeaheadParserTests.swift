import Foundation
import Testing

@testable import Models

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
