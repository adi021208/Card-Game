import Foundation

/// State a game keeps between moves. Codable so it can be checkpointed, and
/// Equatable so replay verification can assert the reconstruction matched.
public protocol GameStateProtocol: Codable, Sendable, Equatable {
    /// The physical table. Settable so the session can end outstanding peeks
    /// when the device changes hands, without the privacy layer needing to
    /// reach inside a game's private state.
    var board: Board { get set }
    /// Whose turn it is; `nil` when the game is waiting on nothing (finished, or
    /// resolving an automatic step).
    var activeSeat: SeatID? { get }
    /// Round/hand/deal counter, starting at 1.
    var roundNumber: Int { get }
    /// Set once the game has finished.
    var finalResult: GameResult? { get }
}

/// One game's rules.
///
/// The shape is a reducer: `apply` is the only thing that changes state, it is
/// pure apart from the injected generator, and it reports what happened as
/// events. That is what makes games testable head-to-head, replayable from a
/// seed, and safe to checkpoint mid-hand.
public protocol GameRules: Sendable {
    associatedtype State: GameStateProtocol
    /// The game's own action type. Strongly typed, never leaves the engine.
    associatedtype Action: Hashable, Sendable
    /// What an AI is allowed to know. Built by `observation(of:for:)`, which is
    /// the *only* way an AI receives information — it is structurally incapable
    /// of reading the full state, so it cannot cheat.
    associatedtype Observation: Sendable

    static var gameID: GameID { get }
    /// Bump when a rules change would alter the outcome of a stored game.
    static var rulesVersion: Int { get }

    /// Deals the opening position. Every random decision goes through `generator`.
    func setup(configuration: GameConfiguration, generator: inout SeededGenerator) -> State

    /// Every move `seat` may legally make right now, in a stable order.
    func legalActions(in state: State, for seat: SeatID) -> [Action]

    /// Applies a move. Callers must have validated it via `legalActions`;
    /// implementations still assert rather than corrupting state.
    func apply(_ action: Action, to state: inout State, generator: inout SeededGenerator) -> [GameEvent]

    /// Explains why a move is not available. Returning `nil` means it is legal.
    func rejection(for action: Action, in state: State) -> IllegalMove?

    /// Encodes a move as a shared token. The token's `id` is the replay format,
    /// so it must be stable across launches and unique within a position.
    func token(for action: Action, in state: State) -> ActionToken

    /// Decodes a token id back into a move.
    ///
    /// Decoding from the id rather than searching the legal-move list is what
    /// lets a game accept a move the enumeration never listed — a poker raise to
    /// an arbitrary amount, say — and still replay it exactly.
    func decodeAction(id: String, in state: State) -> Action?

    /// What the AI in `seat` gets to see.
    func observation(of state: State, for seat: SeatID) -> Observation

    /// The table, redacted for one viewer.
    func presentation(of state: State, for viewer: SeatID?, seating: SeatingPlan) -> TablePresentation

    /// Advances any automatic step that needs no decision (dealing the flop,
    /// collecting a completed trick, auto-playing a forced card). Returns the
    /// events it produced; the session loops until it returns empty.
    func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent]

    /// A teaching hint for `seat` that explains *why*, never just "play this".
    func hint(for state: State, seat: SeatID) -> Hint?

    /// Undo support. Games that allow undo (the solitaires) return true.
    var supportsUndo: Bool { get }
}

public extension GameRules {
    var supportsUndo: Bool { false }

    func action(for token: ActionToken, in state: State) -> Action? {
        decodeAction(id: token.id, in: state)
    }

    func hint(for state: State, seat: SeatID) -> Hint? { nil }

    func advanceAutomatically(_ state: inout State, generator: inout SeededGenerator) -> [GameEvent] { [] }
}

/// A hint. Always carries the reasoning, because the point is to teach the game,
/// not to play it for the player.
public struct Hint: Hashable, Sendable {
    /// Localisation key for the explanation.
    public var messageKey: String
    public var arguments: [String]
    /// Untranslated fallback used in tests and logs.
    public var english: String
    /// Cards the hint is drawing attention to. May be several — a good hint
    /// shows the shape of the choice rather than picking for the player.
    public var cards: [CardID]
    /// The move, when the player asks to be shown outright.
    public var suggestedAction: ActionToken?

    public init(messageKey: String,
                arguments: [String] = [],
                english: String,
                cards: [CardID] = [],
                suggestedAction: ActionToken? = nil) {
        self.messageKey = messageKey
        self.arguments = arguments
        self.english = english
        self.cards = cards
        self.suggestedAction = suggestedAction
    }
}
