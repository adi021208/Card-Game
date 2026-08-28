import Foundation

/// How an AI seat picks its move.
///
/// Note the signature: the agent is handed an `Observation`, never a `State`.
/// It is therefore structurally unable to look at an opponent's hand or at the
/// undealt stock, which is how "the AI does not cheat" is enforced rather than
/// merely promised. Injected as a function so `DeckAI` never becomes a
/// dependency of `DeckCore`.
public typealias GameAgentFunction<R: GameRules> = (
    _ observation: R.Observation,
    _ legalActions: [R.Action],
    _ profile: AIProfile,
    _ generator: inout SeededGenerator
) -> R.Action?

/// The type-erased handle every other layer holds onto.
///
/// Navigation, the privacy coordinator, persistence, the daily challenge engine
/// and the whole UI talk to this. None of them knows which game is running,
/// which is the property that makes adding the fiftieth game a module rather
/// than a rewrite.
public protocol GameSessionProtocol: AnyObject {
    var gameID: GameID { get }
    var rulesVersion: Int { get }
    var configuration: GameConfiguration { get }
    var seating: SeatingPlan { get }
    var activeSeat: SeatID? { get }
    var result: GameResult? { get }
    var roundNumber: Int { get }
    var turnCount: Int { get }
    var supportsUndo: Bool { get }
    var canUndo: Bool { get }
    /// Times the player has taken a move back. Survives the undo itself, which
    /// is why it lives on the session rather than in game state.
    var undoCount: Int { get }
    /// Times the player has asked for a hint.
    var hintsUsed: Int { get }
    var elapsedTime: TimeInterval { get }
    /// Ordered action ids applied so far. Seed plus this list reproduces the game.
    var replayLog: [String] { get }

    /// The table as one viewer may see it. `nil` conceals everything private.
    func presentation(for viewer: SeatID?) -> TablePresentation
    /// Legal moves for a seat, as tokens.
    func availableActions(for seat: SeatID) -> [ActionToken]
    /// Applies a move, or throws with the reason it was refused.
    @discardableResult
    func perform(_ token: ActionToken) throws -> [GameEvent]
    /// Runs every automatic step until a decision is required.
    @discardableResult
    func settle() -> [GameEvent]
    /// Takes the events emitted since the last drain.
    func drainEvents() -> [GameEvent]
    /// Picks a move for an AI seat. Returns nil for a human seat or when the
    /// game is over.
    func aiMove(for seat: SeatID) -> ActionToken?
    /// A teaching hint for a seat.
    func hint(for seat: SeatID) -> Hint?
    @discardableResult
    func undo() -> Bool
    /// Versioned checkpoint suitable for writing to disk.
    func checkpoint() throws -> GameCheckpoint
    /// Ends the game as abandoned, producing a result for the statistics engine.
    func abandon() -> GameResult
    /// Re-derives the game from its seed and log and asserts it matches.
    func verifyReplay() throws
    func pauseClock()
    func resumeClock()
    /// Ends every outstanding peek. Called when the device changes hands.
    func settleTemporaryReveals()
}

/// A versioned save of a game in progress.
public struct GameCheckpoint: Codable, Sendable, Hashable {
    /// Bumped when the envelope shape changes.
    public static let currentEnvelopeVersion = 1

    public var envelopeVersion: Int
    public var gameID: GameID
    public var rulesVersion: Int
    public var configuration: GameConfiguration
    /// The encoded `State`, opaque to everything except its own rules type.
    public var stateData: Data
    public var replayLog: [String]
    public var turnCount: Int
    public var savedAt: Date
    /// Seconds of play already accumulated, so a resumed game keeps its clock.
    public var elapsed: TimeInterval

    public init(envelopeVersion: Int = GameCheckpoint.currentEnvelopeVersion,
                gameID: GameID,
                rulesVersion: Int,
                configuration: GameConfiguration,
                stateData: Data,
                replayLog: [String],
                turnCount: Int,
                savedAt: Date = Date(),
                elapsed: TimeInterval = 0) {
        self.envelopeVersion = envelopeVersion
        self.gameID = gameID
        self.rulesVersion = rulesVersion
        self.configuration = configuration
        self.stateData = stateData
        self.replayLog = replayLog
        self.turnCount = turnCount
        self.savedAt = savedAt
        self.elapsed = elapsed
    }
}

