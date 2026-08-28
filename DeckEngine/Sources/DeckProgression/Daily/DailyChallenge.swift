import Foundation
import DeckCore

/// What a daily challenge asks for.
public enum ChallengeObjective: Hashable, Codable, Sendable {
    /// Beat a score.
    case score(target: Int)
    /// Finish inside a time.
    case speed(seconds: Int)
    /// Finish in no more than this many turns.
    case efficiency(turns: Int)
    /// Reach a specific total.
    case target(value: Int, metricKey: String)
    /// Win from behind.
    case handicap(points: Int)
    /// Meet a game-specific condition, identified by a highlight code.
    case perfect(highlight: String)
    /// Beat the boss, whatever else happens.
    case boss(bossID: String)

    public var kindKey: String {
        switch self {
        case .score: return "challenge.kind.score"
        case .speed: return "challenge.kind.speed"
        case .efficiency: return "challenge.kind.efficiency"
        case .target: return "challenge.kind.target"
        case .handicap: return "challenge.kind.handicap"
        case .perfect: return "challenge.kind.perfect"
        case .boss: return "challenge.kind.boss"
        }
    }

    public var descriptionKey: String { kindKey + ".detail" }

    public var arguments: [String] {
        switch self {
        case let .score(target): return [String(target)]
        case let .speed(seconds): return [String(seconds / 60), String(seconds % 60)]
        case let .efficiency(turns): return [String(turns)]
        case let .target(value, _): return [String(value)]
        case let .handicap(points): return [String(points)]
        case let .perfect(highlight): return [highlight]
        case let .boss(bossID): return [bossID]
        }
    }

    public var englishDescription: String {
        switch self {
        case let .score(target): return "Score at least \(target)."
        case let .speed(seconds): return "Win in under \(seconds / 60)m \(seconds % 60)s."
        case let .efficiency(turns): return "Win in \(turns) turns or fewer."
        case let .target(value, key): return "Reach \(value) \(key)."
        case let .handicap(points): return "Win from \(points) behind."
        case .perfect: return "Pull off the special objective."
        case let .boss(bossID): return "Beat \(bossID)."
        }
    }
}

/// One day's challenge. Fully determined by its date, the ruleset version and
/// the challenge version — every player who opens it gets the identical deal,
/// boss, difficulty and objective.
public struct DailyChallenge: Hashable, Codable, Sendable, Identifiable {
    /// Bumped when the generation rules change, which intentionally re-rolls
    /// past challenges rather than silently invalidating stored results.
    public static let challengeVersion = 1

    public var date: ChallengeDate
    public var gameID: GameID
    public var variantID: String
    public var seed: UInt64
    /// −50% to +200%, expressed as a multiplier from 0.5 to 3.0.
    public var difficultyScale: Double
    public var objective: ChallengeObjective
    public var bossID: String?
    public var options: [String: Int]
    /// How many opponents, and how strong.
    public var opponentCount: Int
    public var opponentDifficulty: AIDifficulty

    public var id: String { "\(date.identifier)/\(gameID.rawValue)" }

    /// The percentage shown next to the difficulty, e.g. `+75%`.
    public var difficultyPercent: Int { Int(((difficultyScale - 1.0) * 100).rounded()) }

    public init(date: ChallengeDate,
                gameID: GameID,
                variantID: String,
                seed: UInt64,
                difficultyScale: Double,
                objective: ChallengeObjective,
                bossID: String?,
                options: [String: Int],
                opponentCount: Int,
                opponentDifficulty: AIDifficulty) {
        self.date = date
        self.gameID = gameID
        self.variantID = variantID
        self.seed = seed
        self.difficultyScale = difficultyScale
        self.objective = objective
        self.bossID = bossID
        self.options = options
        self.opponentCount = opponentCount
        self.opponentDifficulty = opponentDifficulty
    }
}

/// Generates the daily challenge.
///
/// Everything is derived from the seed, so two devices in different time zones
/// that resolve to the same calendar day produce byte-identical challenges, and
/// so does a replay of that day months later.
public struct DailyChallengeGenerator: Sendable {
    private let registry: GameRegistry

    public init(registry: GameRegistry) {
        self.registry = registry
    }

