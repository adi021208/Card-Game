import Foundation
import DeckCore

/// Everything the app counts, for one game or across all of them.
public struct StatisticsRecord: Codable, Sendable, Hashable {
    public var gamesPlayed: Int
    public var gamesWon: Int
    public var gamesLost: Int
    public var gamesDrawn: Int
    public var gamesAbandoned: Int
    public var totalSeconds: Int
    public var fastestWinSeconds: Int?
    public var longestGameSeconds: Int
    public var passAndPlayGames: Int
    public var soloGames: Int
    public var winsByDifficulty: [Int: Int]
    /// Game-declared metrics, already folded by their declared aggregation.
    public var metrics: [String: Int]
    /// How many games reported each metric, so averages are real averages.
    public var metricCounts: [String: Int]
    public var lastPlayed: Date?

    public init(gamesPlayed: Int = 0,
                gamesWon: Int = 0,
                gamesLost: Int = 0,
                gamesDrawn: Int = 0,
                gamesAbandoned: Int = 0,
                totalSeconds: Int = 0,
                fastestWinSeconds: Int? = nil,
                longestGameSeconds: Int = 0,
                passAndPlayGames: Int = 0,
                soloGames: Int = 0,
                winsByDifficulty: [Int: Int] = [:],
                metrics: [String: Int] = [:],
                metricCounts: [String: Int] = [:],
                lastPlayed: Date? = nil) {
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.gamesLost = gamesLost
        self.gamesDrawn = gamesDrawn
        self.gamesAbandoned = gamesAbandoned
        self.totalSeconds = totalSeconds
        self.fastestWinSeconds = fastestWinSeconds
        self.longestGameSeconds = longestGameSeconds
        self.passAndPlayGames = passAndPlayGames
        self.soloGames = soloGames
        self.winsByDifficulty = winsByDifficulty
        self.metrics = metrics
        self.metricCounts = metricCounts
        self.lastPlayed = lastPlayed
    }

    /// Win rate in hundredths of a percent, so it can live in an `Int`.
    public var winRateBasisPoints: Int {
        let decided = gamesWon + gamesLost + gamesDrawn
        guard decided > 0 else { return 0 }
        return gamesWon * 10000 / decided
    }

    public var averageSeconds: Int {
        gamesPlayed > 0 ? totalSeconds / gamesPlayed : 0
    }

    /// The value to show for a declared statistic.
    public func value(for definition: StatisticDefinition) -> Int {
        let raw = metrics[definition.key] ?? 0
        switch definition.aggregation {
        case .average:
            let count = metricCounts[definition.key] ?? 0
            return count > 0 ? raw / count : 0
        default:
            return raw
        }
    }

    public func hasValue(for definition: StatisticDefinition) -> Bool {
        (metricCounts[definition.key] ?? 0) > 0
    }
}

/// The persisted statistics for the whole app.
public struct StatisticsState: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.statistics"

    public var global: StatisticsRecord
    public var perGame: [GameID: StatisticsRecord]
    /// Games won at least once, for the "played the whole library" achievements.
    public var gamesWonAtLeastOnce: Set<GameID>

    public init(global: StatisticsRecord = StatisticsRecord(),
                perGame: [GameID: StatisticsRecord] = [:],
                gamesWonAtLeastOnce: Set<GameID> = []) {
        self.global = global
        self.perGame = perGame
        self.gamesWonAtLeastOnce = gamesWonAtLeastOnce
    }

    public func validate() -> String? {
        if global.gamesPlayed < 0 { return "negative games played" }
        if global.gamesWon > global.gamesPlayed { return "more wins than games" }
        return nil
    }

    public func record(for gameID: GameID) -> StatisticsRecord {
        perGame[gameID] ?? StatisticsRecord()
    }

    public var favouriteGame: GameID? {
        perGame.max { lhs, rhs in
            if lhs.value.gamesPlayed != rhs.value.gamesPlayed {
                return lhs.value.gamesPlayed < rhs.value.gamesPlayed
            }
            return lhs.value.totalSeconds < rhs.value.totalSeconds
        }?.key
    }
}

