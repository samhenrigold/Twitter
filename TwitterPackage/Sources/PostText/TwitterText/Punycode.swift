/// RFC 3492 Punycode, as far as twitter-text needs it: the ASCII form of a domain label, to measure against DNS's
/// 63-character limit.
enum Punycode {
    /// What `punycode.toASCII` gives for `label`: each part between dots (ideographic and fullwidth ones included)
    /// as is when it's ASCII, else `xn--` and its encoding.
    static func ascii(_ label: Substring.UnicodeScalarView) -> String {
        label.split(omittingEmptySubsequences: false, whereSeparator: separators.contains)
            .map { part in part.allSatisfy(\.isASCII) ? String(Substring(part)) : "xn--" + encode(Array(part)) }
            .joined(separator: ".")
    }

    private static let separators: Set<Unicode.Scalar> = [".", "\u{3002}", "\u{FF0E}", "\u{FF61}"]

    private static let base = 36
    private static let tMin = 1
    private static let tMax = 26
    private static let skew = 38
    private static let damp = 700

    /// The Bootstring encoding of `input` (RFC 3492 §6.3), without the `xn--` prefix.
    private static func encode(_ input: [Unicode.Scalar]) -> String {
        var output = String(String.UnicodeScalarView(input.filter(\.isASCII)))
        let basicCount = output.unicodeScalars.count
        var handled = basicCount
        if basicCount > 0 { output.append("-") }

        var n = 0x80
        var delta = 0
        var bias = 72
        let values = input.map { Int($0.value) }
        while handled < values.count {
            let next = values.filter { $0 >= n }.min()!
            delta += (next - n) * (handled + 1)
            n = next
            for value in values {
                if value < n { delta += 1 }
                guard value == n else { continue }
                var q = delta
                var k = base
                while true {
                    let t = k <= bias ? tMin : k >= bias + tMax ? tMax : k - bias
                    if q < t { break }
                    output.append(digit(t + (q - t) % (base - t)))
                    q = (q - t) / (base - t)
                    k += base
                }
                output.append(digit(q))
                bias = adapt(delta, count: handled + 1, isFirst: handled == basicCount)
                delta = 0
                handled += 1
            }
            delta += 1
            n += 1
        }
        return output
    }

    private static func adapt(_ delta: Int, count: Int, isFirst: Bool) -> Int {
        var delta = isFirst ? delta / damp : delta / 2
        delta += delta / count
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }

    private static func digit(_ value: Int) -> Character {
        Character(Unicode.Scalar(UInt8(value < 26 ? 0x61 + value : 0x16 + value)))
    }
}
