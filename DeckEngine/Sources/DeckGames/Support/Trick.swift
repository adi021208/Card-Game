import Foundation
import DeckCore

/// One card laid to a trick, with the seat that played it.
public struct TrickPlay: Hashable, Codable, Sendable {
    public var seat: SeatID
    public var card: CardID

    public init(seat: SeatID, card: CardID) {
        self.seat = seat
        self.card = card
    }
}

/// Shared trick-taking mechanics: following suit, and working out who won.
///
/// Hearts, Spades and Euchre differ in trump and in what the cards are worth,
/// but they agree completely on these two questions, so they answer them here.
public enum TrickEngine {
    /// The cards a seat may legally play into a trick.
    ///
    /// Follow the led suit if you can. If you cannot, anything goes — subject to
    /// whatever extra restrictions the game layers on top (Hearts' first-trick
    /// rule, its hearts-not-broken rule, and so on).
    public static func followingCards(hand: [Card], ledSuit: Suit?) -> [Card] {
        guard let ledSuit else { return hand }
        let following = hand.filter { $0.suit == ledSuit }
        return following.isEmpty ? hand : following
    }

    public static func canFollow(hand: [Card], ledSuit: Suit) -> Bool {
        hand.contains { $0.suit == ledSuit }
    }

    /// The winner of a completed trick.
    ///
    /// The highest trump wins; with no trump played, the highest card of the led
    /// suit wins. Cards of other suits cannot win, which is what makes a discard
    /// a discard.
    public static func winner(plays: [TrickPlay],
                              cards: [CardID: Card],
                              ledSuit: Suit,
                              trump: Suit?,
                              rankValue: (Card) -> Int = { $0.rank?.rawValue ?? 0 }) -> SeatID? {
        var best: (seat: SeatID, value: Int, isTrump: Bool)?
        for play in plays {
            guard let card = cards[play.card], let suit = card.suit else { continue }
            let isTrump = trump != nil && suit == trump
            guard isTrump || suit == ledSuit else { continue }
            let value = rankValue(card)
            if let current = best {
                if isTrump && !current.isTrump {
                    best = (play.seat, value, true)
                } else if isTrump == current.isTrump && value > current.value {
                    best = (play.seat, value, isTrump)
                }
            } else {
                best = (play.seat, value, isTrump)
            }
        }
        return best?.seat
    }
}
