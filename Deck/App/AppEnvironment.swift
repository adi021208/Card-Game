import SwiftUI
import Observation
import DeckCore
import DeckCatalog
import DeckProgression

/// Everything the app needs, assembled once.
///
/// The registry, the stores and the services are built here and handed down
/// through the environment. Nothing constructs its own dependencies, which is
/// what makes the whole app previewable and testable against an in-memory store.
@MainActor
@Observable
public final class AppEnvironment {
    public let registry: GameRegistry
    public let progress: ProgressStore
    public let store: StoreService
    public let gameServices: GameServices
    public let challengeGenerator: DailyChallengeGenerator

    /// The challenge for the current local day, resolved once per launch and
    /// refreshed when the day rolls over while the app is open.
    public private(set) var todaysChallenge: DailyChallenge?
    public private(set) var today: ChallengeDate

    /// The theme every screen draws with.
    public var theme: DeckTheme {
        DeckTheme.theme(progress.collection.selectedTheme)
    }

    public var reducedMotion: Bool { progress.settings.reduceMotion }

    public init(store dataStore: DataStore, gameServices: GameServices? = nil) {
        let registry = GameCatalog.makeRegistry()
        self.registry = registry
        let progress = ProgressStore(store: dataStore, registry: registry)
        self.progress = progress
        self.store = StoreService(progress: progress)
        self.gameServices = gameServices ?? GameServices.makeDefault()
        self.challengeGenerator = DailyChallengeGenerator(registry: registry)
        self.today = ChallengeDate.today()
        self.todaysChallenge = challengeGenerator.challenge(for: today)
        progress.expireStreakIfNeeded(today: today)
        applyPreferences()
    }

    /// The one the app actually runs with.
    public static func makeLive() -> AppEnvironment {
        let dataStore: DataStore
        if let fileStore = try? FileDataStore.applicationSupport() {
            dataStore = fileStore
        } else {
            // Disk is unavailable — play on, but say so rather than losing
            // progress silently.
            dataStore = MemoryDataStore()
        }
        return AppEnvironment(store: dataStore)
    }

    /// An environment with nothing in it, for previews and tests.
    public static func makeEphemeral() -> AppEnvironment {
        AppEnvironment(store: MemoryDataStore(),
                       gameServices: GameServices(provider: OfflineGameServiceProvider()))
    }

    /// Re-resolves the day. Called when the app returns to the foreground, so a
    /// device left open overnight picks up the new challenge.
    public func refreshDay() {
        let resolved = ChallengeDate.today()
        guard resolved != today else { return }
        today = resolved
        todaysChallenge = challengeGenerator.challenge(for: resolved)
        progress.expireStreakIfNeeded(today: resolved)
    }

    public func applyPreferences() {
        Haptics.shared.isEnabled = progress.settings.hapticsEnabled
        AudioService.shared.isEnabled = progress.settings.soundEnabled
        AudioService.shared.packID = progress.collection.selectedSoundPack
    }

    // MARK: - Starting games

