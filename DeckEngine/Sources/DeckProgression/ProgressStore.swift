import Foundation
import DeckCore
import DeckCatalog

/// What the player is entitled to. Set by the StoreKit layer, read everywhere.
public struct Entitlements: Codable, Sendable, Hashable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.entitlements"

    public enum Level: String, Codable, Sendable {
        case free
        case subscribed
        case lifetime
    }

    public var level: Level
    /// When a subscription runs out. Nil for free and lifetime.
    public var expiresAt: Date?
    /// True when Apple has told us a purchase was revoked or refunded.
    public var isRevoked: Bool
    /// When the entitlement was last verified against the store.
    public var verifiedAt: Date?

    public init(level: Level = .free,
                expiresAt: Date? = nil,
                isRevoked: Bool = false,
                verifiedAt: Date? = nil) {
        self.level = level
        self.expiresAt = expiresAt
        self.isRevoked = isRevoked
        self.verifiedAt = verifiedAt
    }

    /// Whether premium is active right now.
    ///
    /// A lapsed subscription and a revoked purchase both fall back to free
    /// immediately; nothing is granted on trust.
    public func isPremium(now: Date = Date()) -> Bool {
        guard !isRevoked else { return false }
        switch level {
        case .free: return false
        case .lifetime: return true
        case .subscribed:
            guard let expiresAt else { return false }
            return expiresAt > now
        }
    }

    public func validate() -> String? { nil }

    public static let free = Entitlements()
}

/// The one place the app reads and writes progress.
///
/// Everything is loaded on init, held in memory, and written back after any
/// meaningful action. Each payload validates itself on the way in and out, and a
/// single corrupt file is replaced with a fresh default rather than taking the
/// whole app down with it.
public final class ProgressStore: @unchecked Sendable {
    private let records: RecordStore
    private let registry: GameRegistry
    private let statisticsEngine: StatisticsEngine
    private let masteryEngine: MasteryEngine
    private let collectionEngine = CollectionEngine()
    public let achievementEngine: AchievementEngine
    private let lock = NSLock()

    public private(set) var statistics: StatisticsState
    public private(set) var achievements: AchievementState
    public private(set) var mastery: MasteryState
    public private(set) var collection: CollectionState
    public private(set) var challenge: ChallengeProgress
    public private(set) var profiles: ProfileState
    public private(set) var history: HistoryState
    public private(set) var settings: SettingsState
    public private(set) var entitlements: Entitlements
    public private(set) var savedGame: SavedGameState

    /// Anything that failed to load, so the settings screen can say so honestly
    /// instead of silently resetting the player's progress.
    public private(set) var loadFailures: [String] = []

    public init(store: DataStore, registry: GameRegistry) {
        // Held locally as well as stored: the loader below is a nested
        // function, and reading self.records from it would count as using
        // self before every stored property is initialised.
        let recordStore = RecordStore(store: store)
        self.records = recordStore
        self.registry = registry
        self.statisticsEngine = StatisticsEngine(registry: registry)
        self.masteryEngine = MasteryEngine(registry: registry)
        self.achievementEngine = AchievementEngine(
            definitions: registry.allAchievements(global: GlobalAchievements.all))

        var failures: [String] = []
        func load<Payload: PersistablePayload>(_ type: Payload.Type, fallback: Payload) -> Payload {
            do {
                return try recordStore.load(type) ?? fallback
            } catch {
                failures.append(Payload.storeKey)
                return fallback
            }
        }

        statistics = load(StatisticsState.self, fallback: StatisticsState())
        achievements = load(AchievementState.self, fallback: AchievementState())
        mastery = load(MasteryState.self, fallback: MasteryState())
        collection = load(CollectionState.self, fallback: CollectionState())
        challenge = load(ChallengeProgress.self, fallback: ChallengeProgress())
        profiles = load(ProfileState.self, fallback: ProfileState())
        history = load(HistoryState.self, fallback: HistoryState())
        settings = load(SettingsState.self, fallback: SettingsState())
        entitlements = load(Entitlements.self, fallback: .free)
        savedGame = load(SavedGameState.self, fallback: SavedGameState())
        loadFailures = failures

        // A first run needs somebody to play as.
        if profiles.profiles.isEmpty {
            profiles.upsert(PlayerProfile(name: "You", isPrimary: true))
            persist(profiles)
        }
        // Default cosmetics are always owned.
        _ = collectionEngine.refresh(state: &collection,
                                     achievements: achievements,
                                     challenge: challenge,
                                     mastery: mastery,
                                     hasPremium: entitlements.isPremium())
        persist(collection)
    }

