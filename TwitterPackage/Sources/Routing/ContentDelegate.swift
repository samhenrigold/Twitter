package enum ContentDelegate: Equatable {
    case compose(Draft)
    /// The compose button held: a new Tweet opened on its saved drafts, as Twitter's is.
    case drafts
    case open(Route)
    case signOut
}
