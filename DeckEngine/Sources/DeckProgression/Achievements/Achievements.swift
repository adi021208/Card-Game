import Foundation
import DeckCore

/// Progress towards one achievement.
public struct AchievementProgress: Codable, Sendable, Hashable {
    public var id: String
    public var progress: Int
    public var target: Int
    public var unlockedAt: Date?

    public init(id: String, progress: Int = 0, target: Int, unlockedAt: Date? = nil) {
        self.id = id
        self.progress = progress
        self.target = target
        self.unlockedAt = unlockedAt
    }

    public var isUnlocked: Bool { unlockedAt != nil }
    public var fraction: Double {
        guard target > 0 else { return isUnlocked ? 1 : 0 }
        return min(1, Double(progress) / Double(target))
    }
}

public struct AchievementState: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.achievements"

    public var entries: [String: AchievementProgress]
    /// Unlocks not yet shown as a poster.
    public var pendingCelebrations: [String]

    public init(entries: [String: AchievementProgress] = [:], pendingCelebrations: [String] = []) {
        self.entries = entries
        self.pendingCelebrations = pendingCelebrations
    }

    public func validate() -> String? {
        for (_, entry) in entries where entry.progress < 0 {
            return "negative achievement progress"
        }
        return nil
    }

    public var unlockedCount: Int { entries.values.filter(\.isUnlocked).count }
    public func isUnlocked(_ id: String) -> Bool { entries[id]?.isUnlocked ?? false }
}

/// Everything the achievement engine needs to evaluate a rule.
///
/// Bundled into one value so a rule can be checked without the engine reaching
/// into four different stores.
public struct ProgressSnapshot: Sendable {
    public var statistics: StatisticsState
    public var challenge: ChallengeProgress
    public var mastery: MasteryState
    public var collectionSize: Int
    /// The result that has just been recorded, when there is one.
    public var lastResult: GameResult?
    public var lastGameID: GameID?
    public var lastConfiguration: GameConfiguration?
    public var lastSeat: SeatID?

    public init(statistics: StatisticsState,
                challenge: ChallengeProgress,
                mastery: MasteryState,
                collectionSize: Int,
                lastResult: GameResult? = nil,
                lastGameID: GameID? = nil,
                lastConfiguration: GameConfiguration? = nil,
                lastSeat: SeatID? = nil) {
        self.statistics = statistics
        self.challenge = challenge
        self.mastery = mastery
        self.collectionSize = collectionSize
        self.lastResult = lastResult
        self.lastGameID = lastGameID
        self.lastConfiguration = lastConfiguration
        self.lastSeat = lastSeat
    }

    var didWinLastGame: Bool {
        guard let result = lastResult, let seat = lastSeat else { return false }
        return result.outcome(for: seat) == .win
    }
}

/// Evaluates achievement rules.
///
/// Rules are data (`AchievementTracking`), so this is one `switch` over rule
/// kinds rather than a growing pile of per-game special cases. A new game's
/// achievements come from its own definition and are evaluated by exactly this
/// code.
public struct AchievementEngine: Sendable {
    public let definitions: [AchievementDefinition]
    private let byID: [String: AchievementDefinition]