    public var hasPremium: Bool { entitlements.isPremium() }

    // MARK: - Recording a finished game

    /// The one entry point for "a game just ended".
    ///
    /// Statistics, achievements, mastery, the collection, the local profiles and
    /// the history list are all updated from this, in that order, because each
    /// depends on the one before it.
    @discardableResult
    public func recordFinishedGame(result: GameResult,
                                   gameID: GameID,
                                   seat: SeatID,
                                   configuration: GameConfiguration,
                                   replayLog: [String]) -> ProgressChange {
        lock.lock()
        defer { lock.unlock() }

        statisticsEngine.record(result: result,
                                gameID: gameID,
                                seat: seat,
                                configuration: configuration,
                                into: &statistics)

        profiles.record(result: result, gameID: gameID, seating: configuration.seating)

        let opponentNames = configuration.seating.seats
            .filter { $0.id != seat }
            .map(\.displayName)
        history.append(GameHistoryEntry(gameID: gameID,
                                        variantID: configuration.variantID,
                                        durationSeconds: Int(result.duration.rounded()),
                                        outcome: result.outcome(for: seat),
                                        score: result.scores[seat] ?? 0,
                                        opponents: opponentNames,
                                        wasPassAndPlay: configuration.isPassAndPlay,
                                        wasChallenge: configuration.isChallenge,
                                        seed: configuration.seed,
                                        replayLog: replayLog))

        mastery = masteryEngine.rebuild(statistics: statistics,
                                        achievements: achievements,
                                        challenge: challenge)

        let snapshot = ProgressSnapshot(statistics: statistics,
                                        challenge: challenge,
                                        mastery: mastery,
                                        collectionSize: collection.unlocked.count,
                                        lastResult: result,
                                        lastGameID: gameID,
                                        lastConfiguration: configuration,
                                        lastSeat: seat)
        let unlockedAchievements = achievementEngine.evaluate(snapshot: snapshot, into: &achievements)

        // Mastery can move again once achievements have been granted.
        mastery = masteryEngine.rebuild(statistics: statistics,
                                        achievements: achievements,
                                        challenge: challenge)
        let unlockedCosmetics = collectionEngine.refresh(state: &collection,
                                                         achievements: achievements,
                                                         challenge: challenge,
                                                         mastery: mastery,
                                                         hasPremium: hasPremium)

        persistAll()
        return ProgressChange(unlockedAchievements: unlockedAchievements,
                              unlockedCosmetics: unlockedCosmetics,
                              masteryLevel: mastery.level(for: gameID))
    }

    /// Records the outcome of a daily-challenge attempt.
    @discardableResult
    public func recordChallenge(attempt: ChallengeAttempt,
                                challenge dailyChallenge: DailyChallenge,
                                result: GameResult,
                                seat: SeatID,
                                succeeded: Bool,
                                replayLog: [String]) -> ChallengeOutcome {
        lock.lock()
        var ledger = ChallengeLedger(progress: challenge, hasUnlimitedAttempts: hasPremium)
        let outcome = ledger.finish(attempt: attempt,
                                    challenge: dailyChallenge,
                                    result: result,
                                    seat: seat,
                                    succeeded: succeeded,
                                    replayLog: replayLog)
        challenge = ledger.progress
        persist(challenge)
        lock.unlock()

        // Streaks feed achievements and the collection.
        lock.lock()
        defer { lock.unlock() }
        let snapshot = ProgressSnapshot(statistics: statistics,
                                        challenge: challenge,
                                        mastery: mastery,
                                        collectionSize: collection.unlocked.count)
        achievementEngine.evaluate(snapshot: snapshot, into: &achievements)
        mastery = masteryEngine.rebuild(statistics: statistics,
                                        achievements: achievements,
                                        challenge: challenge)
        _ = collectionEngine.refresh(state: &collection,
                                     achievements: achievements,
                                     challenge: challenge,
                                     mastery: mastery,
                                     hasPremium: hasPremium)
        persistAll()
        return outcome
    }

