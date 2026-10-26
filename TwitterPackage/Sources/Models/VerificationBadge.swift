package enum VerificationBadge: Hashable, Sendable {
    case blue
    case business
    case government
}

extension User {
    package var verificationBadge: VerificationBadge? {
        switch verifiedType?.lowercased() {
        case "business": .business
        case "government": .government
        default: isVerified ? .blue : nil
        }
    }
}