public enum GameSessionError: Error, Hashable, Sendable {
    case illegal(IllegalMove)
    case unknownAction(String)
    case checkpointVersionUnsupported(Int)
    case checkpointRulesMismatch(saved: Int, current: Int)
    case checkpointGameMismatch(saved: GameID, current: GameID)
    case checkpointCorrupt
    case replayDiverged(atStep: Int)
}

/// The concrete session for one game's rules.
///
/// Not thread-safe by itself; the app drives it from `GameCoordinator`, which is
/// main-actor isolated.
public final class GameSession<Rules: GameRules>: GameSessionProtocol, @unchecked Sendable {
    public let rules: Rules
    public let configuration: GameConfiguration
    public private(set) var state: Rules.State
    private var generator: SeededGenerator
    /// Undo frames. Bounded so a long solitaire game cannot grow without limit.
    private var undoStack: [UndoFrame] = []
    private let undoLimit = 250
    public private(set) var replayLog: [String] = []
    public private(set) var turnCount: Int = 0
    public private(set) var undoCount: Int = 0
    public private(set) var hintsUsed: Int = 0
    private var clockStartedAt = Date()
    private var accumulatedTime: TimeInterval = 0
    private var clockRunning = true
    /// Events emitted since the last drain, for the presentation layer.
    private var pendingEvents: [GameEvent] = []
    private let agent: GameAgentFunction<Rules>?

    private struct UndoFrame {
        var state: Rules.State
        var generator: SeededGenerator
        var logLength: Int
    }

    /// Starts a new game from a configuration. The seed in the configuration is
    /// the only source of randomness.
    public init(rules: Rules,
                configuration: GameConfiguration,
                agent: GameAgentFunction<Rules>? = nil) {
        self.rules = rules
        self.configuration = configuration
        self.agent = agent
        var generator = SeededGenerator(seed: configuration.seed)
        self.state = rules.setup(configuration: configuration, generator: &generator)
        self.generator = generator
        pendingEvents.append(.gameStarted(seats: configuration.seating.ids))
        pendingEvents.append(contentsOf: runAutomaticSteps())
    }

    private init(rules: Rules,
                 configuration: GameConfiguration,
                 state: Rules.State,
                 generator: SeededGenerator,
                 replayLog: [String],
                 turnCount: Int,
                 elapsed: TimeInterval,
                 agent: GameAgentFunction<Rules>?) {
        self.rules = rules
        self.configuration = configuration
        self.state = state
        self.generator = generator
        self.replayLog = replayLog
        self.turnCount = turnCount
        self.accumulatedTime = elapsed
        self.agent = agent
    }

    /// Restores a game from a checkpoint.
    ///
    /// Validation happens before anything is built, so a save written by rules
    /// that no longer exist is refused rather than half-loaded. The generator is
    /// re-derived by fast-forwarding a fresh one through the replay log, so a
    /// resumed game draws exactly the cards it would have drawn had it never
    /// been interrupted.
    public static func restore(rules: Rules,
                               checkpoint: GameCheckpoint,
                               agent: GameAgentFunction<Rules>? = nil) throws -> GameSession<Rules> {
        guard checkpoint.envelopeVersion <= GameCheckpoint.currentEnvelopeVersion else {
            throw GameSessionError.checkpointVersionUnsupported(checkpoint.envelopeVersion)
        }
        guard checkpoint.gameID == Rules.gameID else {
            throw GameSessionError.checkpointGameMismatch(saved: checkpoint.gameID, current: Rules.gameID)
        }
        guard checkpoint.rulesVersion == Rules.rulesVersion else {
            throw GameSessionError.checkpointRulesMismatch(saved: checkpoint.rulesVersion,
                                                           current: Rules.rulesVersion)
        }
        guard let restoredState = try? JSONDecoder().decode(Rules.State.self, from: checkpoint.stateData) else {
            throw GameSessionError.checkpointCorrupt
        }

        var generator = SeededGenerator(seed: checkpoint.configuration.seed)
        var scratch = rules.setup(configuration: checkpoint.configuration, generator: &generator)
        _ = advanceAll(rules: rules, state: &scratch, generator: &generator)
        for actionID in checkpoint.replayLog {
            guard let action = resolve(actionID: actionID, rules: rules, state: scratch) else { break }
            _ = rules.apply(action, to: &scratch, generator: &generator)
            _ = advanceAll(rules: rules, state: &scratch, generator: &generator)
        }

        return GameSession(rules: rules,
                           configuration: checkpoint.configuration,
                           state: restoredState,
                           generator: generator,
                           replayLog: checkpoint.replayLog,
                           turnCount: checkpoint.turnCount,
                           elapsed: checkpoint.elapsed,
                           agent: agent)
    }

