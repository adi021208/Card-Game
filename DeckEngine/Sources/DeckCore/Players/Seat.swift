import Foundation

/// A position at the table. Seats are stable for the life of a game; players
/// (human or AI) are bound to them at setup.
public struct SeatID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible, RawRepresentable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ value: Int) { self.rawValue = value }
    public static func < (lhs: SeatID, rhs: SeatID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { "seat\(rawValue)" }
}

/// Who is operating a seat.
public enum SeatController: Hashable, Codable, Sendable {
    /// A human sharing this device. `profileID` links to a local player profile.
    case human(profileID: String)
    /// An AI opponent with a fixed personality and difficulty.
    case ai(personality: AIPersonalityID, difficulty: AIDifficulty)

    public var isHuman: Bool { if case .human = self { return true }; return false }
    public var isAI: Bool { !isHuman }
}

public struct AIPersonalityID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

public enum AIDifficulty: Int, Codable, CaseIterable, Sendable, Comparable {
    case beginner = 0
    case casual = 1
    case skilled = 2
    case expert = 3

    public static func < (lhs: AIDifficulty, rhs: AIDifficulty) -> Bool { lhs.rawValue < rhs.rawValue }
    public var localizationKey: String { "ai.difficulty.\(self)" }
}

/// A seat with everything the engine needs to run it.
public struct Seat: Hashable, Codable, Sendable, Identifiable {
    public var id: SeatID
    public var displayName: String
    public var controller: SeatController
    /// Team identifier for partnership games (Spades, Euchre). `nil` means solo.
    public var team: Int?
    /// Avatar identifier resolved by the UI layer into artwork.
    public var avatarID: String

    public init(id: SeatID,
                displayName: String,
                controller: SeatController,
                team: Int? = nil,
                avatarID: String = "avatar.default") {
        self.id = id
        self.displayName = displayName
        self.controller = controller
        self.team = team
        self.avatarID = avatarID
    }

    public var isHuman: Bool { controller.isHuman }
}

/// The seating plan for a game, with the turn order baked in.
public struct SeatingPlan: Hashable, Codable, Sendable {
    public private(set) var seats: [Seat]

    public init(seats: [Seat]) {
        precondition(!seats.isEmpty, "A table needs at least one seat")
        self.seats = seats
    }

    public var count: Int { seats.count }
    public var ids: [SeatID] { seats.map(\.id) }
    public var humanSeats: [Seat] { seats.filter(\.isHuman) }
    public var aiSeats: [Seat] { seats.filter { !$0.isHuman } }

    /// True when more than one human shares the device, which is what turns on
    /// the Pass & Play privacy handshake.
    public var isPassAndPlay: Bool { humanSeats.count > 1 }

    public subscript(id: SeatID) -> Seat? {
        seats.first { $0.id == id }
    }

    public func index(of id: SeatID) -> Int? {
        seats.firstIndex { $0.id == id }
    }

    /// Next seat clockwise.
    public func next(after id: SeatID) -> SeatID {
        guard let index = index(of: id) else { return seats[0].id }
        return seats[(index + 1) % seats.count].id
    }

    /// Seat `offset` places clockwise, wrapping.
    public func seat(after id: SeatID, offset: Int) -> SeatID {
        guard let index = index(of: id) else { return seats[0].id }
        let count = seats.count
        let shifted = ((index + offset) % count + count) % count
        return seats[shifted].id
    }

    /// Turn order starting at `id` and going clockwise once around the table.
    public func order(startingAt id: SeatID) -> [SeatID] {
        guard let index = index(of: id) else { return ids }
        return (0..<seats.count).map { seats[($0 + index) % seats.count].id }
    }

    public func teammates(of id: SeatID) -> [SeatID] {
        guard let team = self[id]?.team else { return [] }
        return seats.filter { $0.team == team && $0.id != id }.map(\.id)
    }

    public func opponents(of id: SeatID) -> [SeatID] {
        guard let team = self[id]?.team else { return ids.filter { $0 != id } }
        return seats.filter { $0.team != team }.map(\.id)
    }

    public mutating func rename(_ id: SeatID, to name: String) {
        guard let index = index(of: id) else { return }
        seats[index].displayName = name
    }
}
