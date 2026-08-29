import SwiftUI
import Observation
import DeckCore
import DeckProgression

/// Runs one game.
///
/// This is where the engine, the privacy coordinator, the AI, persistence and
/// the feedback layers meet. It owns no rules of its own: every question about
/// what is legal, what happens next and who may see what is answered by the
/// engine, and this only sequences the answers and turns events into sound,
/// haptics and animation.
@MainActor
@Observable
public final class GameCoordinator {

    // MARK: - Published state

    /// The table as the current viewer is entitled to see it. Recomputed
    /// whenever anything changes, always through `session.presentation(for:)`,
    /// which is what keeps the redaction on the only path to the screen.
    public private(set) var presentation: TablePresentation
    public private(set) var privacyPhase: PrivacyPhase
    /// Cards the player has picked out but not yet committed.
    public private(set) var selection: [CardID] = []
    /// The reason the last attempted move was refused, for one beat.
    public private(set) var rejection: IllegalMove?
    public private(set) var hint: Hint?
    public private(set) var isThinking = false
    public private(set) var result: GameResult?
    public private(set) var progressChange: ProgressChange?
    public private(set) var challengeOutcome: ChallengeOutcome?
    /// Set while cards are gathering for the hand-off, so the table can play the
    /// seal animation.
    public private(set) var isSealing = false
    /// Set when the game is a daily challenge, so the objective can be shown.
    public let challenge: DailyChallenge?

    // MARK: - Dependencies

    private let session: GameSessionProtocol
    private var privacy: PrivacyCoordinator
    private let progress: ProgressStore
    private let settings: SettingsState
    private var attempt: ChallengeAttempt?
    /// Both are cancelled from `deinit`, which is nonisolated. Cancelling a
    /// task handle is safe from any thread; both are assigned only on the
    /// main actor.
    private nonisolated(unsafe) var aiTask: Task<Void, Never>?
    private nonisolated(unsafe) var autoSaveTask: Task<Void, Never>?
    private let cardBackID: String

    /// The seat the person holding the device is playing.
    public private(set) var localSeat: SeatID

    public init(session: GameSessionProtocol,
                progress: ProgressStore,
                challenge: DailyChallenge? = nil,
                attempt: ChallengeAttempt? = nil) {
        self.session = session
        self.progress = progress
        self.settings = progress.settings
        self.challenge = challenge
        self.attempt = attempt
        self.cardBackID = progress.collection.selectedCardBack

        let seating = session.seating
        let startingSeat = session.activeSeat ?? seating.ids.first ?? SeatID(0)
        var coordinator = PrivacyCoordinator(seating: seating, startingSeat: startingSeat)
        coordinator.setReducedMotion(progress.settings.reduceMotion)
        self.privacy = coordinator
        self.privacyPhase = coordinator.phase
        self.localSeat = coordinator.viewer ?? startingSeat
        self.presentation = session.presentation(for: coordinator.viewer)

        Haptics.shared.isEnabled = progress.settings.hapticsEnabled
        AudioService.shared.isEnabled = progress.settings.soundEnabled
        AudioService.shared.packID = progress.collection.selectedSoundPack

        drainAndReact()
        scheduleAIIfNeeded()
        startAutoSave()
    }

    deinit {
        aiTask?.cancel()
        autoSaveTask?.cancel()
    }

    // MARK: - Derived

    public var seating: SeatingPlan { session.seating }
    public var gameID: GameID { session.gameID }
    public var acceptsInput: Bool { privacy.acceptsInput && result == nil }
    public var canUndo: Bool { session.canUndo && acceptsInput }
    public var isPassAndPlay: Bool { seating.isPassAndPlay }
    public var handoffSeatName: String {
        guard let seat = privacyPhase.pendingSeat else { return "" }
        return privacy.displayName(of: seat)
    }
    public var cardBack: String { cardBackID }
    public var elapsed: TimeInterval { session.elapsedTime }

    /// Whether the current viewer is the one who should be acting.
    public var isLocalTurn: Bool {
        guard let active = session.activeSeat else { return false }
        // Simultaneous games have no active seat; anybody may move.
        return active == privacy.viewer
    }

    // MARK: - Input

    /// A tap on a card. Resolves to a move when exactly one fits, and otherwise
    /// builds a selection the player then commits.
    public func tapCard(_ id: CardID) {
        guard acceptsInput else { return }
        rejection = nil
        let candidates = presentation.actions(for: id)

        switch candidates.count {
        case 0:
            // Not a legal move — unless it is part of a selection the game
            // gathers itself (passing three in Hearts, laying in Cheat).
            if presentation.playableCards.contains(id) {
                toggleSelection(id)
            } else {
                refuse(.noSuchAction)
            }
        case 1:
            perform(candidates[0])
        default:
            // Several moves share this card (an eight and four suits, or a card
            // that can go to two piles). The screen presents the choice.
            toggleSelection(id)
        }
    }

