import CryptoKit
import Foundation

/// Generates the `x-client-transaction-id` header the x.com web client sends with every request.
///
/// Ported from iSarabjitDhiman/XClientTransaction and Lqm1/x-client-transaction-id (MIT).
/// The math intentionally mirrors the reference implementation (including JavaScript rounding)
/// so future upstream fixes can be diffed against it.
struct TransactionIDGenerator: Sendable {
    let keyBytes: [UInt8]
    let animationKey: String

    private static let keyword = "obfiowerehiring"
    private static let additionalRandomNumber: UInt8 = 3
    private static let epochOffset: TimeInterval = 1_682_924_400

    enum Failure: Error, LocalizedError {
        case missingVerificationKey, missingIndices, missingFrames

        var errorDescription: String? {
            switch self {
            case .missingVerificationKey: "x.com served no twitter-site-verification key"
            case .missingIndices: "Could not read key byte indices from the ondemand.s chunk"
            case .missingFrames: "x.com served no loading-x-anim frames"
            }
        }
    }

    /// - Parameters:
    ///   - homeHTML: HTML of `https://x.com/i/jf/` (classic web client).
    ///   - ondemandJS: Source of the `ondemand.s` chunk referenced by that HTML.
    init(homeHTML: String, ondemandJS: String) throws {
        guard
            let key = Self.firstMatch(
                #"name=["']twitter-site-verification["'][^>]*?content=["']([^"']+)["']"#, in: homeHTML)
                ?? Self.firstMatch(
                    #"content=["']([^"']+)["'][^>]*?name=["']twitter-site-verification["']"#, in: homeHTML),
            let data = Data(base64Encoded: key)
        else { throw Failure.missingVerificationKey }
        let keyBytes = [UInt8](data)

        let indices = Self.allMatches(#"\(\w\[(\d{1,2})\],\s*16\)"#, in: ondemandJS).compactMap { Int($0) }
        guard indices.count > 1, keyBytes.count > 5 else { throw Failure.missingIndices }
        let rowIndexSource = indices[0]
        let keyByteIndices = Array(indices.dropFirst())

        let frames = Self.frames(in: homeHTML)
        guard frames.count >= 4 else { throw Failure.missingFrames }

        let rowIndex = Int(keyBytes[rowIndexSource] % 16)
        var frameTime = keyByteIndices.reduce(1.0) { $0 * Double(keyBytes[$1] % 16) }
        frameTime = Self.jsRound(frameTime / 10) * 10

        let grid = Self.grid(fromPath: frames[Int(keyBytes[5]) % 4])
        guard rowIndex < grid.count, !grid[rowIndex].isEmpty else { throw Failure.missingFrames }

        self.keyBytes = keyBytes
        self.animationKey = Self.animate(grid[rowIndex], targetTime: frameTime / 4096)
    }

    func generate(method: String, path: String, date: Date = .now, randomByte: UInt8 = .random(in: 0...255)) -> String {
        let timeNow = Int(floor(date.timeIntervalSince1970 - Self.epochOffset))
        let timeBytes = (0..<4).map { UInt8(truncatingIfNeeded: timeNow >> (8 * $0)) }
        let payload = "\(method)!\(path)!\(timeNow)\(Self.keyword)\(animationKey)"
        let hash = Array(SHA256.hash(data: Data(payload.utf8)))
        let bytes = keyBytes + timeBytes + hash.prefix(16) + [Self.additionalRandomNumber]
        let out = [randomByte] + bytes.map { $0 ^ randomByte }
        return Data(out).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    // MARK: Animation key

    private static func animate(_ frames: [Int], targetTime: Double) -> String {
        let values = frames.map(Double.init)
        guard values.count >= 7 else { return "" }
        let fromColor = Array(values[0..<3]) + [1]
        let toColor = Array(values[3..<6]) + [1]
        let toRotation = solve(values[6], min: 60, max: 360, rounding: true)
        let curves = values.dropFirst(7).enumerated().map { index, value in
            solve(value, min: index % 2 == 1 ? -1 : 0, max: 1, rounding: false)
        }

        let progress = cubicValue(curves, time: targetTime)
        let color = zip(fromColor, toColor).map { max(0, $0 * (1 - progress) + $1 * progress) }
        let rotation = toRotation * progress
        let radians = rotation * .pi / 180
        let matrix = [cos(radians), -sin(radians), sin(radians), cos(radians)]

        var parts = color.dropLast().map { String(Int(jsRound($0)), radix: 16) }
        for value in matrix {
            let rounded = abs(jsRound(value * 100) / 100)
            let hex = floatToHex(rounded)
            parts.append(hex.hasPrefix(".") ? "0\(hex)".lowercased() : (hex.isEmpty ? "0" : hex))
        }
        parts += ["0", "0"]
        return parts.joined().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "-", with: "")
    }

    private static func solve(_ value: Double, min: Double, max: Double, rounding: Bool) -> Double {
        let result = value * (max - min) / 255 + min
        return rounding ? floor(result) : jsRound(result * 100) / 100
    }

    private static func cubicValue(_ c: [Double], time: Double) -> Double {
        guard c.count >= 4 else { return time }
        if time <= 0 {
            var gradient = 0.0
            if c[0] > 0 { gradient = c[1] / c[0] } else if c[1] == 0, c[2] > 0 { gradient = c[3] / c[2] }
            return gradient * time
        }
        if time >= 1 {
            var gradient = 0.0
            if c[2] < 1 {
                gradient = (c[3] - 1) / (c[2] - 1)
            } else if c[2] == 1, c[0] < 1 {
                gradient = (c[1] - 1) / (c[0] - 1)
            }
            return 1 + gradient * (time - 1)
        }
        func calc(_ a: Double, _ b: Double, _ m: Double) -> Double {
            3 * a * (1 - m) * (1 - m) * m + 3 * b * (1 - m) * m * m + m * m * m
        }
        var start = 0.0
        var end = 1.0
        var mid = 0.0
        while start < end {
            mid = (start + end) / 2
            let estimate = calc(c[0], c[2], mid)
            if abs(time - estimate) < 0.00001 { return calc(c[1], c[3], mid) }
            if estimate < time { start = mid } else { end = mid }
        }
        return calc(c[1], c[3], mid)
    }

    private static func floatToHex(_ input: Double) -> String {
        var x = input
        var result: [String] = []
        var quotient = floor(x)
        var fraction = x - quotient
        while quotient > 0 {
            quotient = floor(x / 16)
            let remainder = Int(floor(x - quotient * 16))
            result.insert(remainder > 9 ? String(UnicodeScalar(UInt8(remainder + 55))) : String(remainder), at: 0)
            x = quotient
        }
        if fraction == 0 { return result.joined() }
        result.append(".")
        while fraction > 0 {
            fraction *= 16
            let integer = Int(floor(fraction))
            fraction -= Double(integer)
            result.append(integer > 9 ? String(UnicodeScalar(UInt8(integer + 55))) : String(integer))
        }
        return result.joined()
    }

    /// JavaScript `Math.round` (rounds .5 toward +∞).
    private static func jsRound(_ x: Double) -> Double { floor(x + 0.5) }

    // MARK: HTML parsing

    /// The `d` attribute of the second `<path>` in each `loading-x-anim-*` SVG, in document order.
    private static func frames(in html: String) -> [String] {
        var frames: [String] = []
        var searchRange = html.startIndex..<html.endIndex
        while let idRange = html.range(of: "id=\"loading-x-anim-", range: searchRange) {
            let svgEnd =
                html.range(of: "</svg>", range: idRange.upperBound..<html.endIndex)?.lowerBound ?? html.endIndex
            let svg = String(html[idRange.upperBound..<svgEnd])
            let paths = allMatches(#"<path[^>]*?\sd="([^"]*)""#, in: svg)
            if paths.count > 1 { frames.append(paths[1]) }
            searchRange = svgEnd..<html.endIndex
        }
        return frames
    }

    private static func grid(fromPath d: String) -> [[Int]] {
        guard d.count > 9 else { return [] }
        return d.dropFirst(9).components(separatedBy: "C").map { item in
            item.replacingOccurrences(of: #"[^\d]+"#, with: " ", options: .regularExpression)
                .split(separator: " ").compactMap { Int($0) }
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        allMatches(pattern, in: text, limit: 1).first
    }

    static func allMatches(_ pattern: String, in text: String, limit: Int = .max) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var results: [String] = []
        let ns = text as NSString
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, stop in
            guard let match, match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return }
            results.append(ns.substring(with: match.range(at: 1)))
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }
}
