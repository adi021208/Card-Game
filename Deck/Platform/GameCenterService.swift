import Foundation
import Observation
#if canImport(GameKit)
import GameKit
#endif
import DeckCore

/// A leaderboard DECK posts to.
public struct LeaderboardID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }

    /// Longest daily streak.
    public static let bestStreak = LeaderboardID("deck.streak.best")
    /// Days completed in total.
    public static let dailyCompletions = LeaderboardID("deck.daily.completions")
    /// Games won across the whole library.
    public static let totalWins = LeaderboardID("deck.wins.total")

    /// A per-game score board. The metric is whatever that game actually
    /// produces — chips for poker, a low score for Hearts, moves for FreeCell.
    public static func game(_ id: GameID) -> LeaderboardID {
        LeaderboardID("deck.game.\(id.rawValue)")
    }

    /// The fastest win at a game.
    public static func fastest(_ id: GameID) -> LeaderboardID {
        LeaderboardID("deck.fastest.\(id.rawValue)")
    }
}

/// What DECK needs from a game service.
///
/// Behind a protocol because Game Center cannot be signed into during
/// development, and because pretending it is connected when it is not would be
/// a lie the rest of the app would then act on.
public protocol GameServiceProvider: AnyObject, Sendable {
    var isAuthenticated: Bool { get }
    var playerDisplayName: String? { get }
    /// Nil until authentication has been attempted.
    var lastError: String? { get }
    func authenticate() async
    func submit(score: Int, to leaderboard: LeaderboardID) async
    func report(achievementID: String, percentComplete: Double) async
    func loadTopScores(_ leaderboard: LeaderboardID, limit: Int) async -> [LeaderboardEntry]
}

public struct LeaderboardEntry: Identifiable, Sendable, Hashable {
    public var id: String
    public var rank: Int
    public var displayName: String
    public var formattedScore: String
    public var isLocalPlayer: Bool

    public init(id: String, rank: Int, displayName: String, formattedScore: String, isLocalPlayer: Bool) {
        self.id = id
        self.rank = rank
        self.displayName = displayName
        self.formattedScore = formattedScore
        self.isLocalPlayer = isLocalPlayer
    }
}

/// The real Game Center integration.
#if canImport(GameKit)
public final class GameCenterProvider: GameServiceProvider, @unchecked Sendable {
    public private(set) var isAuthenticated = false
    public private(set) var playerDisplayName: String?
    public private(set) var lastError: String?

    public init() {}

    public func authenticate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let player = GKLocalPlayer.local
            player.authenticateHandler = { [weak self] _, error in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    self.isAuthenticated = false
                } else {
                    self.isAuthenticated = player.isAuthenticated
                    self.playerDisplayName = player.isAuthenticated ? player.displayName : nil
                    self.lastError = nil
                }
                continuation.resume()
            }
        }
    }

    public func submit(score: Int, to leaderboard: LeaderboardID) async {
        guard isAuthenticated else { return }
        try? await GKLeaderboard.submitScore(score,
                                             context: 0,
                                             player: GKLocalPlayer.local,
                                             leaderboardIDs: [leaderboard.rawValue])
    }

    public func report(achievementID: String, percentComplete: Double) async {
        guard isAuthenticated else { return }
        let achievement = GKAchievement(identifier: achievementID)
        achievement.percentComplete = min(100, max(0, percentComplete * 100))
        achievement.showsCompletionBanner = true
        try? await GKAchievement.report([achievement])
    }

    public func loadTopScores(_ leaderboard: LeaderboardID, limit: Int) async -> [LeaderboardEntry] {
        guard isAuthenticated else { return [] }
        guard let boards = try? await GKLeaderboard.loadLeaderboards(IDs: [leaderboard.rawValue]),
              let board = boards.first else { return [] }
        guard let entries = try? await board.loadEntries(for: .global,
                                                         timeScope: .allTime,
                                                         range: NSRange(location: 1, length: max(1, limit)))
        else { return [] }
        let localID = GKLocalPlayer.local.gamePlayerID
        return entries.1.map { entry in
            LeaderboardEntry(id: entry.player.gamePlayerID,
                             rank: entry.rank,
                             displayName: entry.player.displayName,
                             formattedScore: entry.formattedScore,
                             isLocalPlayer: entry.player.gamePlayerID == localID)
        }
    }
}
#endif

/// The stand-in used in development, in previews and in tests.
///
/// It never claims to be authenticated. Everything that reads
/// `isAuthenticated` therefore shows the honest "not signed in" state rather
/// than a fake leaderboard, which is the point.
public final class OfflineGameServiceProvider: GameServiceProvider, @unchecked Sendable {
    public private(set) var isAuthenticated = false
    public private(set) var playerDisplayName: String?
    public private(set) var lastError: String?
    /// Scores that would have been submitted, so the debug menu can show them.
    public private(set) var submitted: [(LeaderboardID, Int)] = []

    public init() {}

    public func authenticate() async {
        lastError = String(localized: "gamecenter.unavailable",
                           defaultValue: "Game Center is not signed in on this device.")
    }

    public func submit(score: Int, to leaderboard: LeaderboardID) async {
        submitted.append((leaderboard, score))
    }

    public func report(achievementID: String, percentComplete: Double) async {}

    public func loadTopScores(_ leaderboard: LeaderboardID, limit: Int) async -> [LeaderboardEntry] { [] }
}

/// Chooses a provider and gives the app one thing to talk to.
@MainActor
@Observable
public final class GameServices {
    public private(set) var isAuthenticated = false
    public private(set) var playerName: String?
    public private(set) var statusMessage: String?

    private let provider: GameServiceProvider

    public init(provider: GameServiceProvider) {
        self.provider = provider
    }

    /// Uses the real Game Center where the framework exists, and the honest
    /// offline stand-in everywhere else.
    public static func makeDefault() -> GameServices {
        #if canImport(GameKit) && !targetEnvironment(simulator)
        return GameServices(provider: GameCenterProvider())
        #else
        return GameServices(provider: OfflineGameServiceProvider())
        #endif
    }

    public func authenticate() async {
        await provider.authenticate()
        isAuthenticated = provider.isAuthenticated
        playerName = provider.playerDisplayName
        statusMessage = provider.lastError
    }

    public func submit(score: Int, to leaderboard: LeaderboardID) {
        Task { await provider.submit(score: score, to: leaderboard) }
    }

    public func report(achievementID: String, fraction: Double) {
        Task { await provider.report(achievementID: achievementID, percentComplete: fraction) }
    }

    public func topScores(_ leaderboard: LeaderboardID, limit: Int = 10) async -> [LeaderboardEntry] {
        await provider.loadTopScores(leaderboard, limit: limit)
    }
}
