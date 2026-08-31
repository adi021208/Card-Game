import Foundation

/// Describes the physical stack of cards a game is played with.
///
/// Games declare a configuration rather than building card arrays by hand, so a
/// two-deck game, a 32-card Euchre deck and a 54-card Crazy Eights deck all come
/// out of the same builder with stable identifiers.
public struct DeckConfiguration: Hashable, Codable, Sendable {
    /// How many complete packs are shuffled together.
    public var packs: Int
    /// Ranks present in each pack, low to high.
    public var ranks: [Rank]
    /// Suits present in each pack.
    public var suits: [Suit]
    /// Jokers added per pack.
    public var jokersPerPack: [JokerColour]

    public init(packs: Int = 1,
                ranks: [Rank] = Rank.allCases,
                suits: [Suit] = Suit.allCases,
                jokersPerPack: [JokerColour] = []) {
        self.packs = max(1, packs)
        self.ranks = ranks
        self.suits = suits
        self.jokersPerPack = jokersPerPack
    }

    public var cardsPerPack: Int { ranks.count * suits.count + jokersPerPack.count }
    public var totalCards: Int { cardsPerPack * packs }

    /// Builds the ordered, unshuffled stack. Ordering is deterministic: pack,
    /// then suit, then rank, then jokers.
    public func build() -> [Card] {
        var cards: [Card] = []
        cards.reserveCapacity(totalCards)
        for pack in 0..<packs {
            for suit in suits {
                for rank in ranks {
                    cards.append(Card(suit, rank, deckIndex: pack))
                }
            }
            for joker in jokersPerPack {
                cards.append(Card(joker: joker, deckIndex: pack))
            }
        }
        return cards
    }

    // MARK: - Standard configurations

    /// 52 cards. Poker, Hearts, Spades, Klondike, FreeCell, Gin Rummy, War.
    public static let standard52 = DeckConfiguration()

    /// 54 cards. Crazy Eights and other shedding games that use jokers as wilds.
    public static let standard54 = DeckConfiguration(jokersPerPack: [.red, .black])

    /// 32 cards, sevens up. Piquet-style deck used by some Euchre house rules.
    public static let piquet32 = DeckConfiguration(ranks: [.seven, .eight, .nine, .ten, .jack, .queen, .king, .ace])

    /// 24 cards, nines up. The standard Euchre deck.
    public static let euchre24 = DeckConfiguration(ranks: [.nine, .ten, .jack, .queen, .king, .ace])

    /// 36 cards, sixes up.
    public static let short36 = DeckConfiguration(ranks: [.six, .seven, .eight, .nine, .ten, .jack, .queen, .king, .ace])

    /// Two packs, 104 cards. Spider (four-suit) and two-deck Rummy.
    public static let double52 = DeckConfiguration(packs: 2)

    /// Spider dealt with a single suit repeated eight times is modelled as eight
    /// packs restricted to spades: 8 x 13 = 104 cards, all spades.
    public static func spider(suitCount: Int) -> DeckConfiguration {
        switch suitCount {
        case 1: return DeckConfiguration(packs: 8, suits: [.spades])
        case 2: return DeckConfiguration(packs: 4, suits: [.spades, .hearts])
        default: return DeckConfiguration(packs: 2, suits: Suit.allCases)
        }
    }

    /// Removes specific ranks, for games that strip the deck to fit the player count.
    public func removingRanks(_ removed: Set<Rank>) -> DeckConfiguration {
        var copy = self
        copy.ranks = ranks.filter { !removed.contains($0) }
        return copy
    }
}
