import Foundation

/// A deterministic, portable pseudo-random generator.
///
/// `SystemRandomNumberGenerator` is deliberately *not* reproducible, which makes
/// it useless for daily challenges, replays and tests. This is a SplitMix64
/// generator: tiny, fast, well distributed, and — crucially — it produces the
/// same stream for the same seed on every device, OS version and architecture.
public struct SeededGenerator: RandomNumberGenerator, Codable, Sendable, Hashable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        // Avoid the degenerate all-zero state.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `0..<upperBound`, using rejection sampling so the
    /// distribution has no modulo bias.
    public mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let bound = UInt64(upperBound)
        let limit = UInt64.max - (UInt64.max % bound)
        var candidate = next()
        while candidate >= limit {
            candidate = next()
        }
        return Int(candidate % bound)
    }

    /// Uniform integer in a closed range.
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + nextInt(upperBound: range.count)
    }

    /// Uniform double in `0..<1`.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Returns true with the given probability.
    public mutating func chance(_ probability: Double) -> Bool {
        guard probability > 0 else { return false }
        guard probability < 1 else { return true }
        return nextUnit() < probability
    }

    /// Derives an independent child generator. Used to keep sub-systems (AI
    /// deliberation, cosmetic wobble, boss selection) from consuming the deal's
    /// random stream and thereby changing the deal.
    public func branch(_ salt: UInt64) -> SeededGenerator {
        var mixer = SeededGenerator(seed: state ^ (salt &* 0xD1B54A32D192ED03))
        _ = mixer.next()
        return mixer
    }
}

public extension Array {
    /// Fisher-Yates shuffle driven by a seeded generator. Deterministic for a
    /// given seed and starting order.
    mutating func deterministicShuffle(using generator: inout SeededGenerator) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = generator.nextInt(upperBound: i + 1)
            if i != j { swapAt(i, j) }
        }
    }

    func deterministicShuffled(using generator: inout SeededGenerator) -> [Element] {
        var copy = self
        copy.deterministicShuffle(using: &generator)
        return copy
    }

    /// Uniformly picks one element, or nil when empty.
    func randomElement(using generator: inout SeededGenerator) -> Element? {
        guard !isEmpty else { return nil }
        return self[generator.nextInt(upperBound: count)]
    }
}
