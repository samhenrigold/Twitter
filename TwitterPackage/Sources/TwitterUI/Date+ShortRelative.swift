import Foundation

extension Date {
    package var shortRelative: String { shortRelative(to: .now) }

    /// "2m", "3h", "4d", then the date, as of `now`.
    package func shortRelative(to now: Date) -> String {
        let seconds = now.timeIntervalSince(self)
        switch seconds {
        case ..<60: return "\(Swift.max(Int(seconds), 0))s"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<(86_400 * 7): return "\(Int(seconds / 86_400))d"
        default: return formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