    public func challenge(for date: ChallengeDate) -> DailyChallenge? {
        let eligible = registry.dailyEligible
        guard !eligible.isEmpty else { return nil }

        // The game is chosen from a seed that depends only on the date, so the
        // game itself does not depend on the game — no circularity.
        let pickerSeed = SeedFactory.seed(components: [
            "deck.daily.pick.v1",
            date.identifier,
            "challenge\(DailyChallenge.challengeVersion)"
        ])
        var picker = SeededGenerator(seed: pickerSeed)
        let definition = eligible[picker.nextInt(upperBound: eligible.count)]

        let seed = SeedFactory.dailySeed(challengeDate: date,
                                         gameID: definition.id,
                                         rulesVersion: DailyChallenge.challengeVersion,
                                         challengeVersion: DailyChallenge.challengeVersion)
        var generator = SeededGenerator(seed: seed)

        // Difficulty runs −50% to +200%, weighted towards the middle so most
        // days are playable and the hard ones feel like an event.
        let roll = generator.nextUnit()
        let curved = roll * roll * roll          // long tail towards the top
        let difficultyScale = 0.5 + curved * 2.5

        // A boss appears on roughly half of days, and always on the hardest.
        let boss: Boss?
        if difficultyScale > 1.8 || generator.chance(0.5) {
            boss = BossCast.boss(forSeed: seed, gameID: definition.id)
        } else {
            boss = nil
        }

        let variant = definition.variants.isEmpty
            ? "standard"
            : definition.variants[generator.nextInt(upperBound: definition.variants.count)].id

        let objective = makeObjective(definition: definition,
                                      boss: boss,
                                      difficultyScale: difficultyScale,
                                      generator: &generator)

        var options = definition.resolvedOptions(variantID: variant, overrides: [:])
        if let boss {
            for modifier in boss.modifiers {
                if case let .ruleChange(option, value) = modifier { options[option] = value }
            }
        }

        let maxOpponents = max(0, definition.playerRange.upperBound - 1)
        let opponentCount = min(maxOpponents, max(definition.playerRange.lowerBound - 1, maxOpponents == 0 ? 0 : 3))
        let opponentDifficulty: AIDifficulty
        switch difficultyScale {
        case ..<0.85: opponentDifficulty = .beginner
        case ..<1.25: opponentDifficulty = .casual
        case ..<2.0: opponentDifficulty = .skilled
        default: opponentDifficulty = .expert
        }

        return DailyChallenge(date: date,
                              gameID: definition.id,
                              variantID: variant,
                              seed: seed,
                              difficultyScale: difficultyScale,
                              objective: objective,
                              bossID: boss?.id,
                              options: options,
                              opponentCount: opponentCount,
                              opponentDifficulty: opponentDifficulty)
    }

    /// Chooses an objective that suits the game and scales with the difficulty.
    private func makeObjective(definition: GameDefinition,
                               boss: Boss?,
                               difficultyScale: Double,
                               generator: inout SeededGenerator) -> ChallengeObjective {
        // Boss days are about the boss.
        if let boss, generator.chance(0.6) {
            return .boss(bossID: boss.id)
        }

        let tightening = 1.0 + Double(boss?.objectiveTightening ?? 0) / 100.0
        let scale = difficultyScale * tightening

        // Solitaires are scored on time and efficiency; everything else on
        // score, because that is what those games produce.
        if definition.categories.contains(.solitaire) {
            let choice = generator.nextInt(upperBound: 3)
            switch choice {
            case 0:
                let seconds = Int(600.0 / max(0.5, scale))
                return .speed(seconds: max(90, seconds))
            case 1:
                let moves = Int(220.0 / max(0.5, scale))
                return .efficiency(turns: max(60, moves))
            default:
                let target = Int(400.0 * scale)
                return .score(target: max(80, target))
            }
        }

        if definition.categories.contains(.speed) {
            let seconds = Int(180.0 / max(0.5, scale))
            return .speed(seconds: max(45, seconds))
        }

        let choice = generator.nextInt(upperBound: 4)
        switch choice {
        case 0:
            let handicapPoints = Int(20.0 * scale)
            return .handicap(points: max(5, handicapPoints))
        case 1:
            let turns = Int(160.0 / max(0.5, scale))
            return .efficiency(turns: max(30, turns))
        case 2 where !definition.achievements.isEmpty:
            // Reuse a game's own highlight as a "perfect" objective.
            let candidates = definition.achievements.compactMap { definition -> String? in
                if case let .highlight(code, _) = definition.tracking { return code }
                return nil
            }
            if let code = candidates.first {
                return .perfect(highlight: code)
            }
            return .score(target: Int(100.0 * scale))
        default:
            return .score(target: max(20, Int(100.0 * scale)))
        }
    }

    /// Builds the runnable configuration for a challenge.
    ///
    /// The same challenge always produces the same seating, the same seed and
    /// the same rules — which is what makes two players' attempts comparable.
    public func configuration(for challenge: DailyChallenge,
                              playerProfileID: String,
                              playerName: String,
                              avatarID: String) -> GameConfiguration? {
        guard let definition = registry[challenge.gameID] else { return nil }
        var seats: [Seat] = [
            Seat(id: SeatID(0), displayName: playerName,
                 controller: .human(profileID: playerProfileID),
                 team: definition.playerRange.upperBound == 4 ? 0 : nil,
                 avatarID: avatarID)
        ]
        // Opponent personalities are drawn from the same seed so the table is
        // the same for everybody.
        var generator = SeededGenerator(seed: challenge.seed ^ 0x5EA7_5EA7)
        let bossPersonality = challenge.bossID.flatMap { BossCast.boss($0)?.personalityID }
        for index in 0..<challenge.opponentCount {
            let personality: AIPersonalityID
            if index == 0, let bossPersonality {
                personality = bossPersonality
            } else {
                personality = AICast.all[generator.nextInt(upperBound: AICast.all.count)].id
            }
            let seatIndex = index + 1
            seats.append(Seat(id: SeatID(seatIndex),
                              displayName: AICast.personality(personality).displayName,
                              controller: .ai(personality: personality,
                                              difficulty: challenge.opponentDifficulty),
                              team: definition.playerRange.upperBound == 4 ? seatIndex % 2 : nil,
                              avatarID: "avatar.\(personality.rawValue)"))
        }

        var configuration = GameConfiguration(gameID: challenge.gameID,
                                              seating: SeatingPlan(seats: seats),
                                              variantID: challenge.variantID,
                                              options: challenge.options,
                                              seed: challenge.seed,
                                              difficultyScale: challenge.difficultyScale,
                                              bossID: challenge.bossID,
                                              challengeID: challenge.id)
        if let bossID = challenge.bossID, let boss = BossCast.boss(bossID) {
            configuration = boss.apply(to: configuration)
        }
        return configuration
    }
}
