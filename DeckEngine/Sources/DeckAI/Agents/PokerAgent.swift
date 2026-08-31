import Foundation
import DeckCore
import DeckGames

/// The Texas Hold'em opponent.
///
/// It plays from equity, not from a script: it estimates how often its hand
/// wins against the hands it *cannot see* by sampling them from the cards it
/// knows are unaccounted for, then compares that number to the price it is being
/// offered. Personality changes how it acts on the estimate — never the estimate
/// itself, and never what it is allowed to look at.
public enum PokerAgent {

    public static func choose(observation: TexasHoldemRules.Observation,
                              legalActions: [TexasHoldemRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> TexasHoldemRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        let equity = handEquity(observation: observation, profile: profile, generator: &generator)
        let potAfterCall = Double(observation.pot + observation.toCall)
        let priceToCall = potAfterCall > 0 ? Double(observation.toCall) / potAfterCall : 0
        // How much of the stack is already committed. A player deep in a pot is
        // getting a better price to continue and knows it.
        let commitment = observation.stack > 0
            ? Double(observation.totalCommitted[observation.seat] ?? 0)
                / Double((observation.totalCommitted[observation.seat] ?? 0) + observation.stack)
            : 1.0
        // More opponents means the same hand wins less often.
        let opponents = max(1, observation.activeOpponents)
        // Late position is worth playing wider.
        let positionBonus = positionalWeight(observation)

        // The bluff decision is taken once per action, not per candidate, so the
        // agent's story stays consistent within a single decision.
        let bluffing = observation.toCall <= 0 || equity < 0.35
            ? generator.chance(profile.bluffFrequency * positionBonus)
            : false

        var moves: [ScoredMove<TexasHoldemRules.Action>] = []
        for action in legalActions {
            switch action {
            case .fold:
                // Folding is worth zero: any positive-value line beats it.
                // A stubborn personality dislikes folding slightly.
                let reluctance = profile.riskTolerance * 0.06
                moves.append(ScoredMove(action: action, score: -reluctance, reason: "fold"))

            case .check:
                // Free card. Slow-playing a monster is worth something to an
                // adaptive opponent; a straightforward one just bets it.
                let trap = equity > 0.8 ? profile.adaptability * 0.05 : 0
                moves.append(ScoredMove(action: action, score: 0.02 + trap, reason: "check"))

            case .call:
                let edge = equity - priceToCall
                var score = edge * 1.6
                score += commitment * 0.10
                // Calling with a drawing hand is better with more money behind.
                if equity > 0.4 && equity < 0.6 { score += profile.riskTolerance * 0.05 }
                moves.append(ScoredMove(action: action, score: score, reason: "call"))

            case let .raise(to):
                let extra = Double(to - (observation.committed[observation.seat] ?? 0))
                let potOdds = Double(observation.pot) + extra
                let riskShare = potOdds > 0 ? extra / potOdds : 1
                var score = (equity - 0.5) * 2.2 * (0.6 + profile.aggression)
                // Sizing: a big bet needs a big hand unless the agent is bluffing.
                score -= riskShare * (1.0 - profile.aggression) * 0.8
                score += positionBonus * profile.aggression * 0.12
                if bluffing {
                    // A bluff wants a size that looks like value.
                    score += profile.bluffFrequency * 1.2 - riskShare * 0.3
                }
                // Value-betting into several opponents needs a stronger hand.
                score -= Double(opponents - 1) * 0.06 * (1.0 - equity)
                moves.append(ScoredMove(action: action, score: score, reason: "raise \(to)"))

            case .allIn:
                let stackShare = Double(observation.stack) / Double(max(1, observation.pot + observation.stack))
                var score = (equity - 0.62) * 3.0
                score += profile.riskTolerance * 0.25 - stackShare * 0.5
                if observation.stack <= observation.bigBlind * 8 {
                    // Short stacked: shoving is the whole strategy.
                    score += (equity - 0.42) * 2.0 + profile.aggression * 0.2
                }
                if bluffing && observation.stack < observation.pot {
                    score += profile.bluffFrequency * 0.8
                }
                moves.append(ScoredMove(action: action, score: score, reason: "all in"))
            }
        }

        // An unpredictable personality samples rather than always taking the top
        // line, which is what makes it hard to put on a hand.
        let temperature = profile.bluffFrequency * 0.5 + (1 - profile.memoryStrength) * 0.2
        if temperature > 0.15 {
            if let sampled = AISelector.sample(moves, temperature: temperature, generator: &generator) {
                return generator.chance(profile.mistakeRate)
                    ? AISelector.choose(moves, profile: profile, generator: &generator)
                    : sampled
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    /// Being last to act is worth real money, so the agent widens in position.
    private static func positionalWeight(_ observation: TexasHoldemRules.Observation) -> Double {
        let seats = max(1, observation.seatOrder.count)
        // 0 is the button (best); seats-1 is the small blind.
        let fromButton = Double(observation.positionFromButton)
        return 1.0 - AIMath.normalise(fromButton, in: 0...Double(seats))
    }

    /// Monte-Carlo equity against the hands the agent cannot see.
    ///
    /// The unseen deck is built from the fifty-two cards *minus* the agent's own
    /// hole cards and the community — that is, from public information plus its
    /// own hand. Opponents' actual cards are never consulted, because the
    /// observation does not contain them.
    public static func handEquity(observation: TexasHoldemRules.Observation,
                                  profile: AIProfile,
                                  generator: inout SeededGenerator) -> Double {
        let hole = observation.hole
        guard hole.count == 2 else { return 0.5 }
        let community = observation.community
        let opponents = max(1, observation.activeOpponents)

        var known = Set(hole.map(\.id))
        for card in community { known.insert(card.id) }
        let unseen = DeckConfiguration.standard52.build().filter { !known.contains($0.id) }
        let needed = 5 - community.count
        guard unseen.count >= needed + opponents * 2 else { return 0.5 }

        let trials = max(24, profile.samplingBudget)
        var equity = 0.0

        for _ in 0..<trials {
            var pool = unseen
            // Partial Fisher-Yates: only shuffle the cards we are about to take.
            let draws = needed + opponents * 2
            for index in 0..<draws {
                let pick = index + generator.nextInt(upperBound: pool.count - index)
                pool.swapAt(index, pick)
            }
            var cursor = 0
            var board = community
            for _ in 0..<needed {
                board.append(pool[cursor]); cursor += 1
            }
            let mine = PokerEvaluator.best(from: hole + board)
            var better = 0
            var equal = 0
            for _ in 0..<opponents {
                let theirs = PokerEvaluator.best(from: [pool[cursor], pool[cursor + 1]] + board)
                cursor += 2
                if theirs > mine { better += 1; break }
                if theirs == mine { equal += 1 }
            }
            if better == 0 {
                equity += equal == 0 ? 1.0 : 1.0 / Double(equal + 1)
            }
        }
        return equity / Double(trials)
    }

    /// The agent's own read of its hand, for the debug menu and for tests.
    public static func describe(observation: TexasHoldemRules.Observation) -> String {
        guard observation.hole.count == 2 else { return "no cards" }
        if observation.community.isEmpty {
            return observation.hole.map(\.token).joined(separator: " ")
        }
        return PokerEvaluator.best(from: observation.hole + observation.community).category.englishName
    }
}