    public init(definitions: [AchievementDefinition]) {
        self.definitions = definitions
        self.byID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func definition(_ id: String) -> AchievementDefinition? { byID[id] }

    /// Recomputes every achievement and returns the ids that have just unlocked.
    @discardableResult
    public func evaluate(snapshot: ProgressSnapshot, into state: inout AchievementState) -> [String] {
        var newlyUnlocked: [String] = []
        for definition in definitions {
            let target = definition.target
            var entry = state.entries[definition.id] ?? AchievementProgress(id: definition.id, target: target)
            entry.target = target
            let measured = measure(definition.tracking, snapshot: snapshot, existing: entry.progress)
            entry.progress = max(entry.progress, measured)
            if entry.unlockedAt == nil && entry.progress >= target {
                entry.unlockedAt = Date()
                newlyUnlocked.append(definition.id)
            }
            state.entries[definition.id] = entry
        }
        state.pendingCelebrations.append(contentsOf: newlyUnlocked)
        return newlyUnlocked
    }

    /// Current progress towards a rule.
    ///
    /// Cumulative rules (win counts, streaks) are read from stored statistics.
    /// One-shot rules that describe a *single game* — "win with under ten
    /// deadwood", "finish in five minutes" — can only be judged from the game
    /// that has just finished, so they look at `lastResult` and rely on
    /// `max(existing, measured)` to keep the unlock once it is earned.
    private func measure(_ tracking: AchievementTracking,
                         snapshot: ProgressSnapshot,
                         existing: Int) -> Int {
        switch tracking {
        case let .wins(gameID):
            if let gameID { return snapshot.statistics.record(for: gameID).gamesWon }
            return snapshot.statistics.global.gamesWon

        case let .gamesPlayed(gameID):
            if let gameID { return snapshot.statistics.record(for: gameID).gamesPlayed }
            return snapshot.statistics.global.gamesPlayed

        case let .highlight(code, gameID):
            // Highlights are counted as they happen; the stored progress carries
            // the running total.
            guard let result = snapshot.lastResult else { return existing }
            if let gameID, snapshot.lastGameID != gameID { return existing }
            let occurrences = result.highlights.filter { $0 == code }.count
            return existing + occurrences

        case let .metricAtLeast(key, value, gameID):
            guard let result = snapshot.lastResult else { return existing }
            if let gameID, snapshot.lastGameID != gameID { return existing }
            return (result.metrics[key] ?? Int.min) >= value ? existing + 1 : existing

        case let .metricAtMost(key, value, gameID):
            guard let result = snapshot.lastResult else { return existing }
            if let gameID, snapshot.lastGameID != gameID { return existing }
            // "At most" rules only count on a win — finishing fast by losing
            // fast is not an achievement.
            guard snapshot.didWinLastGame, let measured = result.metrics[key] else { return existing }
            return measured <= value ? existing + 1 : existing

        case .dailyStreak:
            return snapshot.challenge.bestStreak

        case .dailyCompletions:
            return snapshot.challenge.completedDays.count

        case let .bossDefeated(bossID):
            return snapshot.challenge.bossesDefeated.contains(bossID) ? 1 : 0

        case .allBossesDefeated:
            return snapshot.challenge.bossesDefeated.count

        case let .mastery(gameID, level):
            return (snapshot.mastery.level(for: gameID) >= level) ? 1 : 0

        case .distinctGamesWon:
            return snapshot.statistics.gamesWonAtLeastOnce.count

        case .passAndPlayGames:
            return snapshot.statistics.global.passAndPlayGames

        case let .winAtDifficulty(difficulty, gameID, _):
            let record = gameID.map { snapshot.statistics.record(for: $0) } ?? snapshot.statistics.global
            return record.winsByDifficulty
                .filter { $0.key >= difficulty.rawValue }
                .reduce(0) { $0 + $1.value }

        case .collectionSize:
            return snapshot.collectionSize
        }
    }
}

/// Achievements that are not about any one game.
public enum GlobalAchievements {

