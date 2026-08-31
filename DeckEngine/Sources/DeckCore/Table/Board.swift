import Foundation

/// The physical state of the table: which cards exist, which pile each one is
/// in, which way up it is, and who may see its face.
///
/// `Board` is a pure value type. Games own one and mutate it through the
/// vocabulary below (`deal`, `move`, `flip`, `reveal`) rather than shuffling
/// arrays by hand, which keeps the visibility bookkeeping impossible to forget.
public struct Board: Codable, Sendable, Equatable {
    /// Every card in the game, by identifier.
    public private(set) var cards: [CardID: Card]
    /// Ordered contents of each pile. Index 0 is the bottom of a stack and the
    /// left-hand end of a fanned row.
    public private(set) var piles: [Zone: [CardID]]
    /// Reverse index so `zone(of:)` is O(1).
    private var locations: [CardID: Zone]
    /// Face-up cards. Orientation is presentation; `visibility` is permission.
    /// They usually agree, and `move(_:facing:)` keeps them in step.
    public private(set) var faceUp: Set<CardID>
    /// Permission to see each card's face.
    public private(set) var visibility: [CardID: Visibility]

    public init() {
        cards = [:]
        piles = [:]
        locations = [:]
        faceUp = []
        visibility = [:]
    }

    // MARK: - Building

    /// Puts a fresh, shuffled deck into a pile. Everything starts face-down and
    /// hidden; the deal then reveals what it should.
    public mutating func load(_ deck: [Card], into zone: Zone) {
        for card in deck {
            cards[card.id] = card
            locations[card.id] = zone
            visibility[card.id] = .hidden
        }
        piles[zone, default: []].append(contentsOf: deck.map(\.id))
    }

    /// Registers an empty pile so the renderer draws its slot even before a card
    /// arrives (empty foundations, free cells, empty tableau columns).
    public mutating func ensureZone(_ zone: Zone) {
        if piles[zone] == nil { piles[zone] = [] }
    }

    public mutating func ensureZones(_ zones: [Zone]) {
        for zone in zones { ensureZone(zone) }
    }

    // MARK: - Reading

    public var allZones: [Zone] { Array(piles.keys) }

    public func contents(of zone: Zone) -> [CardID] { piles[zone] ?? [] }

    public func cardList(in zone: Zone) -> [Card] {
        contents(of: zone).compactMap { cards[$0] }
    }

    public func count(in zone: Zone) -> Int { piles[zone]?.count ?? 0 }

    public func isEmpty(_ zone: Zone) -> Bool { count(in: zone) == 0 }

    /// Top of a stack / right-hand end of a row.
    public func top(of zone: Zone) -> Card? {
        guard let id = piles[zone]?.last else { return nil }
        return cards[id]
    }

    public func bottom(of zone: Zone) -> Card? {
        guard let id = piles[zone]?.first else { return nil }
        return cards[id]
    }

    public func zone(of card: CardID) -> Zone? { locations[card] }

    public func card(_ id: CardID) -> Card? { cards[id] }

    public func isFaceUp(_ id: CardID) -> Bool { faceUp.contains(id) }

    public func visibility(of id: CardID) -> Visibility { visibility[id] ?? .hidden }

    /// Index of a card within its pile, counting from the bottom.
    public func position(of id: CardID) -> Int? {
        guard let zone = locations[id] else { return nil }
        return piles[zone]?.firstIndex(of: id)
    }