    /// Builds a configuration for a casual game.
    public func configuration(gameID: GameID,
                              humanCount: Int,
                              aiCount: Int,
                              variantID: String,
                              options: [String: Int],
                              difficulty: AIDifficulty,
                              humanProfiles: [PlayerProfile]) -> GameConfiguration? {
        guard let definition = registry[gameID] else { return nil }
        var seats: [Seat] = []
        let usesTeams = definition.playerRange.lowerBound == 4 && definition.playerRange.upperBound == 4
            && (gameID == .spades || gameID == .euchre)

        for index in 0..<humanCount {
            let profile = index < humanProfiles.count ? humanProfiles[index] : nil
            seats.append(Seat(id: SeatID(index),
                              displayName: profile?.name ?? defaultName(for: index),
                              controller: .human(profileID: profile?.id ?? "guest-\(index)"),
                              team: usesTeams ? index % 2 : nil,
                              avatarID: profile?.avatarID ?? "avatar.default"))
        }
        // Opponents are drawn from the cast in a fixed order so a rematch faces
        // the same table.
        for index in 0..<aiCount {
            let seatIndex = humanCount + index
            let personality = AICast.all[index % AICast.all.count]
            seats.append(Seat(id: SeatID(seatIndex),
                              displayName: personality.displayName,
                              controller: .ai(personality: personality.id, difficulty: difficulty),
                              team: usesTeams ? seatIndex % 2 : nil,
                              avatarID: "avatar.\(personality.id.rawValue)"))
        }
        guard !seats.isEmpty else { return nil }

        let resolved = definition.resolvedOptions(variantID: variantID, overrides: options)
        return GameConfiguration(gameID: gameID,
                                 seating: SeatingPlan(seats: seats),
                                 variantID: variantID,
                                 options: resolved,
                                 seed: SeedFactory.casualSeed())
    }

    private func defaultName(for index: Int) -> String {
        let names = ["Player 1", "Player 2", "Player 3", "Player 4", "Player 5", "Player 6"]
        return index < names.count ? names[index] : "Player \(index + 1)"
    }

    public func makeSession(_ configuration: GameConfiguration) -> GameSessionProtocol? {
        registry.makeSession(configuration: configuration)
    }

    /// Rebuilds the game that was in progress when the app was last closed.
    public func resumeSavedGame() -> (session: GameSessionProtocol, viewerSeat: SeatID?)? {
        guard let checkpoint = progress.savedGame.checkpoint else { return nil }
        // `try?` on a throwing call that already returns an optional gives one
        // optional, not two, so this single binding covers both a throw and a
        // nil: either way the save cannot be rebuilt.
        guard let session = try? registry.restoreSession(from: checkpoint) else {
            // The save is from a build whose rules no longer exist. Drop it
            // rather than loading something that would misplay.
            progress.clearSavedGame()
            return nil
        }
        let seat = progress.savedGame.viewerSeat.map { SeatID($0) }
        return (session, seat)
    }

    /// A one-line description of the saved game, for the Continue card.
    public var savedGameSummary: (gameID: GameID, roundNumber: Int, savedAt: Date)? {
        guard let checkpoint = progress.savedGame.checkpoint else { return nil }
        return (checkpoint.gameID, max(1, checkpoint.turnCount / 4 + 1), checkpoint.savedAt)
    }

    // MARK: - Daily challenge

    public func challengeConfiguration() -> GameConfiguration? {
        guard let challenge = todaysChallenge else { return nil }
        let profile = progress.profiles.primary
        return challengeGenerator.configuration(for: challenge,
                                                playerProfileID: profile?.id ?? "guest",
                                                playerName: profile?.name ?? "You",
                                                avatarID: profile?.avatarID ?? "avatar.default")
    }

    public var attemptsRemaining: Int? {
        guard let challenge = todaysChallenge else { return nil }
        return progress.attemptsRemaining(for: challenge)
    }

    public var canPlayChallenge: Bool {
        guard let challenge = todaysChallenge else { return false }
        if progress.challenge.isCompleted(challenge.date) { return false }
        guard let remaining = attemptsRemaining else { return true }
        return remaining > 0
    }

    /// Pushes progress to Game Center, when it is actually connected.
    public func syncLeaderboards() {
        guard gameServices.isAuthenticated else { return }
        gameServices.submit(score: progress.challenge.bestStreak, to: .bestStreak)
        gameServices.submit(score: progress.challenge.completedDays.count, to: .dailyCompletions)
        gameServices.submit(score: progress.statistics.global.gamesWon, to: .totalWins)
    }
}

// `AppEnvironment` is handed down with `.environment(_:)` and read with
// `@Environment(AppEnvironment.self)`. No `EnvironmentKey` is needed, and none
// is used: an environment key with a default would have to build a whole app
// environment just to have something to return.
