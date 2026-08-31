import Foundation

/// Builds reproducible 64-bit seeds from structured inputs.
///
/// `Hasher`/`hashValue` is explicitly seeded per-process by Swift and must never
/// be used here. This is FNV-1a over UTF-8, then a SplitMix64 avalanche, which
/// is stable forever across launches, devices and OS versions.
public enum SeedFactory {
    public static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return avalanche(hash)
    }

    public static func avalanche(_ input: UInt64) -> UInt64 {
        var z = input &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Combines an ordered list of components into one seed.
    public static func seed(components: [String]) -> UInt64 {
        hash(components.joined(separator: "|"))
    }

    /// The daily-challenge seed contract.
    ///
    /// Every player who opens the same challenge on the same canonical date gets
    /// the identical deal, boss, difficulty and objective. Bumping `rulesVersion`
    /// or `challengeVersion` intentionally re-rolls historical challenges so a
    /// rules fix never silently invalidates a stored result.
    public static func dailySeed(challengeDate: ChallengeDate,
                                 gameID: GameID,
                                 rulesVersion: Int,
                                 challengeVersion: Int) -> UInt64 {
        seed(components: [
            "deck.daily.v1",
            challengeDate.identifier,
            gameID.rawValue,
            "rules\(rulesVersion)",
            "challenge\(challengeVersion)"
        ])
    }

    /// A seed for a casual (non-challenge) game. Uses the system generator so
    /// each casual deal is different, but still funnels through the same
    /// deterministic pipeline so the game is replayable once started.
    public static func casualSeed() -> UInt64 {
        var system = SystemRandomNumberGenerator()
        return avalanche(system.next())
    }
}

/// A calendar day, resolved once and used everywhere.
///
/// Daily challenges roll over at local midnight. Storing the resolved
/// `yyyy-MM-dd` string (rather than a `Date`) sidesteps daylight-saving shifts,
/// leap seconds and locale-specific calendars: once a day has been resolved, its
/// identity never changes, even if the device later moves time zone.
public struct ChallengeDate: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Resolves the challenge day for an instant in a given time zone.
    /// The canonical policy is: **the user's current local calendar day**.
    public init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    public static func today(timeZone: TimeZone = .current, now: Date = Date()) -> ChallengeDate {
        ChallengeDate(date: now, timeZone: timeZone)
    }

    /// `2026-08-28`. Stable, sortable, locale independent.
    public var identifier: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { identifier }

    /// Midnight at the start of this day in the given time zone.
    public func startOfDay(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// Offsets by whole days using real calendar arithmetic, so month lengths,
    /// leap years and DST transitions are handled by `Calendar`.
    public func adding(days: Int, in timeZone: TimeZone = .current) -> ChallengeDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Use noon as the anchor so a DST jump at midnight cannot skip a day.
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let anchor = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .day, value: days, to: anchor) else {
            return self
        }
        return ChallengeDate(date: shifted, timeZone: timeZone)
    }

    /// Whole days from `self` to `other` (negative when `other` is earlier).
    public func days(until other: ChallengeDate, in timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let from = startOfDay(in: timeZone)
        let to = other.startOfDay(in: timeZone)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    public static func < (lhs: ChallengeDate, rhs: ChallengeDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public init?(identifier: String) {
        let parts = identifier.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }
}