    // MARK: - GameSessionProtocol

    public var gameID: GameID { Rules.gameID }
    public var rulesVersion: Int { Rules.rulesVersion }
    public var seating: SeatingPlan { configuration.seating }
    public var activeSeat: SeatID? { state.activeSeat }
    public var result: GameResult? {
        guard var result = state.finalResult else { return nil }
        result.duration = elapsedTime
        result.metrics[GlobalMetrics.undoCount] = undoCount
        result.metrics[GlobalMetrics.hintsUsed] = hintsUsed
        result.metrics[GlobalMetrics.durationSeconds] = Int(elapsedTime.rounded())
        result.metrics[GlobalMetrics.turns] = turnCount
        return result
    }
    public var roundNumber: Int { state.roundNumber }
    public var supportsUndo: Bool { rules.supportsUndo }
    public var canUndo: Bool { rules.supportsUndo && !undoStack.isEmpty }

    public func presentation(for viewer: SeatID?) -> TablePresentation {
        rules.presentation(of: state, for: viewer, seating: configuration.seating)
    }

    public func availableActions(for seat: SeatID) -> [ActionToken] {
        guard state.finalResult == nil else { return [] }
        return rules.legalActions(in: state, for: seat).map { rules.token(for: $0, in: state) }
    }

    @discardableResult
    public func perform(_ token: ActionToken) throws -> [GameEvent] {
        guard state.finalResult == nil else { throw GameSessionError.illegal(.gameOver) }
        guard let action = rules.decodeAction(id: token.id, in: state) else {
            throw GameSessionError.unknownAction(token.id)
        }
        if let rejection = rules.rejection(for: action, in: state) {
            throw GameSessionError.illegal(rejection)
        }
        pushUndo()
        var events = rules.apply(action, to: &state, generator: &generator)
        replayLog.append(token.id)
        turnCount += 1
        events.append(contentsOf: runAutomaticSteps())
        pendingEvents.append(contentsOf: events)
        return events
    }

    @discardableResult
    public func settle() -> [GameEvent] {
        let events = runAutomaticSteps()
        pendingEvents.append(contentsOf: events)
        return events
    }

    public func drainEvents() -> [GameEvent] {
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        return events
    }

    public func aiMove(for seat: SeatID) -> ActionToken? {
        guard state.finalResult == nil else { return nil }
        guard let controller = configuration.seating[seat]?.controller, controller.isAI else { return nil }
        let legal = rules.legalActions(in: state, for: seat)
        guard let fallback = legal.first else { return nil }
        let profile = AICast.profile(for: controller, difficultyScale: configuration.difficultyScale)
        let observation = rules.observation(of: state, for: seat)
        // Branch the generator so AI deliberation cannot perturb the deal.
        let salt = UInt64(bitPattern: Int64(seat.rawValue &* 1_000_003 &+ turnCount))
        var agentGenerator = generator.branch(salt)
        let chosen: Rules.Action
        if let agent, let picked = agent(observation, legal, profile, &agentGenerator) {
            chosen = picked
        } else {
            chosen = fallback
        }
        return rules.token(for: chosen, in: state)
    }

