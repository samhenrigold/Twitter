/// Decodes the HTML character references Twitter's API leaves in text: the five named XML ones, `&nbsp;`, and
/// numeric `&#39;` / `&#x27;` forms. Anything else stays as written.
enum CharacterReferences {
    private static let named: [Substring: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var index = text.startIndex
        while let ampersand = text[index...].firstIndex(of: "&") {
            result += text[index..<ampersand]
            let afterAmpersand = text.index(after: ampersand)
            guard let semicolon = text[afterAmpersand...].prefix(10).firstIndex(of: ";"),
                let decoded = reference(text[afterAmpersand..<semicolon])
            else {
                result.append("&")
                index = afterAmpersand
                continue
            }
            result += decoded
            index = text.index(after: semicolon)
        }
        result += text[index...]
        return result
    }

    private static func reference(_ name: Substring) -> String? {
        if let named = named[name] { return named }
        guard name.first == "#" else { return nil }
        let digits = name.dropFirst()
        let value =
            digits.first == "x" || digits.first == "X"
            ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
        return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}
