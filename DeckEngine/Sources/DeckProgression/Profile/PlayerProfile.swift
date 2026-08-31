import Foundation
import DeckCore

/// A person who plays on this device.
///
/// No account, no sign-in, no server. A family gets a profile each so that
/// Pass & Play remembers who won, and everything stays on the phone.
public struct PlayerProfile: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var avatarID: String
    /// The one profile that owns the device — the one Solo and the daily
    /// challenge use.
    public var isPrimary: Bool
    public var createdAt: Date
    public var lastPlayedAt: Date?
    public var gamesPlayed: Int
    public var gamesWon: Int
    public var favouriteGameID: GameID?
    /// Wins per game, for the local leaderboard on the profile card.
    public var winsByGame: [GameID: Int]

    public init(id: String = UUID().uuidString,
                name: String,
                avatarID: String = "avatar.default",
                isPrimary: Bool = false,
                createdAt: Date = Date(),
                lastPlayedAt: Date? = nil,
                gamesPlayed: Int = 0,
                gamesWon: Int = 0,
                favouriteGameID: GameID? = nil,
                winsByGame: [GameID: Int] = [:]) {
        self.id = id
        self.name = name
        self.avatarID = avatarID
        self.isPrimary = isPrimary
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.favouriteGameID = favouriteGameID
        self.winsByGame = winsByGame
    }

    public var winRateBasisPoints: Int {
        gamesPlayed > 0 ? gamesWon * 10000 / gamesPlayed : 0
    }

    /// Initials for the avatar fallback. Handles names of any length, including
    /// a single character or an emoji.
    public var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? String(name.prefix(1)).uppercased() : letters.joined().uppercased()
    }
}

public struct ProfileState: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.profiles"

    public var profiles: [PlayerProfile]
    /// Profiles used in the last Pass & Play game, so the setup screen can
    /// offer the same table again.
    public var recentTable: [String]

    public init(profiles: [PlayerProfile] = [], recentTable: [String] = []) {
        self.profiles = profiles
        self.recentTable = recentTable
    }

    public func validate() -> String? {
        let ids = Set(profiles.map(\.id))
        if ids.count != profiles.count { return "duplicate profile ids" }
        if profiles.filter(\.isPrimary).count > 1 { return "more than one primary profile" }
        return nil
    }

    public var primary: PlayerProfile? {
        profiles.first(where: \.isPrimary) ?? profiles.first
    }

    public func profile(_ id: String) -> PlayerProfile? {
        profiles.first { $0.id == id }
    }

    public mutating func upsert(_ profile: PlayerProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    public mutating func remove(_ id: String) {
        profiles.removeAll { $0.id == id }
        recentTable.removeAll { $0 == id }
    }

    /// Records a finished game against every human who played it.
    public mutating func record(result: GameResult,
                                gameID: GameID,
                                seating: SeatingPlan) {
        for seat in seating.humanSeats {
            guard case let .human(profileID) = seat.controller,
                  let index = profiles.firstIndex(where: { $0.id == profileID }) else { continue }
            profiles[index].gamesPlayed += 1
            profiles[index].lastPlayedAt = Date()
            if result.winners.contains(seat.id) {
                profiles[index].gamesWon += 1
                profiles[index].winsByGame[gameID, default: 0] += 1
            }
            profiles[index].favouriteGameID = profiles[index].winsByGame
                .max { $0.value < $1.value }?.key ?? gameID
        }
        if seating.humanSeats.count > 1 {
            recentTable = seating.humanSeats.compactMap { seat in
                if case let .human(profileID) = seat.controller { return profileID }
                return nil
            }
        }
    }
}

/// A finished game, kept for the history list.
public struct GameHistoryEntry: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var gameID: GameID
    public var variantID: String
    public var playedAt: Date
    public var durationSeconds: Int
    public var outcome: GameResult.Outcome
    public var score: Int
    /// Opponent names, in seating order.
    public var opponents: [String]
    public var wasPassAndPlay: Bool
    public var wasChallenge: Bool
    /// The seed and log, so the game can be replayed and reviewed.
    public var seed: UInt64
    public var replayLog: [String]

    public init(id: String = UUID().uuidString,
                gameID: GameID,
                variantID: String,
                playedAt: Date = Date(),
                durationSeconds: Int,
                outcome: GameResult.Outcome,
                score: Int,
                opponents: [String],
                wasPassAndPlay: Bool,
                wasChallenge: Bool,
                seed: UInt64,
                replayLog: [String]) {
        self.id = id
        self.gameID = gameID
        self.variantID = variantID
        self.playedAt = playedAt
        self.durationSeconds = durationSeconds
        self.outcome = outcome
        self.score = score
        self.opponents = opponents
        self.wasPassAndPlay = wasPassAndPlay
        self.wasChallenge = wasChallenge
        self.seed = seed
        self.replayLog = replayLog
    }
}

