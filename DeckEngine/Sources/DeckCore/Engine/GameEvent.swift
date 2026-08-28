import Foundation

/// Something the engine did, published for other layers to react to.
///
/// Animation, audio and haptics subscribe to these; none of them ever inspects
/// game state directly. A new game emits the same vocabulary and immediately
/// gets the whole feel of the app for free.
public enum GameEvent: Hashable, Sendable {
    case gameStarted(seats: [SeatID])
    case roundStarted(number: Int)
    case handsDealt(counts: [SeatID: Int])
    case cardDealt(card: CardID, to: Zone, faceUp: Bool)
    case cardDrawn(card: CardID, by: SeatID, from: Zone)
    case cardPlayed(card: CardID, by: SeatID, to: Zone)
    case cardsPlayed(cards: [CardID], by: SeatID, to: Zone)
    case cardDiscarded(card: CardID, by: SeatID)
    case cardsMoved(cards: [CardID], from: Zone, to: Zone)
    case cardFlipped(card: CardID, faceUp: Bool)
    case cardsRevealed(cards: [CardID], to: Set<SeatID>)
    case deckShuffled(zone: Zone)
    case deckRecycled(from: Zone, to: Zone)
    case turnChanged(from: SeatID?, to: SeatID)
    case turnSkipped(seat: SeatID)
    case directionReversed
    case suitChosen(Suit, by: SeatID)
    case trickCompleted(winner: SeatID, cards: [CardID])
    case betPlaced(seat: SeatID, amount: Int, kind: ActionKind)
    case potAwarded(seat: SeatID, amount: Int)
    case showdown(revealed: [SeatID: [CardID]])
    case bidMade(seat: SeatID, value: Int)
    case claimMade(seat: SeatID, claim: String)
    case challengeResolved(challenger: SeatID, target: SeatID, claimWasTrue: Bool)
    case scoreChanged(seat: SeatID, delta: Int, total: Int)
    case roundEnded(scores: [SeatID: Int])
    case playerOut(seat: SeatID, place: Int)
    case foundationCompleted(zone: Zone)
    case moveRejected(IllegalMove)
    case moveUndone
    case gameEnded(GameResult)
    /// A free-form marker games use for their own signature moments
    /// ("shot the moon", "gin", "royal flush"). Consumed by achievements,
    /// statistics and the result screen.
    case highlight(code: String, seat: SeatID?, value: Int?)

    /// Whether this event should interrupt the pass handshake. Anything that
    /// reveals a card must not fire while the device is between players.
    public var revealsCards: Bool {
        switch self {
        case .cardDealt, .cardDrawn, .cardPlayed, .cardsPlayed, .cardDiscarded,
             .cardFlipped, .cardsRevealed, .showdown:
            return true
        default:
            return false
        }
    }
}
