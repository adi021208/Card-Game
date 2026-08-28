import Foundation
import DeckCore
import DeckGames

/// The Gin Rummy opponent.
///
/// It uses the same meld solver the player's own deadwood readout uses, so its
/// arithmetic is exactly as good as the interface's — the difference between a
/// beginner and an expert here is judgement about *when* to knock, and how much
/// it lets the discard pile tell the other player.
public enum GinRummyAgent {

    public static func choose(observation: GinRummyRules.Observation,
                              legalActions: [GinRummyRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> GinRummyRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        let hand = observation.hand
        let current = MeldSolver.best(hand)

        var moves: [ScoredMove<GinRummyRules.Action>] = []
        for action in legalActions {
            switch action {
            case .takeDiscard:
                guard let top = observation.discardTop else { continue }
                let improved = MeldSolver.best(hand + [top])
                // Taking is worth the drop in deadwood, minus the information it
                // gives away — a careful player weights that more heavily.
                let gain = Double(current.deadwoodPoints - improved.deadwoodPoints)
                let tell = 3.0 * (1.0 - profile.aggression)
                moves.append(ScoredMove(action: action, score: gain - tell, reason: "take"))

            case .drawFromStock:
                // The blind draw's value is the average improvement it might
                // bring, which is roughly proportional to how much deadwood is
                // still floating around.
                moves.append(ScoredMove(action: action,
                                        score: 2.0 + Double(current.deadwoodPoints) * 0.05,
                                        reason: "draw"))

            case .passUpcard:
                guard let top = observation.discardTop else { continue }
                let improved = MeldSolver.best(hand + [top])
                let gain = Double(current.deadwoodPoints - improved.deadwoodPoints)
                moves.append(ScoredMove(action: action, score: 3.0 - gain, reason: "pass"))

            case let .discard(cardID):
                guard let card = hand.first(where: { $0.id == cardID }) else { continue }
                var remaining = hand
                remaining.removeAll { $0.id == cardID }
                let after = MeldSolver.best(remaining)
                var score = Double(60 - after.deadwoodPoints)
                // Prefer throwing what is nowhere near a meld.
                score += Double(CardScoring.deadwoodPoints(card)) * 0.35
                // Do not feed the opponent: a card adjacent to what they took
                // from the discard pile is dangerous.
                if isDangerous(card, observation: observation) {
                    score -= 8.0 * profile.memoryStrength
                }
                moves.append(ScoredMove(action: action, score: score, reason: "discard \(card.token)"))

            case let .knock(cardID):
                guard let card = hand.first(where: { $0.id == cardID }) else { continue }
                var remaining = hand
                remaining.removeAll { $0.id == cardID }
                let after = MeldSolver.best(remaining)
                // Gin is always right. Otherwise the knock is a bet: a small
                // knock wins a little and risks an undercut.
                var score: Double
                if after.deadwoodPoints == 0 {
                    score = 200.0
                } else {
                    score = 40.0 - Double(after.deadwoodPoints) * 2.4
                    // Late in the deal there is no time left to improve.
                    if observation.stockCount < 12 { score += 14.0 }
                    // A patient personality holds out for gin.
                    score -= (1.0 - profile.riskTolerance) * Double(after.deadwoodPoints) * 0.8
                    score += profile.aggression * 6.0
                }
                moves.append(ScoredMove(action: action, score: score, reason: "knock"))
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    /// A card is dangerous when the opponent has shown interest in its
    /// neighbourhood — same rank, or one either side in the same suit.
    static func isDangerous(_ card: Card, observation: GinRummyRules.Observation) -> Bool {
        for taken in observation.opponentTookFromDiscard {
            if taken.rank == card.rank { return true }
            if taken.suit == card.suit,
               let a = taken.rank?.aceLowValue, let b = card.rank?.aceLowValue,
               abs(a - b) <= 2 {
                return true
            }
        }
        return false
    }
}

/// The Rummy opponent.
///
/// Melding banks points and hands the table information at the same time, so the
/// agent's personality shows in how long it sits on a completed set.
public enum RummyAgent {

    public static func choose(observation: RummyRules.Observation,
                              legalActions: [RummyRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> RummyRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        let hand = observation.hand
        let current = MeldSolver.best(hand)
        let closeToOut = hand.count <= 4

        var moves: [ScoredMove<RummyRules.Action>] = []
        for action in legalActions {
            switch action {
            case .drawFromStock:
                moves.append(ScoredMove(action: action, score: 2.0, reason: "draw"))

            case .takeDiscard:
                guard let top = observation.discardTop else { continue }
                let improved = MeldSolver.best(hand + [top])
                let gain = Double(current.deadwoodPoints - improved.deadwoodPoints)
                let completesMeld = improved.melds.count > current.melds.count
                var score = gain * 0.5
                if completesMeld { score += 6.0 }
                score -= 2.0 * (1.0 - profile.aggression)
                moves.append(ScoredMove(action: action, score: score, reason: "take"))

            case let .meld(ids):
                // Laying down banks the cards but shows the table what you hold
                // and gives everybody somewhere to lay off.
                var score = Double(ids.count) * 3.0
                if closeToOut { score += 12.0 }
                score -= (1.0 - profile.aggression) * 4.0
                if observation.stockCount < 10 { score += 6.0 }
                moves.append(ScoredMove(action: action, score: score, reason: "meld"))

            case .layOff:
                // Almost always right: it costs nothing and sheds a card.
                moves.append(ScoredMove(action: action, score: 9.0, reason: "lay off"))

            case let .discard(cardID):
                guard let card = hand.first(where: { $0.id == cardID }) else { continue }
                var remaining = hand
                remaining.removeAll { $0.id == cardID }
                let after = MeldSolver.best(remaining)
                var score = Double(60 - after.deadwoodPoints) * 0.4
                score += Double(CardScoring.deadwoodPoints(card)) * 0.3
                // Avoid handing an opponent a card that extends a meld on the table.
                for meld in observation.tableMelds where MeldSolver.canLayOff(card, on: meld) {
                    score -= 7.0 * profile.memoryStrength
                }
                moves.append(ScoredMove(action: action, score: score, reason: "discard \(card.token)"))
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}
