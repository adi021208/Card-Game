import Foundation
import DeckCore

/// A candidate move with the agent's evaluation of it.
public struct ScoredMove<Action> {
    public var action: Action
    /// Higher is better. Agents use whatever scale suits the game; only the
    /// ordering matters.
    public var score: Double
    /// Optional trace for the debug menu and for the "why did it do that" tools.
    public var reason: String

    public init(action: Action, score: Double, reason: String = "") {
        self.action = action
        self.score = score
        self.reason = reason
    }
}

/// Turns a scored list into a decision, applying the personality.
///
/// This is where difficulty actually lives. Every agent scores moves as well as
/// it can, and then this layer decides how faithfully that evaluation is
/// followed — a beginner picks a clearly worse move often, an expert almost
/// never. Difficulty never touches what the agent was allowed to see.
public enum AISelector {

    public static func choose<Action>(_ moves: [ScoredMove<Action>],
                                      profile: AIProfile,
                                      generator: inout SeededGenerator) -> Action? {
        guard !moves.isEmpty else { return nil }
        guard moves.count > 1 else { return moves[0].action }

        let sorted = moves.sorted { $0.score > $1.score }

        // A mistake is picking a move the agent itself rated worse. Weak players
        // do it often; they are not picking at random, they are picking badly.
        if generator.chance(profile.mistakeRate) {
            // Bias towards the middle of the list rather than the very worst
            // move, which is what a distracted human actually does.
            let ceiling = max(1, min(sorted.count - 1, Int(Double(sorted.count) * 0.7)))
            let index = 1 + generator.nextInt(upperBound: ceiling)
            return sorted[min(index, sorted.count - 1)].action
        }

        // Ties are broken with a personality-stable jitter so two opponents in
        // the same seat do not always make the identical choice.
        let best = sorted[0].score
        let jitter = (1.0 - profile.memoryStrength) * 0.05
        let threshold = best - abs(best) * jitter - jitter
        let contenders = sorted.filter { $0.score >= threshold }
        if contenders.count > 1 {
            return contenders[generator.nextInt(upperBound: contenders.count)].action
        }
        return sorted[0].action
    }

    /// Softmax sampling, for agents where committing to the single best move
    /// makes the opponent readable. `temperature` rises with unpredictability.
    public static func sample<Action>(_ moves: [ScoredMove<Action>],
                                      temperature: Double,
                                      generator: inout SeededGenerator) -> Action? {
        guard !moves.isEmpty else { return nil }
        guard temperature > 0.001, moves.count > 1 else {
            return moves.max { $0.score < $1.score }?.action
        }
        let maximum = moves.map(\.score).max() ?? 0
        let weights = moves.map { exp(($0.score - maximum) / temperature) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return moves[0].action }
        var target = generator.nextUnit() * total
        for (index, weight) in weights.enumerated() {
            target -= weight
            if target <= 0 { return moves[index].action }
        }
        return moves[moves.count - 1].action
    }
}

/// Bookkeeping every card-game agent wants: what has been seen, and what that
/// implies about who holds what.
///
/// Everything here is derived from *public* information — cards played face up,
/// and the fact that a player failed to follow suit. `memoryStrength` decides
/// how much of it the agent actually retains, which is what makes a beginner
/// forget that spades are gone.
public struct CardMemory {
    public private(set) var seen: Set<CardID> = []
    /// Suits a seat is known to be out of, because they discarded on one.
    public private(set) var voids: [SeatID: Set<Suit>] = [:]
    /// Counts of each rank still unaccounted for.
    public private(set) var remainingByRank: [Rank: Int] = [:]
    public private(set) var remainingBySuit: [Suit: Int] = [:]
    private let retention: Double

    public init(configuration: DeckConfiguration = .standard52, memoryStrength: Double = 1.0) {
        self.retention = memoryStrength
        for card in configuration.build() {
            if let rank = card.rank { remainingByRank[rank, default: 0] += 1 }
            if let suit = card.suit { remainingBySuit[suit, default: 0] += 1 }
        }
    }

    /// Records a card everyone saw. Weak memories drop some of them.
    public mutating func note(_ card: Card, using generator: inout SeededGenerator) {
        guard !seen.contains(card.id) else { return }
        guard retention >= 1.0 || generator.chance(retention) else { return }
        seen.insert(card.id)
        if let rank = card.rank { remainingByRank[rank] = max(0, (remainingByRank[rank] ?? 0) - 1) }
        if let suit = card.suit { remainingBySuit[suit] = max(0, (remainingBySuit[suit] ?? 0) - 1) }
    }

    /// Records that a seat discarded off-suit, which proves they hold none.
    public mutating func noteVoid(_ seat: SeatID, suit: Suit, using generator: inout SeededGenerator) {
        guard retention >= 1.0 || generator.chance(retention) else { return }
        voids[seat, default: []].insert(suit)
    }

    public func isVoid(_ seat: SeatID, in suit: Suit) -> Bool {
        voids[seat]?.contains(suit) ?? false
    }

    public func remaining(_ suit: Suit) -> Int { remainingBySuit[suit] ?? 0 }
    public func remaining(_ rank: Rank) -> Int { remainingByRank[rank] ?? 0 }
    public func hasSeen(_ card: Card) -> Bool { seen.contains(card.id) }
}

/// Shared numeric helpers.
public enum AIMath {
    /// Blends two values by a weight in 0…1.
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * min(1, max(0, t))
    }

    /// Maps a value in `range` onto 0…1.
    public static func normalise(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }
}
