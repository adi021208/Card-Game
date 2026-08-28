import Foundation
import DeckCore
import DeckGames

/// The Crazy Eights opponent.
///
/// Shedding games look simple and are not: the real decisions are which suit to
/// keep alive, when to spend a wild card, and when the player on your left is
/// close enough to going out that you should attack rather than tidy your hand.
public enum CrazyEightsAgent {

    public static func choose(observation: CrazyEightsRules.Observation,
                              legalActions: [CrazyEightsRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> CrazyEightsRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        let hand = observation.hand
        let handSize = hand.count
        // How many of each suit the agent holds; the suit it is longest in is
        // the one it wants to keep playable.
        var suitCounts: [Suit: Int] = [:]
        for card in hand {
            if let suit = card.suit { suitCounts[suit, default: 0] += 1 }
        }
        // What has already gone. A suit that is nearly exhausted is a bad one to
        // nominate, because nobody can follow it — including the agent.
        var suitPlayed: [Suit: Int] = [:]
        for card in observation.seenCards {
            if let suit = card.suit { suitPlayed[suit, default: 0] += 1 }
        }

        let threatened = observation.opponentCardCounts.values.min() ?? 99
        // Pressure rises sharply once somebody is one or two cards from out.
        let pressure = threatened <= 2 ? 1.0 : (threatened <= 4 ? 0.5 : 0.0)
        let wildsInHand = hand.filter { $0.rank == .eight || ($0.settingsAllowJoker(observation) && $0.isJoker) }.count

        var moves: [ScoredMove<CrazyEightsRules.Action>] = []
        for action in legalActions {
            switch action {
            case let .play(cardID):
                guard let card = hand.first(where: { $0.id == cardID }) else { continue }
                var score = 10.0
                // Shed the highest-value cards first: they are what a loss costs.
                score += Double(CardScoring.standardPoints(card)) * 0.22

                if let suit = card.suit {
                    // Keeping length in the suit on top means more of the hand
                    // stays playable next turn.
                    let remainingInSuit = (suitCounts[suit] ?? 1) - 1
                    score += Double(remainingInSuit) * 0.9
                    // Playing into an exhausted suit strands the agent.
                    score -= Double(suitPlayed[suit] ?? 0) * 0.12
                }
                // Matching by rank when the suit is short is how you switch suits
                // without spending an eight.
                if let top = observation.topCard, card.rank == top.rank, card.suit != observation.currentSuit {
                    let target = card.suit.flatMap { suitCounts[$0] } ?? 0
                    score += Double(target) * 0.8 + 1.2
                }
                if observation.settings.houseSpecials, let rank = card.rank {
                    // Attack when the next player is close to going out.
                    switch rank {
                    case .two: score += pressure * 6.0 * (0.5 + profile.aggression)
                    case .queen: score += pressure * 4.5 * (0.5 + profile.aggression)
                    case .ace: score += pressure * 1.5 * profile.aggression
                    default: break
                    }
                }
                moves.append(ScoredMove(action: action, score: score, reason: card.token))

            case let .playWild(cardID, suit):
                guard hand.contains(where: { $0.id == cardID }) else { continue }
                // A wild card is the way out of a suit you cannot follow. Spending
                // it while you still have ordinary cards throws that away.
                let ordinaryPlayable = hand.contains { card in
                    guard card.rank != .eight, !card.isJoker else { return false }
                    if card.suit == observation.currentSuit { return true }
                    if let top = observation.topCard, card.rank == top.rank { return true }
                    return false
                }
                var score = 6.0
                if ordinaryPlayable {
                    // Holding the eight back is usually right — unless the hand is
                    // nearly finished, or a cautious personality wants it gone.
                    score -= 7.0 * (1.0 - profile.riskTolerance)
                    if handSize <= 3 { score += 5.0 }
                }
                // Nominate the suit the agent is longest in and that is not spent.
                let held = Double(suitCounts[suit] ?? 0)
                score += held * 2.4
                score -= Double(suitPlayed[suit] ?? 0) * 0.18
                if held == 0 { score -= 6.0 }
                // With several wilds, spending one is cheaper.
                score += Double(max(0, wildsInHand - 1)) * 1.2
                if handSize == 1 { score += 20.0 }
                moves.append(ScoredMove(action: action, score: score, reason: "wild->\(suit.token)"))

            case .draw:
                // Drawing is forced in the classic rules and a real choice in the
                // draw-one variant, where a cautious player takes the card.
                var score = 2.0
                score += (1.0 - profile.aggression) * 1.5
                if observation.stockCount < 4 { score -= 3.0 }
                moves.append(ScoredMove(action: action, score: score, reason: "draw"))

            case .pass:
                moves.append(ScoredMove(action: action, score: 0.5, reason: "pass"))
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}

private extension Card {
    /// Jokers are only wild when the variant says so.
    func settingsAllowJoker(_ observation: CrazyEightsRules.Observation) -> Bool {
        observation.settings.useJokers
    }
}