public struct HistoryState: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.history"
    /// A short list, not a feed. Enough to see the last few sessions.
    public static let limit = 40

    public var entries: [GameHistoryEntry]

    public init(entries: [GameHistoryEntry] = []) {
        self.entries = entries
    }

    public func validate() -> String? { nil }

    public mutating func append(_ entry: GameHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    public var recentGameIDs: [GameID] {
        var seen: Set<GameID> = []
        var result: [GameID] = []
        for entry in entries where !seen.contains(entry.gameID) {
            seen.insert(entry.gameID)
            result.append(entry.gameID)
        }
        return result
    }
}

/// Everything else the player has chosen.
public struct SettingsState: Codable, Equatable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.settings"

    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    public var reduceMotion: Bool
    /// Legal moves get a light treatment. Off by default in a challenge.
    public var showMoveAssist: Bool
    /// Hints available during a daily challenge.
    public var allowHintsInChallenges: Bool
    public var dailyReminderEnabled: Bool
    /// Minutes past local midnight for the reminder.
    public var dailyReminderMinutes: Int
    public var favouriteGameIDs: [GameID]
    /// The last configuration the player used, so Quick Play can repeat it.
    public var quickPlayGameID: GameID?
    public var quickPlayVariantID: String?
    public var quickPlayIsPassAndPlay: Bool
    public var preferredDifficulty: AIDifficulty
    public var hasSeenWelcome: Bool
    public var hasSeenPassAndPlayIntro: Bool

    public init(soundEnabled: Bool = true,
                hapticsEnabled: Bool = true,
                reduceMotion: Bool = false,
                showMoveAssist: Bool = true,
                allowHintsInChallenges: Bool = false,
                dailyReminderEnabled: Bool = false,
                dailyReminderMinutes: Int = 19 * 60,
                favouriteGameIDs: [GameID] = [],
                quickPlayGameID: GameID? = nil,
                quickPlayVariantID: String? = nil,
                quickPlayIsPassAndPlay: Bool = false,
                preferredDifficulty: AIDifficulty = .casual,
                hasSeenWelcome: Bool = false,
                hasSeenPassAndPlayIntro: Bool = false) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.reduceMotion = reduceMotion
        self.showMoveAssist = showMoveAssist
        self.allowHintsInChallenges = allowHintsInChallenges
        self.dailyReminderEnabled = dailyReminderEnabled
        self.dailyReminderMinutes = dailyReminderMinutes
        self.favouriteGameIDs = favouriteGameIDs
        self.quickPlayGameID = quickPlayGameID
        self.quickPlayVariantID = quickPlayVariantID
        self.quickPlayIsPassAndPlay = quickPlayIsPassAndPlay
        self.preferredDifficulty = preferredDifficulty
        self.hasSeenWelcome = hasSeenWelcome
        self.hasSeenPassAndPlayIntro = hasSeenPassAndPlayIntro
    }

    public func validate() -> String? {
        if dailyReminderMinutes < 0 || dailyReminderMinutes >= 24 * 60 { return "reminder out of range" }
        return nil
    }
}

/// The one game in progress, if there is one. Saved as a versioned checkpoint so
/// a game survives the app being killed mid-hand.
public struct SavedGameState: Codable, Sendable, PersistablePayload {
    public static let schemaVersion = 1
    public static let storeKey = "deck.savedGame"

    public var checkpoint: GameCheckpoint?
    /// Which human was looking at the screen, so the game resumes on the pass
    /// screen for the right person rather than showing their hand to whoever
    /// opens the app.
    public var viewerSeat: Int?

    public init(checkpoint: GameCheckpoint? = nil, viewerSeat: Int? = nil) {
        self.checkpoint = checkpoint
        self.viewerSeat = viewerSeat
    }

    public func validate() -> String? {
        guard let checkpoint else { return nil }
        if checkpoint.stateData.isEmpty { return "empty checkpoint" }
        if checkpoint.envelopeVersion > GameCheckpoint.currentEnvelopeVersion {
            return "checkpoint from a newer build"
        }
        return nil
    }
}