    public static let all: [AchievementDefinition] = [
        AchievementDefinition(id: "global.firstWin",
                              titleKey: "ach.global.firstWin", descriptionKey: "ach.global.firstWin.desc",
                              category: .wins, tracking: .wins(gameID: nil), emblem: .stamp),
        AchievementDefinition(id: "global.fiftyWins",
                              titleKey: "ach.global.fiftyWins", descriptionKey: "ach.global.fiftyWins.desc",
                              category: .wins, tracking: .wins(gameID: nil), targetOverride: 50,
                              rewardID: "cardback.gold", emblem: .crown, weight: .notable),
        AchievementDefinition(id: "global.hundredGames",
                              titleKey: "ach.global.hundredGames", descriptionKey: "ach.global.hundredGames.desc",
                              category: .games, tracking: .gamesPlayed(gameID: nil), targetOverride: 100,
                              emblem: .binder, weight: .notable),

        AchievementDefinition(id: "streak.three",
                              titleKey: "ach.streak.three", descriptionKey: "ach.streak.three.desc",
                              category: .streak, tracking: .dailyStreak(days: 3), emblem: .flame),
        AchievementDefinition(id: "streak.seven",
                              titleKey: "ach.streak.seven", descriptionKey: "ach.streak.seven.desc",
                              category: .streak, tracking: .dailyStreak(days: 7),
                              rewardID: "theme.sundayComic", emblem: .flame, weight: .notable),
        AchievementDefinition(id: "streak.thirty",
                              titleKey: "ach.streak.thirty", descriptionKey: "ach.streak.thirty.desc",
                              category: .streak, tracking: .dailyStreak(days: 30),
                              rewardID: "cardback.streak", emblem: .flame, weight: .landmark),
        AchievementDefinition(id: "daily.ten",
                              titleKey: "ach.daily.ten", descriptionKey: "ach.daily.ten.desc",
                              category: .streak, tracking: .dailyCompletions(count: 10), emblem: .clock),

        AchievementDefinition(id: "boss.scarlet",
                              titleKey: "ach.boss.scarlet", descriptionKey: "ach.boss.scarlet.desc",
                              category: .boss, tracking: .bossDefeated(bossID: "scarlet"),
                              rewardID: "avatar.scarlet", emblem: .skull, weight: .notable),
        AchievementDefinition(id: "boss.all",
                              titleKey: "ach.boss.all", descriptionKey: "ach.boss.all.desc",
                              category: .boss, tracking: .allBossesDefeated,
                              rewardID: "theme.streetPrint", emblem: .crown, weight: .landmark),

        AchievementDefinition(id: "passplay.ten",
                              titleKey: "ach.passplay.ten", descriptionKey: "ach.passplay.ten.desc",
                              category: .passAndPlay, tracking: .passAndPlayGames(count: 10),
                              rewardID: "cardback.table", emblem: .binder, weight: .notable),
        AchievementDefinition(id: "passplay.first",
                              titleKey: "ach.passplay.first", descriptionKey: "ach.passplay.first.desc",
                              category: .passAndPlay, tracking: .passAndPlayGames(count: 1), emblem: .stamp),

        AchievementDefinition(id: "library.five",
                              titleKey: "ach.library.five", descriptionKey: "ach.library.five.desc",
                              category: .collection, tracking: .distinctGamesWon(count: 5), emblem: .binder),
        AchievementDefinition(id: "library.everything",
                              titleKey: "ach.library.everything", descriptionKey: "ach.library.everything.desc",
                              category: .collection, tracking: .distinctGamesWon(count: 15),
                              rewardID: "cardback.library", emblem: .crown, weight: .landmark),
        AchievementDefinition(id: "collection.ten",
                              titleKey: "ach.collection.ten", descriptionKey: "ach.collection.ten.desc",
                              category: .collection, tracking: .collectionSize(count: 10), emblem: .binder),

        AchievementDefinition(id: "skill.expert",
                              titleKey: "ach.skill.expert", descriptionKey: "ach.skill.expert.desc",
                              category: .skill, tracking: .winAtDifficulty(.expert, gameID: nil, count: 1),
                              emblem: .crown, weight: .notable),
        AchievementDefinition(id: "skill.expertTen",
                              titleKey: "ach.skill.expertTen", descriptionKey: "ach.skill.expertTen.desc",
                              category: .skill, tracking: .winAtDifficulty(.expert, gameID: nil, count: 10),
                              rewardID: "avatar.expert", emblem: .crown, weight: .landmark)
    ]
}
