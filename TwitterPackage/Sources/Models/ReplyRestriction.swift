/// Who may reply to a post when its author limited replies.
package struct ReplyRestriction: Hashable, Codable, Sendable {
    package enum Policy: String, Hashable, Codable, Sendable {
        case mentioned
        case following
        case verified
        case subscribers
        case other
    }

    package var policy: Policy
    package var ownerScreenName: String?
    package var viewerCanReply: Bool
    /// Twitter's own wording, used for policies the app doesn't know.
    package var prompt: String?

    package init(policy: Policy, ownerScreenName: String? = nil, viewerCanReply: Bool, prompt: String? = nil) {
        self.policy = policy
        self.ownerScreenName = ownerScreenName
        self.viewerCanReply = viewerCanReply
        self.prompt = prompt
    }

    package var message: String {
        let owner = ownerScreenName.map { "@\($0)" }
        switch policy {
        case .mentioned:
            return owner.map { "People \($0) mentioned can reply" } ?? "Only people mentioned can reply"
        case .following:
            return owner.map { "Accounts \($0) follows can reply" } ?? "Only accounts the author follows can reply"
        case .verified:
            return "Only verified accounts can reply"
        case .subscribers:
            return owner.map { "Only \($0)'s subscribers can reply" } ?? "Only subscribers can reply"
        case .other:
            return prompt ?? "Replies to this Tweet are limited"
        }
    }
}
