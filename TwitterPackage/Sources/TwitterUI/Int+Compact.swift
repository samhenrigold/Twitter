import Foundation

extension Int {
    /// Twitter's count style: the full number below 10,000 ("1,234"), then K / M / B with one decimal, truncated and
    /// without a trailing ".0" ("12.3K", "123K", "1.2M").
    package var compact: String { compact(locale: .current) }

    /// ``compact`` in a given locale, which decides the grouping and decimal separators.
    package func compact(locale: Locale) -> String {
        guard magnitude >= 10_000 else { return formatted(.number.locale(locale)) }
        let units: [(Int, String)] = [
            (1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")
        ]
        let value = self.magnitude
        guard let (divisor, suffix) = units.first(where: { value >= UInt($0.0) }) else {
            return formatted(.number.locale(locale))
        }
        // Integer division truncates, so 1,299,999 reads "1.2M", never "1.3M".
        let tenths = value / (UInt(divisor) / 10)
        let number = Double(tenths / 10) + Double(tenths % 10) / 10
        return (self < 0 ? "-" : "") + number.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
            + suffix
    }
}
