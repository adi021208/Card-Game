import Foundation
import DeckCore

/// How far a player has got with one game.
///
/// Mastery is deliberately not "hours played": it is wins, achievements and
/// whether the hardest opponent has been beaten, so it rewards getting good at
/// a game rather than leaving it running.
public struct MasteryRecord: Codable, Sendable, Hashable {
    public var gameID: GameID
    public var wins: Int
    public var achievementsUnlocked: Int
    public var achievementsAvailable: Int
    public var beatExpert: Bool
    public var dailyChallengesWon: Int

    public init(gameID: GameID,
                wins: Int = 0,
                achievementsUnlocked: Int = 0,
                achievementsAvailable: Int = 0,
                beatExpert: Bool = false,
                dailyChallengesWon: Int = 0) {
        self.gameID = gameID
        self.wins = wins
        self.achievementsUnlocked = achievementsUnlocked
        self.achievementsAvailable = achievementsAvailable
        self.beatExpert = beatExpert
        self.dailyChallengesWon = dailyChallengesWon
    }

    /// Five bands, from never played to mastered.
    public var level: Int {
        var points = 0
        points += min(4, wins / 3)
        if achievementsAvailable > 0 {
            points += min(3, achievementsUnlocked * 3 / max(1, achievementsAvailable))
        }
        if beatExpert { points += 2 }
        if dailyChallengesWon > 0 { points += 1 }
        switch points {
        case 0: return 0
        case 1...2: return 1
        case 3...4: return 2
        case 5...7: return 3
        default: return 4
        }
    }

    public var levelKey: String { "mastery.level.\(level)" }

    /// Progress towards the next band, 0…1.
    public var progressToNextLevel: Double {
        let current = level
        guard current < 4 else { return 1 }
        let thresholds = [1, 3, 5, 8]
        var points = 0
        points += min(4, wins / 3)
        if achievementsAvailable > 0 {
            points += min(3, achievementsUnlocked * 3 / max(1, achievementsAvailable))
        }
        if beatExpert { points += 2 }
        if dailyChallengesWon > 0 { points += 1 }
        let next = thresholds[current]
        let previous = current == 0 ? 0 : thresholds[current - 1]
        guard next > previous else { return 1 }
        return min(1, max(0, Double(points - previous) / Double(next - previous)))
    }

    public var isMastered: Bool { level >= 4 }
}

public struct MasteryState: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.mastery"

    public var records: [GameID: MasteryRecord]

    public init(records: [GameID: MasteryRecord] = [:]) {
        self.records = records
    }

    public func validate() -> String? {
        for (_, record) in records where record.wins < 0 { return "negative win count" }
        return nil
    }

    public func record(for gameID: GameID) -> MasteryRecord {
        records[gameID] ?? MasteryRecord(gameID: gameID)
    }

    public func level(for gameID: GameID) -> Int { record(for: gameID).level }

    public var masteredCount: Int { records.values.filter(\.isMastered).count }
}

/// Recomputes mastery from the other stores. It owns no facts of its own, which
/// is why it can never drift out of step with statistics or achievements.
public struct MasteryEngine: Sendable {
    private let registry: GameRegistry

    public init(registry: GameRegistry) {
        self.registry = registry
    }

    public func rebuild(statistics: StatisticsState,
                        achievements: AchievementState,
                        challenge: ChallengeProgress) -> MasteryState {
        var state = MasteryState()
        for definition in registry.all {
            let record = statistics.record(for: definition.id)
            let ids = definition.achievements.map(\.id)
            let unlocked = ids.filter { achievements.isUnlocked($0) }.count
            let beatExpert = record.winsByDifficulty
                .filter { $0.key >= AIDifficulty.expert.rawValue }
                .reduce(0) { $0 + $1.value } > 0
            let dailyWins = challenge.attempts.values
                .flatMap { $0 }
                .filter { $0.gameID == definition.id && $0.succeeded }
                .count
            state.records[definition.id] = MasteryRecord(gameID: definition.id,
                                                         wins: record.gamesWon,
                                                         achievementsUnlocked: unlocked,
                                                         achievementsAvailable: ids.count,
                                                         beatExpert: beatExpert,
                                                         dailyChallengesWon: dailyWins)
        }
        return state
    }
}
