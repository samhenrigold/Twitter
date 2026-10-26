import Foundation

package enum TwitterError: LocalizedError, Sendable {
    case notSignedIn
    case unauthorized
    case rateLimited(resetAt: Date?)
    case http(Int, String)
    case api(String)
    case catalog(String)
    case missingOperation(String)

    package var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're not signed in."
        case .unauthorized: "Your Twitter session expired. Sign in again."
        case .rateLimited(let reset):
            if let reset {
                "Twitter rate limit reached. Try again \(reset.formatted(.relative(presentation: .named)))."
            } else {
                "Twitter rate limit reached. Try again in a few minutes."
            }
        case .http(let code, let body): "Twitter returned HTTP \(code). \(body.prefix(200))"
        case .api(let message): message
        case .catalog(let message): message
        case .missingOperation(let name): "Twitter's web client no longer exposes \(name)."
        }
    }
}