    public func hint(for seat: SeatID) -> Hint? {
        guard state.finalResult == nil else { return nil }
        guard let hint = rules.hint(for: state, seat: seat) else { return nil }
        hintsUsed += 1
        return hint
    }

    @discardableResult
    public func undo() -> Bool {
        guard rules.supportsUndo, let frame = undoStack.popLast() else { return false }
        state = frame.state
        generator = frame.generator
        if replayLog.count > frame.logLength {
            replayLog.removeLast(replayLog.count - frame.logLength)
        }
        turnCount = max(0, turnCount - 1)
        undoCount += 1
        pendingEvents.append(.moveUndone)
        return true
    }

    public func checkpoint() throws -> GameCheckpoint {
        let data = try JSONEncoder().encode(state)
        return GameCheckpoint(gameID: Rules.gameID,
                              rulesVersion: Rules.rulesVersion,
                              configuration: configuration,
                              stateData: data,
                              replayLog: replayLog,
                              turnCount: turnCount,
                              elapsed: elapsedTime)
    }

    public func abandon() -> GameResult {
        if let existing = state.finalResult { return existing }
        return GameResult(duration: elapsedTime,
                          turnCount: turnCount,
                          roundCount: state.roundNumber)
    }

    public var elapsedTime: TimeInterval {
        clockRunning ? accumulatedTime + Date().timeIntervalSince(clockStartedAt) : accumulatedTime
    }

    /// Stops the clock when the app leaves the foreground, so time spent off
    /// screen never counts against a speed challenge.
    public func pauseClock() {
        guard clockRunning else { return }
        accumulatedTime += Date().timeIntervalSince(clockStartedAt)
        clockRunning = false
    }

    public func resumeClock() {
        guard !clockRunning else { return }
        clockStartedAt = Date()
        clockRunning = true
    }

    public func settleTemporaryReveals() {
        state.board.settleTemporaryReveals()
    }

    // MARK: - Replay verification

    /// Replays the stored log from the seed and checks it lands on the same
    /// state. Backs the daily-challenge integrity check and the replay tests.
    public func verifyReplay() throws {
        var generator = SeededGenerator(seed: configuration.seed)
        var scratch = rules.setup(configuration: configuration, generator: &generator)
        _ = GameSession.advanceAll(rules: rules, state: &scratch, generator: &generator)
        for (index, actionID) in replayLog.enumerated() {
            guard let action = GameSession.resolve(actionID: actionID, rules: rules, state: scratch) else {
                throw GameSessionError.replayDiverged(atStep: index)
            }
            _ = rules.apply(action, to: &scratch, generator: &generator)
            _ = GameSession.advanceAll(rules: rules, state: &scratch, generator: &generator)
        }
        guard scratch == state else {
            throw GameSessionError.replayDiverged(atStep: replayLog.count)
        }
    }

    // MARK: - Internals

    /// Decodes a stored action id back into a move. Token ids are stable,
    /// seat-qualified and self-describing: they *are* the replay format.
    private static func resolve(actionID: String, rules: Rules, state: Rules.State) -> Rules.Action? {
        rules.decodeAction(id: actionID, in: state)
    }

    @discardableResult
    private static func advanceAll(rules: Rules,
                                   state: inout Rules.State,
                                   generator: inout SeededGenerator) -> [GameEvent] {
        var produced: [GameEvent] = []
        // Bounded so a rules bug cannot hang the app; 512 automatic steps is far
        // more than any game in the library needs between two decisions.
        for _ in 0..<512 {
            let events = rules.advanceAutomatically(&state, generator: &generator)
            if events.isEmpty { break }
            produced.append(contentsOf: events)
        }
        return produced
    }

    private func runAutomaticSteps() -> [GameEvent] {
        GameSession.advanceAll(rules: rules, state: &state, generator: &generator)
    }

    private func pushUndo() {
        guard rules.supportsUndo else { return }
        undoStack.append(UndoFrame(state: state, generator: generator, logLength: replayLog.count))
        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
    }
}
