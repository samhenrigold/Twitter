extension TwitterTextConfiguration {
    /// Code points from `start` through `end` (inclusive, as in the JSON) weigh `weight`.
    package struct WeightedRange: Hashable, Codable, Sendable {
        package var start: UInt32
        package var end: UInt32
        package var weight: Int

        package init(start: UInt32, end: UInt32, weight: Int) {
            self.start = start
            self.end = end
            self.weight = weight
        }

        package func contains(_ scalar: Unicode.Scalar) -> Bool {
            (start...end).contains(scalar.value)
        }
    }
}
