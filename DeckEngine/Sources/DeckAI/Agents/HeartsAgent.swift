import Foundation
import DeckCore
import DeckGames

/// The Hearts opponent.
///
/// Hearts is a game of avoidance with one enormous exception, so the agent does
/// three things: it counts what has gone, it works out whether it can still be
/// hurt in each suit, and it notices when taking *everything* has become the
/// better line. Personality decides how far it will chase that.
public enum HeartsAgent {

    public static func choose(observation: HeartsRules.Observation,
                              legalActions: [HeartsRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> HeartsRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        switch observation.phase {
        case .passing:
            return choosePass(observation: observation,
                              legalActions: legalActions,
                              profile: profile,
                              generator: &generator)
        case .playing:
            return choosePlay(observation: observation,
                              legalActions: legalActions,
                              profile: profile,
                              generator: &generator)
        case .scoring:
            return legalActions.first
        }
    }

    // MARK: - Passing

    private static func choosePass(observation: HeartsRules.Observation,
                                   legalActions: [HeartsRules.Action],
                                   profile: AIProfile,
                                   generator: inout SeededGenerator) -> HeartsRules.Action? {
        let hand = observation.hand
        var suitCounts: [Suit: Int] = [:]
        for card in hand {
            if let suit = card.suit { suitCounts[suit, default: 0] += 1 }
        }
        let spadeCount = suitCounts[.spades] ?? 0

        // Score every card by how much trouble it is likely to cause.
        func danger(_ card: Card) -> Double {
            guard let suit = card.suit, let rank = card.rank else { return 0 }
            var value = 0.0
            if suit == .spades {
                switch rank {
                case .queen: value += spadeCount <= 3 ? 40 : 14
                case .king, .ace: value += spadeCount <= 3 ? 30 : 10
                default: value += Double(rank.rawValue) * 0.2
                }
            } else if suit == .hearts {
                value += Double(rank.rawValue) * 1.4
            } else {
                value += Double(rank.rawValue) * 0.9
                // Emptying a short suit is worth a lot: it buys discards later.
                let length = suitCounts[suit] ?? 0
                if length <= 2 { value += 8.0 - Double(length) * 2.0 }
            }
            return value
        }

        // A hand strong enough to shoot the moon wants the opposite of all this.
        let shootScore = moonPotential(hand: hand, suitCounts: suitCounts)
        let willTryToShoot = shootScore > 0.72 && generator.chance(profile.riskTolerance * 0.7)

        var moves: [ScoredMove<HeartsRules.Action>] = []
        // Evaluating all 286 combinations is cheap and gives a genuinely better
        // pass than picking the three worst cards independently.
        for action in legalActions {
            guard case let .passCards(ids) = action else { continue }
            let cards = ids.compactMap { id in hand.first { $0.id == id } }
            guard cards.count == 3 else { continue }
            var score = cards.reduce(0.0) { $0 + danger($1) }

            // Passing the whole of a short suit is worth more than the sum of
            // the cards, because it creates a void.
            var passedBySuit: [Suit: Int] = [:]
            for card in cards {
                if let suit = card.suit { passedBySuit[suit, default: 0] += 1 }
            }
            for (suit, count) in passedBySuit where suit != .spades {
                if count == suitCounts[suit] { score += 12.0 }
            }
            if willTryToShoot {
                // Keep the high cards; pass the low ones that cannot win a trick.
                score = -score
                score += cards.reduce(0.0) { $0 + Double(14 - ($1.rank?.rawValue ?? 14)) }
            }
            moves.append(ScoredMove(action: action, score: score))
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    /// Rough estimate of whether the hand can take all twenty-six.
    static func moonPotential(hand: [Card], suitCounts: [Suit: Int]) -> Double {
        guard !hand.isEmpty else { return 0 }
        let highCards = hand.filter { ($0.rank?.rawValue ?? 0) >= Rank.queen.rawValue }.count
        let aces = hand.filter { $0.rank == .ace }.count
        let heartCount = suitCounts[.hearts] ?? 0
        let heartStrength = hand.filter { $0.suit == .hearts && ($0.rank?.rawValue ?? 0) >= 10 }.count
        let controlsSpades = hand.contains { $0.suit == .spades && $0.rank == .queen }
            && (suitCounts[.spades] ?? 0) >= 4
        var score = Double(highCards) / 8.0 * 0.4
        score += Double(aces) / 4.0 * 0.25
        score += Double(heartStrength) / 4.0 * 0.25
        if heartCount >= 5 { score += 0.1 }
        if controlsSpades { score += 0.1 }
        return min(1, score)
    }

    // MARK: - Playing

    private static func choosePlay(observation: HeartsRules.Observation,
                                   legalActions: [HeartsRules.Action],
                                   profile: AIProfile,
                                   generator: inout SeededGenerator) -> HeartsRules.Action? {
        let hand = observation.hand
        let legalIDs = Set(observation.legalCards.map(\.id))

        // Everything the agent knows is public: cards played to completed
        // tricks, and cards on the table right now.
        var playedBySuit: [Suit: Int] = [:]
        for entry in observation.playedCards {
            if let suit = entry.card.suit { playedBySuit[suit, default: 0] += 1 }
        }
        for entry in observation.trickPlays {
            if let suit = entry.card.suit { playedBySuit[suit, default: 0] += 1 }
        }
        // Which seats have shown themselves void, inferred from discards.
        var voids: [SeatID: Set<Suit>] = [:]
        var ledSuitOfTrick: Suit?
        var trickIndex = 0
        for entry in observation.playedCards {
            if trickIndex % observation.seatOrder.count == 0 {
                ledSuitOfTrick = entry.card.suit
            } else if let led = ledSuitOfTrick, entry.card.suit != led {
                voids[entry.seat, default: []].insert(led)
            }
            trickIndex += 1
        }
        // A weak memory forgets some of it.
        if profile.memoryStrength < 1.0 {
            for seat in voids.keys where !generator.chance(profile.memoryStrength) {
                voids[seat] = []
            }
        }

        let queenGone = observation.playedCards.contains { $0.card.suit == .spades && $0.card.rank == .queen }
            || observation.trickPlays.contains { $0.card.suit == .spades && $0.card.rank == .queen }
        let myPoints = observation.roundPoints[observation.seat] ?? 0
        let othersHavePoints = observation.roundPoints.contains { $0.key != observation.seat && $0.value > 0 }
        // Committed to shooting only while nobody else has taken a point.
        let shooting = !othersHavePoints && myPoints > 0
            && moonPotential(hand: hand, suitCounts: suitLengths(hand)) > 0.6
            && profile.riskTolerance > 0.45

        let pointsOnTable = observation.trickPlays.reduce(0) { total, entry in
            total + pointValue(entry.card)
        }
        let winningCard = currentWinner(observation)

        var moves: [ScoredMove<HeartsRules.Action>] = []
        for action in legalActions {
            guard case let .play(cardID) = action,
                  legalIDs.contains(cardID),
                  let card = hand.first(where: { $0.id == cardID }),
                  let rank = card.rank, let suit = card.suit else { continue }

            var score = 0.0
            let isLeading = observation.trickPlays.isEmpty

            if isLeading {
                // Leading low keeps the trick away. Leading a suit opponents are
                // void in hands them a free discard, which is usually bad.
                score += Double(15 - rank.rawValue) * 1.2
                let outstanding = 13 - (playedBySuit[suit] ?? 0) - countInHand(hand, suit: suit)
                if outstanding <= 0 {
                    // Nobody else holds the suit: this trick is certainly yours.
                    score -= 14.0
                }
                if suit == .spades {
                    if !queenGone && rank.rawValue > Rank.queen.rawValue {
                        // Leading the king or ace of spades draws the queen onto you.
                        score -= 26.0 * (1.0 - profile.riskTolerance)
                    } else if !queenGone && rank.rawValue < Rank.queen.rawValue {
                        // Flushing the queen out is a good, well-known play.
                        score += 8.0
                    }
                }
                if suit == .hearts && !observation.heartsBroken { score -= 5.0 }
                if shooting {
                    // Shooting means taking every trick: lead the highest thing.
                    score = Double(rank.rawValue) * 2.0
                    if suit == .spades && rank == .queen { score += 10 }
                }
            } else if let led = observation.ledSuit, suit == led {
                // Following suit. The question is whether to take the trick.
                let wouldWin = (winningCard.map { rank.rawValue > $0.rawValue } ?? true)
                let isLastToPlay = observation.trickPlays.count == observation.seatOrder.count - 1
                if shooting {
                    score += wouldWin ? Double(rank.rawValue) * 2.5 : -20
                } else if wouldWin {
                    // Taking a clean trick late in the hand is sometimes right;
                    // taking points never is.
                    score -= Double(pointsOnTable) * 4.0
                    score -= 6.0
                    if isLastToPlay && pointsOnTable == 0 { score += 3.0 }
                    if !queenGone && led == .spades && rank.rawValue > Rank.queen.rawValue {
                        score -= 30.0
                    }
                } else {
                    // Ducking. Get rid of the highest card that still loses.
                    score += Double(rank.rawValue) * 1.4 + 8.0
                }
            } else {
                // Void in the led suit: this is the moment to unload.
                if shooting {
                    score += Double(15 - rank.rawValue)
                } else {
                    if suit == .spades && rank == .queen { score += 60.0 }
                    else if suit == .spades && rank.rawValue > Rank.queen.rawValue && !queenGone { score += 34.0 }
                    else if suit == .hearts { score += 14.0 + Double(rank.rawValue) * 1.6 }
                    else { score += Double(rank.rawValue) * 1.1 }
                    // Keeping length in a suit you are void-adjacent to is worth
                    // little; dumping from your longest side suit is worth more.
                    score += Double(countInHand(hand, suit: suit)) * 0.4
                }
            }

            // A cautious personality weights avoiding points higher; an
            // aggressive one is happier to take a trick to keep control.
            score += (0.5 - profile.riskTolerance) * Double(pointValue(card)) * 1.5
            moves.append(ScoredMove(action: action, score: score, reason: card.token))
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    // MARK: - Helpers

    private static func suitLengths(_ hand: [Card]) -> [Suit: Int] {
        var counts: [Suit: Int] = [:]
        for card in hand {
            if let suit = card.suit { counts[suit, default: 0] += 1 }
        }
        return counts
    }

    private static func countInHand(_ hand: [Card], suit: Suit) -> Int {
        hand.reduce(0) { $0 + ($1.suit == suit ? 1 : 0) }
    }

    static func pointValue(_ card: Card) -> Int {
        if card.suit == .hearts { return 1 }
        if card.suit == .spades && card.rank == .queen { return 13 }
        return 0
    }

    /// The rank currently winning the trick, if the agent is following suit.
    private static func currentWinner(_ observation: HeartsRules.Observation) -> Rank? {
        guard let led = observation.ledSuit else { return nil }
        return observation.trickPlays
            .filter { $0.card.suit == led }
            .compactMap { $0.card.rank }
            .max()
    }
}