    /// Zones of a kind, sorted by index then owner, so renderers get a stable order.
    public func zones(ofKind kind: ZoneKind, owner: SeatID? = nil) -> [Zone] {
        piles.keys
            .filter { $0.kind == kind && (owner == nil || $0.owner == owner) }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return (lhs.owner?.rawValue ?? -1) < (rhs.owner?.rawValue ?? -1)
            }
    }

    // MARK: - Mutating

    /// Moves one card to the top of a pile, setting its orientation and
    /// visibility together so the two can never drift apart.
    @discardableResult
    public mutating func move(_ id: CardID, to zone: Zone, facing: Facing) -> Bool {
        guard cards[id] != nil else { return false }
        removeFromCurrentPile(id)
        ensureZone(zone)
        piles[zone]?.append(id)
        locations[id] = zone
        apply(facing, to: id)
        return true
    }

    /// Moves a card without changing which way up it is.
    @discardableResult
    public mutating func move(_ id: CardID, to zone: Zone) -> Bool {
        guard cards[id] != nil else { return false }
        removeFromCurrentPile(id)
        ensureZone(zone)
        piles[zone]?.append(id)
        locations[id] = zone
        return true
    }

    /// Moves a run of cards, preserving their relative order. Used for the
    /// multi-card tableau moves in Klondike, FreeCell and Spider.
    @discardableResult
    public mutating func move(_ ids: [CardID], to zone: Zone) -> Bool {
        for id in ids where cards[id] == nil { return false }
        for id in ids {
            removeFromCurrentPile(id)
        }
        ensureZone(zone)
        piles[zone]?.append(contentsOf: ids)
        for id in ids { locations[id] = zone }
        return true
    }

    /// Draws the top card of a pile into another pile.
    @discardableResult
    public mutating func draw(from source: Zone, to destination: Zone, facing: Facing) -> Card? {
        guard let id = piles[source]?.last, let card = cards[id] else { return nil }
        move(id, to: destination, facing: facing)
        return card
    }

    /// Deals `count` cards one at a time. Returns what was actually dealt, which
    /// may be fewer than requested if the source runs dry.
    @discardableResult
    public mutating func deal(_ count: Int, from source: Zone, to destination: Zone, facing: Facing) -> [Card] {
        var dealt: [Card] = []
        for _ in 0..<count {
            guard let card = draw(from: source, to: destination, facing: facing) else { break }
            dealt.append(card)
        }
        return dealt
    }

    /// Turns a card over, updating visibility to match.
    public mutating func flip(_ id: CardID, faceUp isUp: Bool, privateTo seats: Set<SeatID>? = nil) {
        if isUp {
            apply(seats.map { Facing.privateFaceUp($0) } ?? .faceUp, to: id)
        } else {
            apply(.faceDown, to: id)
        }
    }

    /// Grants a temporary peek without losing the underlying permission.
    /// Peeking twice does not nest: the original permission is what gets restored.
    public mutating func temporarilyReveal(_ id: CardID, to seats: Set<SeatID>) {
        let current = visibility(of: id)
        if case let .temporarilyRevealed(existing, restoring) = current {
            visibility[id] = .temporarilyRevealed(to: existing.union(seats), restoring: restoring)
        } else {
            visibility[id] = .temporarilyRevealed(to: seats, restoring: current)
        }
    }

    /// Ends every outstanding peek. The privacy coordinator calls this before a
    /// device changes hands.
    public mutating func settleTemporaryReveals() {
        let snapshot = visibility
        for (id, value) in snapshot {
            let settled = value.settled
            if settled != value { visibility[id] = settled }
        }
    }

    /// Re-assigns private ownership, for example when a hand is passed in Hearts.
    public mutating func setVisibility(_ value: Visibility, for id: CardID) {
        visibility[id] = value
    }

    public mutating func setVisibility(_ value: Visibility, forAllIn zone: Zone) {
        for id in contents(of: zone) { visibility[id] = value }
    }

    /// Sorts a pile in place with a comparator over cards. Used to keep hands
    /// tidy; never changes visibility.
    public mutating func sort(_ zone: Zone, by areInIncreasingOrder: (Card, Card) -> Bool) {
        guard let ids = piles[zone] else { return }
        let sorted = ids.compactMap { cards[$0] }.sorted(by: areInIncreasingOrder).map(\.id)
        piles[zone] = sorted
    }

    /// Shuffles a pile using the deterministic generator.
    public mutating func shuffle(_ zone: Zone, using generator: inout SeededGenerator) {
        guard var ids = piles[zone] else { return }
        ids.deterministicShuffle(using: &generator)
        piles[zone] = ids
    }

    /// Recycles a discard pile back into the stock, leaving the top discard in
    /// place. Standard behaviour for shedding games that exhaust the stock.
    public mutating func recycleDiscard(into stockZone: Zone,
                                        from discardZone: Zone,
                                        keepingTop: Bool,
                                        using generator: inout SeededGenerator) {
        var ids = contents(of: discardZone)
        guard ids.count > (keepingTop ? 1 : 0) else { return }
        if keepingTop { ids.removeLast() }
        for id in ids {
            move(id, to: stockZone, facing: .faceDown)
        }
        shuffle(stockZone, using: &generator)
    }

    private mutating func removeFromCurrentPile(_ id: CardID) {
        guard let currentZone = locations[id] else { return }
        piles[currentZone]?.removeAll { $0 == id }
    }

    private mutating func apply(_ facing: Facing, to id: CardID) {
        switch facing {
        case .faceUp:
            faceUp.insert(id)
            visibility[id] = .everyone
        case .faceDown:
            faceUp.remove(id)
            visibility[id] = .hidden
        case let .privateFaceUp(seats):
            // The card is face-up from its owner's point of view but the table
            // must not see it — a hand held up to the chest.
            faceUp.insert(id)
            visibility[id] = .seats(seats)
        case .unchanged:
            break
        }
    }

    /// How a card sits when it lands.
    public enum Facing: Hashable, Sendable {
        /// Face-up, everyone sees it.
        case faceUp
        /// Face-down, nobody sees it.
        case faceDown
        /// Held by these seats: they see it, nobody else does.
        case privateFaceUp(Set<SeatID>)
        /// Leave orientation and permission alone.
        case unchanged

        public static func hand(_ seat: SeatID) -> Facing { .privateFaceUp([seat]) }
    }
}

