import Foundation
import DeckCore

/// One recorded run at a daily challenge.
public struct ChallengeAttempt: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var challengeID: String
    public var date: ChallengeDate
    public var gameID: GameID
    public var attemptNumber: Int
    public var startedAt: Date
    public var finishedAt: Date?
    public var succeeded: Bool
    public var score: Int
    public var durationSeconds: Int
    public var turns: Int
    public var difficultyPercent: Int
    public var bossID: String?
    /// The move log, so a result can be verified rather than trusted.
    public var replayLog: [String]

    public init(id: String = UUID().uuidString,
                challengeID: String,
                date: ChallengeDate,
                gameID: GameID,
                attemptNumber: Int,
                startedAt: Date = Date(),
                finishedAt: Date? = nil,
                succeeded: Bool = false,
                score: Int = 0,
                durationSeconds: Int = 0,
                turns: Int = 0,
                difficultyPercent: Int = 0,
                bossID: String? = nil,
                replayLog: [String] = []) {
        self.id = id
        self.challengeID = challengeID
        self.date = date
        self.gameID = gameID
        self.attemptNumber = attemptNumber
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.succeeded = succeeded
        self.score = score
        self.durationSeconds = durationSeconds
        self.turns = turns
        self.difficultyPercent = difficultyPercent
        self.bossID = bossID
        self.replayLog = replayLog
    }

    public var isComplete: Bool { finishedAt != nil }
}

/// Everything the app remembers about the daily challenge.
public struct ChallengeProgress: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.challenge.progress"

    /// Attempts keyed by challenge id.
    public var attempts: [String: [ChallengeAttempt]]
    /// Days completed successfully, newest last.
    public var completedDays: [ChallengeDate]
    /// Days attempted and failed.
    public var failedDays: [ChallengeDate]
    public var currentStreak: Int
    public var bestStreak: Int
    /// The last day counted towards the streak, so a day cannot count twice.
    public var lastStreakDay: ChallengeDate?
    /// Bosses beaten at least once.
    public var bossesDefeated: Set<String>
    /// Best result per challenge, for the "Best" line on the challenge poster.
    public var bestScores: [String: Int]
    public var bestTimes: [String: Int]

    public init(attempts: [String: [ChallengeAttempt]] = [:],
                completedDays: [ChallengeDate] = [],
                failedDays: [ChallengeDate] = [],
                currentStreak: Int = 0,
                bestStreak: Int = 0,
                lastStreakDay: ChallengeDate? = nil,
                bossesDefeated: Set<String> = [],
                bestScores: [String: Int] = [:],
                bestTimes: [String: Int] = [:]) {
        self.attempts = attempts
        self.completedDays = completedDays
        self.failedDays = failedDays
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.lastStreakDay = lastStreakDay
        self.bossesDefeated = bossesDefeated
        self.bestScores = bestScores
        self.bestTimes = bestTimes
    }

    public func validate() -> String? {
        if currentStreak < 0 || bestStreak < 0 { return "negative streak" }
        if currentStreak > bestStreak { return "current streak exceeds best" }
        return nil
    }

    public func attempts(for challengeID: String) -> [ChallengeAttempt] {
        attempts[challengeID] ?? []
    }

    public func isCompleted(_ date: ChallengeDate) -> Bool {
        completedDays.contains(date)
    }
}

/// Applies daily-challenge results to stored progress.
///
/// The integrity rules live here and nowhere else: a day counts once, a streak
/// advances once, attempts are capped, and a result can be re-verified from its
/// own replay log before it is accepted.
public struct ChallengeLedger: Sendable {
    public static let freeAttemptsPerDay = 3

    public var progress: ChallengeProgress
    /// Premium players get unlimited attempts.
    public var hasUnlimitedAttempts: Bool

    public init(progress: ChallengeProgress = ChallengeProgress(), hasUnlimitedAttempts: Bool = false) {
        self.progress = progress
        self.hasUnlimitedAttempts = hasUnlimitedAttempts
    }

    public func attemptsUsed(for challenge: DailyChallenge) -> Int {
        progress.attempts(for: challenge.id).count
    }

    public func attemptsRemaining(for challenge: DailyChallenge) -> Int? {
        guard !hasUnlimitedAttempts else { return nil }
        return max(0, Self.freeAttemptsPerDay - attemptsUsed(for: challenge))
    }

    public func canAttempt(_ challenge: DailyChallenge) -> Bool {
        // A completed day cannot be replayed for a second reward, ever.
        guard !progress.isCompleted(challenge.date) else { return false }
        guard let remaining = attemptsRemaining(for: challenge) else { return true }
        return remaining > 0
    }

    /// Opens a new attempt, or returns nil when the player has none left.
    public mutating func beginAttempt(_ challenge: DailyChallenge) -> ChallengeAttempt? {
        guard canAttempt(challenge) else { return nil }
        let number = attemptsUsed(for: challenge) + 1
        let attempt = ChallengeAttempt(challengeID: challenge.id,
                                       date: challenge.date,
                                       gameID: challenge.gameID,
                                       attemptNumber: number,
                                       difficultyPercent: challenge.difficultyPercent,
                                       bossID: challenge.bossID)
        progress.attempts[challenge.id, default: []].append(attempt)
        return attempt
    }