    public func toggleSelection(_ id: CardID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
            Haptics.shared.tap(.light)
        } else {
            selection.append(id)
            Haptics.shared.tap(.pickUp)
            AudioService.shared.play(.cardPickUp)
        }
    }

    public func clearSelection() {
        selection.removeAll()
    }

    /// Moves offered for the cards currently selected.
    public func actionsForSelection() -> [ActionToken] {
        guard !selection.isEmpty else { return [] }
        let chosen = Set(selection)
        return presentation.actions.filter { Set($0.cards) == chosen }
    }

    /// Moves that involve one specific card, for the picker.
    public func actions(for card: CardID) -> [ActionToken] {
        presentation.actions(for: card)
    }

    public func perform(_ token: ActionToken) {
        guard acceptsInput else { return }
        do {
            let events = try session.perform(token)
            selection.removeAll()
            hint = nil
            rejection = nil
            react(to: events)
            refresh()
            handleTurnChange()
        } catch let GameSessionError.illegal(reason) {
            refuse(reason)
        } catch {
            refuse(.noSuchAction)
        }
    }

    public func undo() {
        guard session.undo() else { return }
        selection.removeAll()
        hint = nil
        Haptics.shared.tap(.light)
        AudioService.shared.play(.cardFlip)
        refresh()
    }

    public func requestHint() {
        guard let seat = privacy.viewer else { return }
        // Hints are off during a competitive challenge unless the player has
        // deliberately turned them on.
        if challenge != nil && !settings.allowHintsInChallenges { return }
        hint = session.hint(for: seat)
        if hint != nil { Haptics.shared.tap(.light) }
    }

    public func dismissHint() { hint = nil }

    // MARK: - Pass & Play

    /// The incoming player has confirmed they are the only one looking.
    public func confirmReveal() {
        let directives = privacy.confirmReveal()
        apply(directives)
    }

    /// Called when the seal animation finishes.
    public func sealingFinished() {
        privacy.sealingCompleted()
        isSealing = false
        privacyPhase = privacy.phase
        refresh()
    }

    /// Called when the app is about to leave the foreground, is being
    /// screenshotted, or enters the app switcher.
    public func shieldForBackground() {
        session.pauseClock()
        apply(privacy.shield())
        saveCheckpoint()
    }

    public func returnedToForeground() {
        session.resumeClock()
        refresh()
    }

    private func apply(_ directives: [PrivacyDirective]) {
        for directive in directives {
            switch directive {
            case .clearInteraction:
                selection.removeAll()
                hint = nil
                aiTask?.cancel()
            case .settleReveals:
                // Anything a player was shown stops being visible before the
                // device moves, in the engine's own state rather than on screen.
                session.settleTemporaryReveals()
            case .sealCards:
                isSealing = true
                Haptics.shared.tap(.handoff)
                AudioService.shared.play(.handoff)
            case .presentHandoff:
                isSealing = false
            case let .revealHand(seat, _):
                localSeat = seat
                AudioService.shared.play(.reveal)
                Haptics.shared.tap(.turnChange)
            case let .resumePlay(seat):
                localSeat = seat
            case .conclude:
                break
            }
        }
        privacyPhase = privacy.phase
        refresh()

        // The reveal animation finishes on its own clock, then play resumes.
        if case let .revealing(seat) = privacy.phase {
            let duration = privacy.revealDuration
            Task { @MainActor in
                if duration > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                }
                self.privacy.revealCompleted()
                self.privacyPhase = self.privacy.phase
                self.localSeat = seat
                self.refresh()
                self.scheduleAIIfNeeded()
            }
        } else {
            scheduleAIIfNeeded()
        }
    }

    // MARK: - Turn flow

    private func handleTurnChange() {
        guard result == nil else { return }
        guard let active = session.activeSeat else {
            // Simultaneous game: nobody's turn in particular.
            scheduleAIIfNeeded()
            return
        }
        let directives = privacy.turnPassed(to: active)
        if directives.isEmpty {
            privacyPhase = privacy.phase
            scheduleAIIfNeeded()
        } else {
            apply(directives)
        }
        saveCheckpoint()
    }

    /// Lets the AI take its turn, after a pause proportional to its personality.
    private func scheduleAIIfNeeded() {
        aiTask?.cancel()
        guard result == nil else { return }
        guard let active = session.activeSeat else { return }
        guard let seat = seating[active], !seat.isHuman else {
            isThinking = false
            return
        }
        // The device must be with somebody before an AI move is animated, or the
        // player who just passed would watch the next hand being played.
        guard privacy.phase.acceptsInput || !isPassAndPlay else { return }

        isThinking = true
        let delay = thinkingTime(for: seat)
        aiTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.takeAIMove(for: active)
        }
    }

    private func thinkingTime(for seat: Seat) -> TimeInterval {
        guard case let .ai(personalityID, difficulty) = seat.controller else { return 0.4 }
        let profile = AICast.personality(personalityID).profile
        // A deliberate personality takes longer, a reckless one snaps.
        var seconds = 0.35 + profile.reactionSpeed * 0.55
        if difficulty == .expert { seconds += 0.15 }
        if settings.reduceMotion { seconds = min(seconds, 0.3) }
        return seconds
    }

    private func takeAIMove(for seat: SeatID) {
        isThinking = false
        guard let token = session.aiMove(for: seat) else {
            // No legal move: let the engine settle and move on.
            react(to: session.settle())
            refresh()
            handleTurnChange()
            return
        }
        do {
            let events = try session.perform(token)
            react(to: events)
            refresh()
            handleTurnChange()
        } catch {
            // An AI cannot produce an illegal move by construction, but if the
            // rules ever change under a saved game, drop the turn rather than
            // wedging the table.
            react(to: session.settle())
            refresh()
            handleTurnChange()
        }
    }

    // MARK: - Reacting to the engine

    private func drainAndReact() {
        react(to: session.drainEvents())
        refresh()
    }

    /// Turns engine events into sound, haptics and one-shot UI state.
    ///
    /// Nothing here inspects game state: every game emits the same vocabulary,
    /// so a new game gets the app's whole feel without touching this function.
    private func react(to events: [GameEvent]) {
        for event in events {
            switch event {
            case .cardDealt, .cardDrawn:
                AudioService.shared.play(.cardDeal)
                Haptics.shared.tap(.deal)
            case .cardPlayed, .cardsPlayed, .cardDiscarded, .cardsMoved:
                AudioService.shared.play(.cardPlace)
                Haptics.shared.tap(.place)
            case .cardFlipped, .cardsRevealed:
                AudioService.shared.play(.cardFlip)
            case .deckShuffled, .deckRecycled, .handsDealt:
                AudioService.shared.play(.shuffle)
                Haptics.shared.tap(.shuffle)
            case .trickCompleted, .potAwarded:
                AudioService.shared.play(.collect)
                Haptics.shared.tap(.collect)
            case .betPlaced:
                AudioService.shared.play(.chip)
            case .turnChanged:
                AudioService.shared.play(.turnChange)
            case .moveRejected(let reason):
                refuse(reason)
            case .gameEnded(let finished):
                finish(with: finished)
            case .highlight:
                AudioService.shared.play(.stamp)
                Haptics.shared.tap(.light)
            case .roundStarted:
                AudioService.shared.play(.shuffle)
            default:
                break
            }
        }
    }

    private func refuse(_ reason: IllegalMove) {
        rejection = reason
        selection.removeAll()
        Haptics.shared.tap(.rejected)
        AudioService.shared.play(.invalid)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if self?.rejection == reason { self?.rejection = nil }
        }
    }

    private func refresh() {
        presentation = session.presentation(for: privacy.viewer)
        privacyPhase = privacy.phase
    }

    // MARK: - Finishing

    private func finish(with finished: GameResult) {
        aiTask?.cancel()
        autoSaveTask?.cancel()
        session.pauseClock()
        let final = session.result ?? finished
        result = final
        _ = privacy.conclude()
        privacyPhase = privacy.phase
        // Results are public: everybody at the table sees the same screen.
        presentation = session.presentation(for: localSeat)

        let outcome = final.outcome(for: localSeat)
        AudioService.shared.play(outcome == .win ? .victory : .defeat)
        Haptics.shared.tap(outcome == .win ? .victory : .defeat)

        progressChange = progress.recordFinishedGame(result: final,
                                                     gameID: session.gameID,
                                                     seat: localSeat,
                                                     configuration: session.configuration,
                                                     replayLog: session.replayLog)

        if let challenge, let attempt {
            let succeeded = ChallengeLedger.evaluate(objective: challenge.objective,
                                                     result: final,
                                                     seat: localSeat,
                                                     bossID: challenge.bossID)
            challengeOutcome = progress.recordChallenge(attempt: attempt,
                                                        challenge: challenge,
                                                        result: final,
                                                        seat: localSeat,
                                                        succeeded: succeeded,
                                                        replayLog: session.replayLog)
            if succeeded {
                AudioService.shared.play(.achievement)
                Haptics.shared.tap(.streak)
            }
        }

        if let change = progressChange, !change.isEmpty {
            AudioService.shared.play(.achievement)
            Haptics.shared.tap(.achievement)
        }
        progress.clearSavedGame()
    }

    /// Ends the game early, recording it as abandoned so the statistics stay honest.
    public func abandon() {
        aiTask?.cancel()
        autoSaveTask?.cancel()
        guard result == nil else { return }
        let abandoned = session.abandon()
        progress.recordFinishedGame(result: abandoned,
                                    gameID: session.gameID,
                                    seat: localSeat,
                                    configuration: session.configuration,
                                    replayLog: session.replayLog)
        progress.clearSavedGame()
    }

    // MARK: - Saving

    /// Writes a checkpoint after every move, and on a timer, so a game survives
    /// the app being killed at any point.
    private func startAutoSave() {
        autoSaveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, self.result == nil else { return }
                self.saveCheckpoint()
            }
        }
    }

    public func saveCheckpoint() {
        guard result == nil else { return }
        guard let checkpoint = try? session.checkpoint() else { return }
        // The viewer is stored too, so a resumed Pass & Play game opens on the
        // pass screen for the right person rather than showing a hand to
        // whoever picks the phone up.
        progress.saveGame(checkpoint, viewerSeat: privacy.viewer)
    }
}