// MARK: - Redaction

public extension Board {
    /// The card as one viewer is entitled to see it.
    func visibleCard(_ id: CardID, for viewer: SeatID?) -> VisibleCard {
        guard let card = cards[id] else { return .concealed(id) }
        return visibility(of: id).canSee(viewer) ? .known(card) : .concealed(id)
    }

    /// A pile as one viewer is entitled to see it.
    func visibleContents(of zone: Zone, for viewer: SeatID?) -> [VisibleCard] {
        contents(of: zone).map { visibleCard($0, for: viewer) }
    }

    /// The whole board, redacted for one viewer.
    ///
    /// This is the only shape the UI ever renders. Passing `nil` — the state the
    /// device is in between players — conceals every private card in the game,
    /// which is what makes backgrounding, screenshots and the pass handshake
    /// safe by construction rather than by remembering to hide things.
    func redacted(for viewer: SeatID?) -> RedactedBoard {
        var visiblePiles: [Zone: [VisibleCard]] = [:]
        visiblePiles.reserveCapacity(piles.count)
        for (zone, ids) in piles {
            visiblePiles[zone] = ids.map { visibleCard($0, for: viewer) }
        }
        return RedactedBoard(viewer: viewer,
                             piles: visiblePiles,
                             faceUp: faceUp,
                             totalCards: cards.count)
    }
}

/// A board with every card the viewer may not see replaced by an anonymous
/// placeholder. There is no way to recover the hidden faces from this value.
public struct RedactedBoard: Hashable, Sendable {
    public let viewer: SeatID?
    public let piles: [Zone: [VisibleCard]]
    public let faceUp: Set<CardID>
    public let totalCards: Int

    public init(viewer: SeatID?, piles: [Zone: [VisibleCard]], faceUp: Set<CardID>, totalCards: Int) {
        self.viewer = viewer
        self.piles = piles
        self.faceUp = faceUp
        self.totalCards = totalCards
    }

    public func contents(of zone: Zone) -> [VisibleCard] { piles[zone] ?? [] }
    public func count(in zone: Zone) -> Int { piles[zone]?.count ?? 0 }
    public func top(of zone: Zone) -> VisibleCard? { piles[zone]?.last }
    public func isFaceUp(_ id: CardID) -> Bool { faceUp.contains(id) }

    public func zones(ofKind kind: ZoneKind, owner: SeatID? = nil) -> [Zone] {
        piles.keys
            .filter { $0.kind == kind && (owner == nil || $0.owner == owner) }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return (lhs.owner?.rawValue ?? -1) < (rhs.owner?.rawValue ?? -1)
            }
    }

    /// Every card face this view exposes. Tests assert against this to prove one
    /// player cannot see another player's hand.
    public var knownCards: Set<CardID> {
        var result: Set<CardID> = []
        for cards in piles.values {
            for card in cards where card.isKnown {
                result.insert(card.id)
            }
        }
        return result
    }
}