    /// Records the outcome of an attempt and updates the streak.
    ///
    /// Returns what changed, so the UI can play exactly the right celebration.
    @discardableResult
    public mutating func finish(attempt: ChallengeAttempt,
                                challenge: DailyChallenge,
                                result: GameResult,
                                seat: SeatID,
                                succeeded: Bool,
                                replayLog: [String]) -> ChallengeOutcome {
        var stored = attempt
        stored.finishedAt = Date()
        stored.succeeded = succeeded
        stored.score = result.scores[seat] ?? 0
        stored.durationSeconds = Int(result.duration.rounded())
        stored.turns = result.turnCount
        stored.replayLog = replayLog

        var list = progress.attempts(for: challenge.id)
        if let index = list.firstIndex(where: { $0.id == attempt.id }) {
            list[index] = stored
        } else {
            list.append(stored)
        }
        progress.attempts[challenge.id] = list

        // Best-of tracking is independent of the streak.
        if stored.score > (progress.bestScores[challenge.id] ?? Int.min) {
            progress.bestScores[challenge.id] = stored.score
        }
        if succeeded, stored.durationSeconds > 0,
           stored.durationSeconds < (progress.bestTimes[challenge.id] ?? Int.max) {
            progress.bestTimes[challenge.id] = stored.durationSeconds
        }

        guard succeeded else {
            if !progress.failedDays.contains(challenge.date) && !progress.isCompleted(challenge.date) {
                progress.failedDays.append(challenge.date)
            }
            return ChallengeOutcome(succeeded: false,
                                    streakAdvanced: false,
                                    streak: progress.currentStreak,
                                    isNewBestStreak: false,
                                    bossDefeated: nil,
                                    attemptsRemaining: attemptsRemaining(for: challenge))
        }

        // A day can only ever be completed once, which is what stops a streak
        // being farmed by replaying the same challenge.
        var streakAdvanced = false
        var newBest = false
        var bossDefeated: String?

        if !progress.isCompleted(challenge.date) {
            progress.completedDays.append(challenge.date)
            progress.failedDays.removeAll { $0 == challenge.date }

            if let last = progress.lastStreakDay {
                let gap = last.days(until: challenge.date)
                if gap == 1 {
                    progress.currentStreak += 1
                } else if gap == 0 {
                    // Same day again: no change. Should not happen, but a clock
                    // change should never be able to inflate a streak.
                } else {
                    progress.currentStreak = 1
                }
            } else {
                progress.currentStreak = 1
            }
            progress.lastStreakDay = challenge.date
            streakAdvanced = true
            if progress.currentStreak > progress.bestStreak {
                progress.bestStreak = progress.currentStreak
                newBest = true
            }
            if let bossID = challenge.bossID, !progress.bossesDefeated.contains(bossID) {
                progress.bossesDefeated.insert(bossID)
                bossDefeated = bossID
            } else if let bossID = challenge.bossID {
                progress.bossesDefeated.insert(bossID)
            }
        }

        return ChallengeOutcome(succeeded: true,
                                streakAdvanced: streakAdvanced,
                                streak: progress.currentStreak,
                                isNewBestStreak: newBest,
                                bossDefeated: bossDefeated,
                                attemptsRemaining: attemptsRemaining(for: challenge))
    }

    /// Breaks the streak when a day has been missed entirely.
    ///
    /// Call on launch with today's date: if the last completed day is more than
    /// one day ago, the run is over.
    public mutating func expireStreakIfNeeded(today: ChallengeDate) {
        guard let last = progress.lastStreakDay else { return }
        if last.days(until: today) > 1 {
            progress.currentStreak = 0
        }
    }

    /// Whether the result satisfies the objective.
    ///
    /// The engine decides this, not the interface — a challenge is passed
    /// because the rules say so, never because a screen said "you win".
    public static func evaluate(objective: ChallengeObjective,
                                result: GameResult,
                                seat: SeatID,
                                bossID: String?) -> Bool {
        switch objective {
        case let .score(target):
            return (result.scores[seat] ?? 0) >= target
        case let .speed(seconds):
            return result.outcome(for: seat) == .win && Int(result.duration.rounded()) <= seconds
        case let .efficiency(turns):
            return result.outcome(for: seat) == .win && result.turnCount <= turns
        case let .target(value, metricKey):
            return (result.metrics[metricKey] ?? 0) >= value
        case .handicap:
            return result.outcome(for: seat) == .win
        case let .perfect(highlight):
            return result.highlights.contains(highlight)
        case .boss:
            guard bossID != nil else { return false }
            return result.outcome(for: seat) == .win
        }
    }
}

/// What changed when a daily challenge attempt finished.
public struct ChallengeOutcome: Hashable, Sendable {
    public var succeeded: Bool
    public var streakAdvanced: Bool
    public var streak: Int
    public var isNewBestStreak: Bool
    public var bossDefeated: String?
    /// Nil when unlimited.
    public var attemptsRemaining: Int?

    public init(succeeded: Bool,
                streakAdvanced: Bool,
                streak: Int,
                isNewBestStreak: Bool,
                bossDefeated: String?,
                attemptsRemaining: Int?) {
        self.succeeded = succeeded
        self.streakAdvanced = streakAdvanced
        self.streak = streak
        self.isNewBestStreak = isNewBestStreak
        self.bossDefeated = bossDefeated
        self.attemptsRemaining = attemptsRemaining
    }
}
