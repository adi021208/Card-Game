import Foundation

/// How a pile is arranged on the table.
public enum PileStyle: Hashable, Codable, Sendable {
    /// Overlapping arc. Hands.
    case fan
    /// Left-to-right row with a fixed overlap.
    case row(overlap: Double)
    /// One on top of another, only the top readable.
    case stack
    /// Downward cascade with the rank corners showing. Solitaire tableau.
    case cascade
    /// A single card slot.
    case single
    /// Fan, but rendered small and face-down. Opponent hands.
    case opponentFan
}

/// Where a pile sits in the table composition.
///
/// Deliberately abstract: the renderer maps these onto the actual geometry for
/// the current device, orientation and Dynamic Type size, so a game never
/// hard-codes a point value.
public enum SlotAnchor: Hashable, Codable, Sendable {
    /// The device holder's own hand, along the bottom edge.
    case ownHand
    /// An opponent, placed around the table by seat offset from the viewer.
    case opponent(offset: Int)
    /// The middle of the table, laid out left to right.
    case centre(order: Int)
    /// A column in a grid, row-major. Solitaire.
    case grid(row: Int, column: Int)
    /// Pinned to a corner, for stock and discard piles.
    case corner(Corner)

    public enum Corner: String, Codable, Sendable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }
}

/// One pile as the renderer should draw it.
public struct TableSlot: Hashable, Codable, Sendable, Identifiable {
    public var zone: Zone
    public var style: PileStyle
    public var anchor: SlotAnchor
    /// Optional label, e.g. "Foundations", "Free cells".
    public var titleKey: String?
    /// Shown when the pile is empty, e.g. "Drop an Ace here".
    public var emptyHintKey: String?
    /// Whether tapping the empty slot is itself a move (turning the stock over).
    public var acceptsDrop: Bool
    /// Relative visual weight, used to size the slot against its neighbours.
    public var prominence: Double

    public var id: Zone { zone }

    public init(zone: Zone,
                style: PileStyle,
                anchor: SlotAnchor,
                titleKey: String? = nil,
                emptyHintKey: String? = nil,
                acceptsDrop: Bool = false,
                prominence: Double = 1.0) {
        self.zone = zone
        self.style = style
        self.anchor = anchor
        self.titleKey = titleKey
        self.emptyHintKey = emptyHintKey
        self.acceptsDrop = acceptsDrop
        self.prominence = prominence
    }
}

/// A short line of state the table shows, such as "Hearts led", "Pot 240",
/// "Trump: Spades". Games emit these instead of the renderer knowing about any
/// particular game's concepts.
public struct TableCallout: Hashable, Codable, Sendable, Identifiable {
    public enum Emphasis: String, Codable, Sendable {
        /// The single most important thing on screen.
        case primary
        /// Supporting state.
        case secondary
        /// A warning or a pressure state.
        case alert
    }

    public var id: String
    public var labelKey: String
    public var arguments: [String]
    public var emphasis: Emphasis
    /// A suit to draw alongside the text, when the callout is about a suit.
    public var suit: Suit?

    public init(id: String,
                labelKey: String,
                arguments: [String] = [],
                emphasis: Emphasis = .secondary,
                suit: Suit? = nil) {
        self.id = id
        self.labelKey = labelKey
        self.arguments = arguments
        self.emphasis = emphasis
        self.suit = suit
    }
}

/// A seat as shown on the table edge.
public struct SeatStatus: Hashable, Codable, Sendable, Identifiable {
    public var seat: SeatID
    public var displayName: String
    public var avatarID: String
    /// Primary number: chips, score, tricks — whatever the game counts.
    public var score: Int?
    /// Label for that number.
    public var scoreLabelKey: String?
    public var cardCount: Int
    /// Chips currently in front of the seat on this betting street.
    public var wager: Int?
    public var isActive: Bool
    public var isDealer: Bool
    public var isHuman: Bool
    /// Short state word: "folded", "all in", "passed", "out".
    public var stateKey: String?
    public var team: Int?

    public var id: SeatID { seat }

    public init(seat: SeatID,
                displayName: String,
                avatarID: String,
                score: Int? = nil,
                scoreLabelKey: String? = nil,
                cardCount: Int = 0,
                wager: Int? = nil,
                isActive: Bool = false,
                isDealer: Bool = false,
                isHuman: Bool = false,
                stateKey: String? = nil,
                team: Int? = nil) {
        self.seat = seat
        self.displayName = displayName
        self.avatarID = avatarID
        self.score = score
        self.scoreLabelKey = scoreLabelKey
        self.cardCount = cardCount
        self.wager = wager
        self.isActive = isActive
        self.isDealer = isDealer
        self.isHuman = isHuman
        self.stateKey = stateKey
        self.team = team
    }
}

/// The complete, already-redacted description of the table for one viewer.
///
/// The UI renders exactly this and nothing else. It contains no `Card` the
/// viewer is not allowed to see, no reference to game state, and no way to ask
/// for more. Everything the player is offered — every legal move — is in
/// `actions`, so the UI cannot invent a move the rules would refuse.
public struct TablePresentation: Hashable, Sendable {
    public var gameID: GameID
    /// The seat whose eyes we are behind. `nil` between players.
    public var viewer: SeatID?
    public var board: RedactedBoard
    public var slots: [TableSlot]
    public var seats: [SeatStatus]
    public var callouts: [TableCallout]
    /// Moves the viewer may make right now. Empty when it is not their turn.
    public var actions: [ActionToken]
    /// Cards the viewer may pick up, as a fast lookup for the hand renderer.
    public var playableCards: Set<CardID>
    /// Whose turn it is.
    public var activeSeat: SeatID?
    /// Round/hand number, shown in the status bar and used by "Continue".
    public var roundNumber: Int
    /// Headline for the current phase: "Pre-flop", "Passing", "Trick 4".
    public var phaseKey: String
    public var phaseArguments: [String]
    /// Set once the game is over.
    public var result: GameResult?

    public init(gameID: GameID,
                viewer: SeatID?,
                board: RedactedBoard,
                slots: [TableSlot],
                seats: [SeatStatus],
                callouts: [TableCallout] = [],
                actions: [ActionToken] = [],
                playableCards: Set<CardID> = [],
                activeSeat: SeatID? = nil,
                roundNumber: Int = 1,
                phaseKey: String = "",
                phaseArguments: [String] = [],
                result: GameResult? = nil) {
        self.gameID = gameID
        self.viewer = viewer
        self.board = board
        self.slots = slots
        self.seats = seats
        self.callouts = callouts
        self.actions = actions
        self.playableCards = playableCards
        self.activeSeat = activeSeat
        self.roundNumber = roundNumber
        self.phaseKey = phaseKey
        self.phaseArguments = phaseArguments
        self.result = result
    }

    /// Actions attached to a particular card, for tap and drag handling.
    public func actions(for card: CardID) -> [ActionToken] {
        actions.filter { $0.cards.contains(card) }
    }

    /// Moves that are not about a specific card: check, fold, draw, pass.
    public var barActions: [ActionToken] {
        actions.filter { $0.cards.isEmpty }
    }

    public var isFinished: Bool { result != nil }
}