/// Folds finished games into the statistics.
///
/// It has no idea what "queens captured" means: each game declares how its
/// metrics should be aggregated, and this applies that declaration. Adding a
/// game never means editing this file.
public struct StatisticsEngine: Sendable {
    private let definitionsByKey: [String: StatisticDefinition]

    public init(registry: GameRegistry) {
        var index = registry.statisticsIndex
        // The engine's own metrics behave the same way as a game's.
        index[GlobalMetrics.durationSeconds] = StatisticDefinition(key: GlobalMetrics.durationSeconds,
                                                                   titleKey: "stat.duration",
                                                                   aggregation: .minimum,
                                                                   format: .duration)
        index[GlobalMetrics.undoCount] = StatisticDefinition(key: GlobalMetrics.undoCount,
                                                             titleKey: "stat.undos",
                                                             aggregation: .total)
        index[GlobalMetrics.hintsUsed] = StatisticDefinition(key: GlobalMetrics.hintsUsed,
                                                             titleKey: "stat.hints",
                                                             aggregation: .total)
        index[GlobalMetrics.turns] = StatisticDefinition(key: GlobalMetrics.turns,
                                                         titleKey: "stat.turns",
                                                         aggregation: .total)
        self.definitionsByKey = index
    }

    /// Records a completed game.
    public func record(result: GameResult,
                       gameID: GameID,
                       seat: SeatID,
                       configuration: GameConfiguration,
                       into state: inout StatisticsState) {
        let outcome = result.outcome(for: seat)
        apply(result: result, outcome: outcome, seat: seat,
              configuration: configuration, into: &state.global)
        var perGame = state.perGame[gameID] ?? StatisticsRecord()
        apply(result: result, outcome: outcome, seat: seat,
              configuration: configuration, into: &perGame)
        state.perGame[gameID] = perGame
        if outcome == .win {
            state.gamesWonAtLeastOnce.insert(gameID)
        }
    }

    private func apply(result: GameResult,
                       outcome: GameResult.Outcome,
                       seat: SeatID,
                       configuration: GameConfiguration,
                       into record: inout StatisticsRecord) {
        record.gamesPlayed += 1
        switch outcome {
        case .win: record.gamesWon += 1
        case .loss: record.gamesLost += 1
        case .draw: record.gamesDrawn += 1
        case .abandoned: record.gamesAbandoned += 1
        }
        let seconds = Int(result.duration.rounded())
        record.totalSeconds += seconds
        record.longestGameSeconds = max(record.longestGameSeconds, seconds)
        if outcome == .win, seconds > 0 {
            record.fastestWinSeconds = min(record.fastestWinSeconds ?? Int.max, seconds)
        }
        if configuration.isPassAndPlay { record.passAndPlayGames += 1 }
        if configuration.isSolo { record.soloGames += 1 }
        if outcome == .win {
            // The hardest opponent at the table is the one the win is worth.
            let hardest = configuration.seating.seats.compactMap { seat -> Int? in
                if case let .ai(_, difficulty) = seat.controller { return difficulty.rawValue }
                return nil
            }.max()
            if let hardest {
                record.winsByDifficulty[hardest, default: 0] += 1
            }
        }
        record.lastPlayed = Date()

        for (key, value) in result.metrics {
            record.metricCounts[key, default: 0] += 1
            let aggregation = definitionsByKey[key]?.aggregation ?? .total
            switch aggregation {
            case .total, .average:
                record.metrics[key, default: 0] += value
            case .maximum:
                record.metrics[key] = max(record.metrics[key] ?? Int.min, value)
            case .minimum:
                record.metrics[key] = min(record.metrics[key] ?? Int.max, value)
            case .occurrences:
                if value != 0 { record.metrics[key, default: 0] += 1 }
            }
        }
    }
}
