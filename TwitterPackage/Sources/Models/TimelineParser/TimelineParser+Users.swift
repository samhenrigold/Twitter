import Foundation

extension TimelineParser {
    static func user(fromResult container: Any?) -> User? {
        guard let result = ((container as? JSON)?["user_results"] as? JSON)?["result"] as? JSON else { return nil }
        return user(from: result)
    }

    package static func user(from result: JSON) -> User? {
        guard result["__typename"] as? String != "UserUnavailable",
            let id = result["rest_id"] as? String
        else { return nil }
        let legacy = result["legacy"] as? JSON ?? [:]
        let core = result["core"] as? JSON ?? [:]
        guard let screenName = (core["screen_name"] as? String) ?? (legacy["screen_name"] as? String) else {
            return nil
        }

        var user = User(
            id: id,
            name: (core["name"] as? String) ?? (legacy["name"] as? String) ?? screenName,
            screenName: screenName
        )
        user.avatarURL =
            (((result["avatar"] as? JSON)?["image_url"] as? String) ?? (legacy["profile_image_url_https"] as? String))
            .flatMap(URL.init(string:))
        let banner = ((result["banner"] as? JSON)?["image_url"] as? String) ?? (legacy["profile_banner_url"] as? String)
        user.bannerURL = banner.flatMap { URL(string: $0 + "/1500x500") }

        let profileBio = result["profile_bio"] as? JSON
        let entities = (profileBio?["entities"] as? JSON) ?? (legacy["entities"] as? JSON)
        var bio = (profileBio?["description"] as? String) ?? (legacy["description"] as? String) ?? ""
        for url in (entities?["description"] as? JSON)?["urls"] as? [JSON] ?? [] {
            if let short = url["url"] as? String, let display = url["display_url"] as? String {
                bio = bio.replacingOccurrences(of: short, with: display)
            }
        }
        user.bio = decodeEntities(bio)
        user.location = ((result["location"] as? JSON)?["location"] as? String) ?? (legacy["location"] as? String) ?? ""
        let website = ((entities?["url"] as? JSON)?["urls"] as? [JSON])?.first
        user.website = website?["display_url"] as? String
        user.websiteURL = (website?["expanded_url"] as? String).flatMap(URL.init(string:))

        let counts = result["relationship_counts"] as? JSON
        user.followersCount = counts?["followers"] != nil ? int(counts?["followers"]) : int(legacy["followers_count"])
        user.followingCount = counts?["following"] != nil ? int(counts?["following"]) : int(legacy["friends_count"])
        let tweetCounts = result["tweet_counts"] as? JSON
        user.postsCount = tweetCounts?["tweets"] != nil ? int(tweetCounts?["tweets"]) : int(legacy["statuses_count"])
        user.isVerified =
            (result["is_blue_verified"] as? Bool ?? false)
            || ((result["verification"] as? JSON)?["verified"] as? Bool ?? false)
            || (legacy["verified"] as? Bool ?? false)
        user.verifiedType =
            (legacy["verified_type"] as? String) ?? ((result["verification"] as? JSON)?["verified_type"] as? String)
        user.isProtected =
            ((result["privacy"] as? JSON)?["protected"] as? Bool) ?? (legacy["protected"] as? Bool ?? false)
        let relationship = result["relationship_perspectives"] as? JSON
        user.isFollowing = (relationship?["following"] as? Bool) ?? (legacy["following"] as? Bool ?? false)
        user.followsViewer = (relationship?["followed_by"] as? Bool) ?? (legacy["followed_by"] as? Bool ?? false)
        user.isMuting = (relationship?["muting"] as? Bool) ?? (legacy["muting"] as? Bool ?? false)
        user.isBlocking = (relationship?["blocking"] as? Bool) ?? (legacy["blocking"] as? Bool ?? false)
        user.blocksViewer = (relationship?["blocked_by"] as? Bool) ?? (legacy["blocked_by"] as? Bool ?? false)
        if let label = (result["affiliates_highlighted_label"] as? JSON)?["label"] as? JSON,
            let description = label["description"] as? String
        {
            user.affiliate = AffiliateLabel(
                description: description,
                badgeURL: ((label["badge"] as? JSON)?["url"] as? String).flatMap(URL.init(string:)),
                url: ((label["url"] as? JSON)?["url"] as? String).flatMap(URL.init(string:))
            )
        }
        user.pinnedTweetID =
            ((result["pinned_items"] as? JSON)?["tweet_ids_str"] as? [String])?.first
            ?? (legacy["pinned_tweet_ids_str"] as? [String])?.first
        user.joined = (((core["created_at"] as? String) ?? (legacy["created_at"] as? String))).flatMap(parseDate)
        return user
    }

    /// The accounts in a typeahead response (`search/typeahead.json`), which come in v1.1's flat shape.
    package static func typeaheadUsers(from root: Any) -> [User] {
        ((root as? JSON)?["users"] as? [JSON] ?? []).compactMap { legacy in
            guard let id = (legacy["id_str"] as? String) ?? (legacy["id"] as? Int).map(String.init) else { return nil }
            return user(from: ["rest_id": id, "legacy": legacy, "is_blue_verified": legacy["is_blue_verified"] ?? false]
            )
        }
    }
}
