import Foundation
import Testing

@testable import Models

struct TweetLanguageTests {
    @Test
    func offersTranslationOnlyForAnotherPlacedLanguage() {
        let english = Locale.Language(identifier: "en-US")
        var tweet = Tweet.mock(id: "1", text: "こんにちは")
        tweet.language = "ja"
        #expect(tweet.isInAnotherLanguage(than: english))
        tweet.language = "en"
        #expect(!tweet.isInAnotherLanguage(than: english))
        tweet.language = "und"
        #expect(!tweet.isInAnotherLanguage(than: english))
        tweet.language = nil
        #expect(!tweet.isInAnotherLanguage(than: english))
    }
}
