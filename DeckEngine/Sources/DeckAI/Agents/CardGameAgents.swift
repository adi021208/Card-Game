import Foundation
import DeckCore
import DeckGames

/// The Go Fish opponent.
///
/// Everything at a Go Fish table is public except the cards themselves, so the
/// agent plays the *questions*: it remembers what everybody has asked for, and
/// asks the player most likely to be holding what it needs.
public enum GoFishAgent {

    public static func choose(observation: GoFishRules.Observation,
                              legalActions: [GoFishRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> GoFishRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        var counts: [Rank: Int] = [:]
        for card in observation.hand {
            guard let rank = card.rank else { continue }
            counts[rank, default: 0] += 1
        }

        // What the history says each player is holding, weighted by memory.
        var belief: [SeatID: [Rank: Double]] = [:]
        for record in observation.askHistory {
            guard profile.memoryStrength >= 1.0 || generator.chance(profile.memoryStrength) else { continue }
            // Asking for a rank proves you hold at least one of it.
            belief[record.asker, default: [:]][record.rank, default: 0] += 1.0
            if record.succeeded {
                // The target gave theirs away, so they have none left.
                belief[record.target, default: [:]][record.rank] = -2.0
                // ...and the asker now holds more.
                belief[record.asker, default: [:]][record.rank, default: 0] += 1.0
            } else {
                // Denied: they had none at the time.
                belief[record.target, default: [:]][record.rank, default: 0] -= 1.5
            }
        }

        var moves: [ScoredMove<GoFishRules.Action>] = []
        for action in legalActions {
            guard case let .ask(target, rank) = action else { continue }
            var score = 0.0
            // Closer to a book is better.
            let held = counts[rank] ?? 0
            score += Double(held) * 2.0
            if held == 3 { score += 6.0 }
            // Belief that the target holds it.
            score += (belief[target]?[rank] ?? 0) * 3.5
            // A player with more cards is more likely to hold any given rank.
            let targetCards = observation.opponentCardCounts[target] ?? 1
            score += Double(targetCards) * 0.12
            // Asking reveals what you hold, so a cautious agent asks for what it
            // already holds three of — where the information costs least.
            score -= (1.0 - profile.aggression) * Double(4 - held) * 0.6
            moves.append(ScoredMove(action: action, score: score, reason: "\(rank.token)@\(target.rawValue)"))
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}

/// The Cheat opponent.
///
/// It lies when it has to and sometimes when it does not, and it calls on the
/// arithmetic: if it holds three of the claimed rank and somebody says they put
/// down two, one of those is a lie and it does not need to guess.
public enum CheatAgent {

    public static func choose(observation: CheatRules.Observation,
                              legalActions: [CheatRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> CheatRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        switch observation.phase {
        case .challenging:
            return chooseChallenge(observation: observation, legalActions: legalActions,
                                   profile: profile, generator: &generator)
        case .laying:
            return chooseLay(observation: observation, legalActions: legalActions,
                             profile: profile, generator: &generator)
        }
    }

    private static func chooseChallenge(observation: CheatRules.Observation,
                                        legalActions: [CheatRules.Action],
                                        profile: AIProfile,
                                        generator: inout SeededGenerator) -> CheatRules.Action? {
        guard let claimed = observation.claimedRank else { return .believe }
        let held = observation.ownRankCounts[claimed] ?? 0
        let claimedCount = observation.claimedCount

        // Four of each rank exist. If what is claimed plus what the agent holds
        // is more than four, the claim is certainly false.
        let certainLie = held + claimedCount > 4
        // Otherwise, the more the agent holds and the more they claimed, the
        // likelier the lie.
        var suspicion = Double(held) * 0.22 + Double(claimedCount - 1) * 0.15
        // Somebody down to their last cards has every reason to lie.
        if let layer = observation.lastLayer, (observation.opponentCardCounts[layer] ?? 9) <= 2 {
            suspicion += 0.3
        }
        // A big pile makes a wrong call expensive, so the agent needs more
        // certainty before it calls.
        let cost = Double(observation.pileCount) / 20.0
        suspicion -= cost * (1.0 - profile.riskTolerance) * 0.5
        suspicion += (profile.aggression - 0.5) * 0.2

        var moves: [ScoredMove<CheatRules.Action>] = []
        for action in legalActions {
            switch action {
            case .challenge:
                moves.append(ScoredMove(action: action,
                                        score: certainLie ? 100.0 : suspicion * 10.0,
                                        reason: "call"))
            case .believe:
                moves.append(ScoredMove(action: action,
                                        score: certainLie ? -100.0 : (1.0 - suspicion) * 5.0,
                                        reason: "believe"))
            default:
                continue
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }

    private static func chooseLay(observation: CheatRules.Observation,
                                  legalActions: [CheatRules.Action],
                                  profile: AIProfile,
                                  generator: inout SeededGenerator) -> CheatRules.Action? {
        let required = observation.requiredRank
        let truthful = observation.ownRankCounts[required] ?? 0
        let handSize = observation.hand.count
        // Somebody about to go out changes the calculation entirely.
        let opponentClose = observation.opponentCardCounts.values.min() ?? 99

        var moves: [ScoredMove<CheatRules.Action>] = []
        for action in legalActions {
            guard case let .lay(cards, claiming) = action else { continue }
            let laidCards = cards.compactMap { id in observation.hand.first { $0.id == id } }
            let honest = laidCards.allSatisfy { $0.rank == claiming }
            let count = cards.count

            var score = Double(count) * 1.4       // shedding is the point
            if honest {
                score += 6.0
                // Dumping every card of the rank is efficient but predictable.
                if count == truthful { score += 1.5 }
            } else {
                // Lying risks the whole pile.
                let exposure = Double(observation.pileCount + count) * 0.08
                score += profile.bluffFrequency * 8.0 - exposure * (1.0 - profile.riskTolerance)
                // A big lie is more likely to be called.
                score -= Double(count - 1) * 1.6
                // Lying is worth more when the agent is nearly out.
                if handSize <= 3 { score += 5.0 }
                // ...and when someone else is about to go out anyway.
                if opponentClose <= 2 { score += 3.0 * profile.riskTolerance }
                // Padding with the highest cards you do not want is better than
                // spending cards you might need honestly later.
                let padded = laidCards.filter { $0.rank != claiming }
                let paddingQuality = padded.reduce(0.0) { $0 + Double($1.rank?.rawValue ?? 0) } / Double(max(1, padded.count))
                score += paddingQuality * 0.12
            }
            moves.append(ScoredMove(action: action, score: score, reason: honest ? "honest" : "bluff"))
        }
        // A little sampling keeps the agent from being readable.
        let temperature = 0.4 + profile.bluffFrequency
        if let sampled = AISelector.sample(moves, temperature: temperature, generator: &generator),
           !generator.chance(profile.mistakeRate) {
            return sampled
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}

/// The President opponent.
///
/// The interesting decision is not what to play but whether to play at all:
/// passing hands the lead to somebody else, and the lead is worth more than one
/// card off your hand.
public enum PresidentAgent {

    public static func choose(observation: PresidentRules.Observation,
                              legalActions: [PresidentRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> PresidentRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        var byRank: [Rank: Int] = [:]
        for card in observation.hand {
            guard let rank = card.rank else { continue }
            byRank[rank, default: 0] += 1
        }
        let handSize = observation.hand.count
        let opponentClose = observation.opponentCardCounts.values.min() ?? 99
        let urgent = opponentClose <= 3

        var moves: [ScoredMove<PresidentRules.Action>] = []
        for action in legalActions {
            switch action {
            case let .play(ids):
                let cards = ids.compactMap { id in observation.hand.first { $0.id == id } }
                guard let rank = cards.first?.rank else { continue }
                let power = Double(PresidentRules.power(rank, twosAreBombs: observation.settings.twosAreBombs))
                var score = Double(ids.count) * 2.2
                // Spending high cards early wastes them.
                score -= power * 0.45
                // Breaking up a set to make a smaller play is expensive.
                let held = byRank[rank] ?? ids.count
                if ids.count < held { score -= Double(held - ids.count) * 1.8 }
                // Near the end, get rid of everything.
                if handSize <= 4 { score += power * 0.5 + 4.0 }
                if urgent { score += 3.0 * profile.aggression }
                // A bomb is precious; spend it to stop somebody going out.
                if power >= 100 { score -= urgent ? 2.0 : 14.0 * (1.0 - profile.aggression) }
                moves.append(ScoredMove(action: action, score: score, reason: "play \(rank.token)x\(ids.count)"))

            case .pass:
                // Passing keeps high cards for a lead you can control.
                var score = 3.0 + (1.0 - profile.aggression) * 3.0
                if handSize <= 3 { score -= 6.0 }
                if urgent { score -= 4.0 }
                moves.append(ScoredMove(action: action, score: score, reason: "pass"))
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}

/// The Speed opponent.
///
/// It has no hidden information to exploit and no turns to think in, so the only
/// thing that varies is how fast and how well it picks — `reactionSpeed` paces
/// it, and lookahead decides whether it takes the card that opens a follow-up.
public enum SpeedAgent {

    public static func choose(observation: SpeedRules.Observation,
                              legalActions: [SpeedRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> SpeedRules.Action? {
        guard !legalActions.isEmpty else { return nil }
        guard legalActions.count > 1 else { return legalActions[0] }

        var moves: [ScoredMove<SpeedRules.Action>] = []
        for action in legalActions {
            switch action {
            case let .play(_, cardID, pile):
                guard let card = observation.hand.first(where: { $0.id == cardID }) else { continue }
                var score = 1.0
                if profile.planningDepth > 0 {
                    // How many other cards in hand would become playable on this
                    // pile once this card is on top.
                    let followUps = observation.hand.filter {
                        $0.id != cardID && SpeedRules.isPlayable($0, on: card)
                    }.count
                    score += Double(followUps) * 2.0
                    // Keeping both piles reachable is worth something.
                    if let otherTop = observation.centreTops[1 - pile] {
                        let reach = observation.hand.filter {
                            $0.id != cardID && SpeedRules.isPlayable($0, on: otherTop)
                        }.count
                        score += Double(reach) * 0.4
                    }
                }
                moves.append(ScoredMove(action: action, score: score, reason: card.token))
            case .breakDeadlock:
                moves.append(ScoredMove(action: action, score: 0.5, reason: "flip"))
            }
        }
        return AISelector.choose(moves, profile: profile, generator: &generator)
    }
}

/// The War opponent. There are no decisions in War; the agent exists so the
/// registry has one for every game and the flip is paced like a person doing it.
public enum WarAgent {
    public static func choose(observation: WarRules.Observation,
                              legalActions: [WarRules.Action],
                              profile: AIProfile,
                              generator: inout SeededGenerator) -> WarRules.Action? {
        legalActions.first
    }
}
