import Foundation
import Testing

@testable import PostText

/// One case of twitter-text's conformance suite: `conformance/*.yml` at twitter/twitter-text 30e2430 (2021-10-21),
/// converted to JSON as is under `Resources/TwitterText/conformance` (`ruby -ryaml -rjson`, one file per YAML file).
struct TwitterTextConformanceCase<Expected: Decodable & Sendable>: Decodable, Sendable, CustomTestStringConvertible {
    enum File: String {
        case extract, tlds, validate
    }

    let description: String
    let text: String
    let expected: Expected

    var testDescription: String { description }

    /// The cases of one section of `file`. An optional `Expected` reads `null` as `nil` (`replies`).
    static func load(_ file: File, _ section: String) throws -> [Self] {
        let url = try #require(
            Bundle.module.url(
                forResource: file.rawValue, withExtension: "json", subdirectory: "TwitterText/conformance"))
        let decoder = JSONDecoder()
        decoder.userInfo[.conformanceSection] = section
        return try decoder.decode(Section.self, from: Data(contentsOf: url)).cases
    }

    private struct Section: Decodable {
        let cases: [TwitterTextConformanceCase]

        init(from decoder: any Decoder) throws {
            let name = decoder.userInfo[.conformanceSection] as? String ?? ""
            let sections = try decoder.container(keyedBy: SectionKey.self)
            cases = try sections.decode([TwitterTextConformanceCase].self, forKey: SectionKey(stringValue: name))
        }
    }

    private struct SectionKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}

extension CodingUserInfoKey {
    fileprivate static let conformanceSection = CodingUserInfoKey(rawValue: "conformanceSection")!
}