    public func beginChallengeAttempt(_ dailyChallenge: DailyChallenge) -> ChallengeAttempt? {
        lock.lock()
        defer { lock.unlock() }
        var ledger = ChallengeLedger(progress: challenge, hasUnlimitedAttempts: hasPremium)
        let attempt = ledger.beginAttempt(dailyChallenge)
        challenge = ledger.progress
        persist(challenge)
        return attempt
    }

    public func attemptsRemaining(for dailyChallenge: DailyChallenge) -> Int? {
        ChallengeLedger(progress: challenge, hasUnlimitedAttempts: hasPremium)
            .attemptsRemaining(for: dailyChallenge)
    }

    public func expireStreakIfNeeded(today: ChallengeDate) {
        lock.lock()
        defer { lock.unlock() }
        var ledger = ChallengeLedger(progress: challenge, hasUnlimitedAttempts: hasPremium)
        let before = ledger.progress.currentStreak
        ledger.expireStreakIfNeeded(today: today)
        if ledger.progress.currentStreak != before {
            challenge = ledger.progress
            persist(challenge)
        }
    }

    // MARK: - Mutation

    public func update(settings newValue: SettingsState) {
        lock.lock(); defer { lock.unlock() }
        settings = newValue
        persist(settings)
    }

    public func update(profiles newValue: ProfileState) {
        lock.lock(); defer { lock.unlock() }
        profiles = newValue
        persist(profiles)
    }

    public func update(collection newValue: CollectionState) {
        lock.lock(); defer { lock.unlock() }
        collection = newValue
        persist(collection)
    }

    public func update(entitlements newValue: Entitlements) {
        lock.lock(); defer { lock.unlock() }
        entitlements = newValue
        persist(entitlements)
        _ = collectionEngine.refresh(state: &collection,
                                     achievements: achievements,
                                     challenge: challenge,
                                     mastery: mastery,
                                     hasPremium: newValue.isPremium())
        persist(collection)
    }

    public func saveGame(_ checkpoint: GameCheckpoint?, viewerSeat: SeatID?) {
        lock.lock(); defer { lock.unlock() }
        savedGame = SavedGameState(checkpoint: checkpoint, viewerSeat: viewerSeat?.rawValue)
        persist(savedGame)
    }

    public func clearSavedGame() {
        saveGame(nil, viewerSeat: nil)
    }

    public func consumeAchievementCelebrations() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let pending = achievements.pendingCelebrations
        achievements.pendingCelebrations = []
        persist(achievements)
        return pending
    }

    public func consumeCollectionReveals() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let pending = collection.pendingReveals
        collection.pendingReveals = []
        persist(collection)
        return pending
    }

    /// Wipes everything. Used by the debug menu and by "reset progress".
    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        statistics = StatisticsState()
        achievements = AchievementState()
        mastery = MasteryState()
        collection = CollectionState()
        challenge = ChallengeProgress()
        history = HistoryState()
        savedGame = SavedGameState()
        _ = collectionEngine.refresh(state: &collection,
                                     achievements: achievements,
                                     challenge: challenge,
                                     mastery: mastery,
                                     hasPremium: hasPremium)
        persistAll()
    }

    // MARK: - Persistence

    private func persist<Payload: PersistablePayload>(_ payload: Payload) {
        do {
            try records.save(payload)
        } catch {
            // A failed write must not lose the in-memory state; the next write
            // will try again with the same data.
            loadFailures.append(Payload.storeKey)
        }
    }

    private func persistAll() {
        persist(statistics)
        persist(achievements)
        persist(mastery)
        persist(collection)
        persist(challenge)
        persist(profiles)
        persist(history)
        persist(settings)
        persist(savedGame)
    }
}

/// What changed when a game was recorded.
public struct ProgressChange: Sendable, Hashable {
    public var unlockedAchievements: [String]
    public var unlockedCosmetics: [String]
    public var masteryLevel: Int

    public init(unlockedAchievements: [String], unlockedCosmetics: [String], masteryLevel: Int) {
        self.unlockedAchievements = unlockedAchievements
        self.unlockedCosmetics = unlockedCosmetics
        self.masteryLevel = masteryLevel
    }

    public var isEmpty: Bool { unlockedAchievements.isEmpty && unlockedCosmetics.isEmpty }
}
