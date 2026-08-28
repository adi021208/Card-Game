import Foundation

/// How a finished game came out. The engine produces this; the UI renders it.
public struct GameResult: Hashable, Codable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case win
        case loss
        case draw
        case abandoned
    }

    /// Seats that won. Several for a partnership win or a tie.
    public var winners: [SeatID]
    /// Final score for each seat, in whatever unit the game scores in.
    public var scores: [SeatID: Int]
    /// Finishing order, first to last. Used by President and by multi-player games.
    public var placements: [SeatID]
    /// Wall-clock seconds of active play.
    public var duration: TimeInterval
    /// Turns taken by all seats combined.
    public var turnCount: Int
    /// Rounds/hands/deals played.
    public var roundCount: Int
    /// Game-defined metrics, keyed by `StatisticKey`. Fed straight into the
    /// statistics engine without the engine knowing what any of them mean.
    public var metrics: [String: Int]
    /// Codes emitted via `.highlight`, for achievements to consume.
    public var highlights: [String]

    public init(winners: [SeatID] = [],
                scores: [SeatID: Int] = [:],
                placements: [SeatID] = [],
                duration: TimeInterval = 0,
                turnCount: Int = 0,
                roundCount: Int = 0,
                metrics: [String: Int] = [:],
                highlights: [String] = []) {
        self.winners = winners
        self.scores = scores
        self.placements = placements
        self.duration = duration
        self.turnCount = turnCount
        self.roundCount = roundCount
        self.metrics = metrics
        self.highlights = highlights
    }

    /// Outcome from one seat's point of view.
    public func outcome(for seat: SeatID) -> Outcome {
        if winners.isEmpty { return .draw }
        if winners.contains(seat) { return winners.count > 1 ? .draw : .win }
        return .loss
    }

    public func place(of seat: SeatID) -> Int? {
        guard let index = placements.firstIndex(of: seat) else { return nil }
        return index + 1
    }
}

/// Metric keys the engine itself reports for every game, whatever it is.
///
/// Game-specific metrics live in each game's own `Statistics` enum; these are
/// the ones the session can measure without knowing the rules.
public enum GlobalMetrics {
    public static let undoCount = "core.undoCount"
    public static let hintsUsed = "core.hintsUsed"
    public static let durationSeconds = "core.durationSeconds"
    public static let turns = "core.turns"
}
