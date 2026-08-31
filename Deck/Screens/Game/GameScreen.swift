import SwiftUI
import DeckCore
import DeckProgression

/// The table.
///
/// Everything above the hand rail is the game; everything below it is the
/// player's own cards and the moves they can make. There is no navigation
/// chrome on the table itself — pause, rules and hints live in one small row at
/// the top, and the rest of the screen belongs to the cards.
public struct GameScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var coordinator: GameCoordinator?
    @State private var loadFailure: String?
    @State private var showsPauseMenu = false
    @State private var showsRules = false
    @State private var sealProgress: Double = 0
    @State private var pendingChoiceCard: CardID?

    private let gameID: GameID
    private let challenge: DailyChallenge?
    private let resumeExisting: Bool

    public init(gameID: GameID, challenge: DailyChallenge? = nil, resumeExisting: Bool = false) {
        self.gameID = gameID
        self.challenge = challenge
        self.resumeExisting = resumeExisting
    }

    public var body: some View {
        ZStack {
            tableGround
            if let coordinator {
                content(coordinator)
            } else if let loadFailure {
                DeckErrorView(message: loadFailure,
                              retryTitle: String(localized: "common.back", defaultValue: "BACK"),
                              onRetry: { router.closeGame() })
            } else {
                DeckLoadingView(message: String(localized: "game.dealing", defaultValue: "Dealing…"))
            }
        }
        .task { await start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                coordinator?.returnedToForeground()
            case .inactive, .background:
                // The app switcher takes a snapshot the moment this fires, so
                // everything private has to be gone before it returns.
                coordinator?.shieldForBackground()
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showsRules) {
            if let definition = deck.registry[gameID] {
                RulesSheet(definition: definition)
            }
        }
        .sheet(isPresented: $showsPauseMenu) {
            if let coordinator {
                PauseSheet(coordinator: coordinator,
                           onResume: { showsPauseMenu = false },
                           onRules: { showsPauseMenu = false; showsRules = true },
                           onQuit: {
                               coordinator.abandon()
                               showsPauseMenu = false
                               router.closeGame()
                           })
            }
        }
    }

    private var tableGround: some View {
        ZStack {
            theme.ground
            TableCloth(theme: theme, gameID: gameID)
        }
        .ignoresSafeArea()
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ coordinator: GameCoordinator) -> some View {
        ZStack {
            VStack(spacing: 0) {
                statusBar(coordinator)
                TableSurface(presentation: coordinator.presentation,
                             selection: coordinator.selection,
                             highlighted: Set(coordinator.hint?.cards ?? []),
                             cardBackID: coordinator.cardBack,
                             isInteractive: coordinator.acceptsInput,
                             onTapCard: { handleTap($0, coordinator) },
                             onTapZone: { handleZoneTap($0, coordinator) })
                    .frame(maxHeight: .infinity)
                actionBar(coordinator)
            }
            .opacity(coordinator.privacyPhase.showsPrivateInformation ? 1 : 0)
            // Belt and braces: the table is also removed from the hierarchy
            // while the device is in transit, so nothing private can be
            // snapshotted even at zero opacity.
            .allowsHitTesting(coordinator.acceptsInput)

            if coordinator.isSealing {
                SealOverlay(progress: sealProgress)
                    .onAppear { runSeal(coordinator) }
            }

            if case let .handoff(next) = coordinator.privacyPhase {
                PassScreen(playerName: coordinator.seating[next]?.displayName ?? "",
                           seatIndex: next.rawValue,
                           onReveal: { coordinator.confirmReveal() })
                    .transition(.opacity)
            }

            if let card = pendingChoiceCard {
                MoveChoiceSheet(card: card,
                                options: coordinator.actions(for: card),
                                onPick: { token in
                                    pendingChoiceCard = nil
                                    coordinator.perform(token)
                                },
                                onCancel: { pendingChoiceCard = nil })
            }

            if let hint = coordinator.hint {
                HintCard(hint: hint, onDismiss: { coordinator.dismissHint() })
            }

            if let rejection = coordinator.rejection {
                RejectionBanner(reason: rejection)
            }

            if let result = coordinator.result {
                ResultScreen(result: result,
                             coordinator: coordinator,
                             onRematch: { restart() },
                             onDone: { router.closeGame() })
                    .transition(.opacity)
            }
        }
        .animation(DeckMotion.respectingReduceMotion(DeckMotion.panel, reduced: reducedMotion),
                   value: coordinator.privacyPhase)
    }

    // MARK: - Status

    private func statusBar(_ coordinator: GameCoordinator) -> some View {
        VStack(spacing: DeckSpace.xs) {
            HStack(spacing: DeckSpace.xs) {
                DeckIconButton(systemImage: "pause.fill",
                               label: String(localized: "game.pause", defaultValue: "Pause")) {
                    coordinator.saveCheckpoint()
                    showsPauseMenu = true
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(phaseText(coordinator))
                        .font(DeckType.displayCondensed(19))
                        .foregroundStyle(theme.onGround)
                    if let challenge = coordinator.challenge {
                        Text(challenge.objective.englishDescription)
                            .font(DeckType.footnote)
                            .foregroundStyle(theme.onGroundMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if coordinator.canUndo {
                    DeckIconButton(systemImage: "arrow.uturn.backward",
                                   label: String(localized: "game.undo", defaultValue: "Undo")) {
                        coordinator.undo()
                    }
                }
                DeckIconButton(systemImage: "lightbulb",
                               label: String(localized: "game.hint", defaultValue: "Hint"),
                               isEnabled: coordinator.acceptsInput) {
                    coordinator.requestHint()
                }
                DeckIconButton(systemImage: "questionmark",
                               label: String(localized: "game.rules", defaultValue: "How to play")) {
                    showsRules = true
                }
            }
            CalloutRow(callouts: coordinator.presentation.callouts)
        }
        .padding(.horizontal, DeckSpace.m)
        .padding(.top, DeckSpace.xs)
    }

    private func phaseText(_ coordinator: GameCoordinator) -> String {
        let presentation = coordinator.presentation
        let format = String.deck(presentation.phaseKey, or: CalloutRow.humanised(presentation.phaseKey))
        return CalloutRow.interpolate(format, arguments: presentation.phaseArguments)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionBar(_ coordinator: GameCoordinator) -> some View {
        let selectionActions = coordinator.actionsForSelection()
        let barActions = coordinator.presentation.barActions

        VStack(spacing: DeckSpace.xs) {
            if !coordinator.selection.isEmpty {
                HStack(spacing: DeckSpace.xs) {
                    ForEach(selectionActions) { token in
                        MoveButton(title: label(for: token),
                                   detail: token.amount.map { "\($0)" },
                                   tone: .go) {
                            coordinator.perform(token)
                        }
                    }
                    MoveButton(title: String(localized: "common.clear", defaultValue: "CLEAR"),
                               tone: .hold) {
                        coordinator.clearSelection()
                    }
                }
            }
            if !barActions.isEmpty {
                HStack(spacing: DeckSpace.xs) {
                    ForEach(barActions.prefix(4)) { token in
                        MoveButton(title: label(for: token),
                                   detail: detail(for: token),
                                   tone: tone(for: token)) {
                            coordinator.perform(token)
                        }
                    }
                }
            }
            if coordinator.isThinking {
                Text(String(localized: "game.thinking", defaultValue: "Thinking…"))
                    .font(DeckType.caption)
                    .foregroundStyle(theme.onGroundMuted)
            }
        }
        .padding(.horizontal, DeckSpace.m)
        .padding(.bottom, DeckSpace.s)
        .frame(minHeight: 8)
    }

    private func label(for token: ActionToken) -> String {
        let format = String.deck(token.labelKey, or: CalloutRow.humanised(token.labelKey))
        return CalloutRow.interpolate(format, arguments: token.labelArguments).uppercased()
    }

    private func detail(for token: ActionToken) -> String? {
        guard let amount = token.amount, token.kind != .bid else { return nil }
        return "\(amount)"
    }

    private func tone(for token: ActionToken) -> MoveButton.Tone {
        switch token.kind {
        case .fold, .concede: return .stop
        case .check, .passTurn, .acknowledge: return .hold
        default: return .go
        }
    }

    private func handleTap(_ card: CardID, _ coordinator: GameCoordinator) {
        let options = coordinator.actions(for: card)
        if options.count > 1 {
            // Several legal moves use this card — an eight and four suits, or a
            // card that can go to two piles. Ask rather than guess.
            pendingChoiceCard = card
            Haptics.shared.tap(.pickUp)
        } else {
            coordinator.tapCard(card)
        }
    }

    private func handleZoneTap(_ zone: Zone, _ coordinator: GameCoordinator) {
        // A tap on an empty slot is a move when the game offers one for it.
        if let token = coordinator.presentation.actions.first(where: {
            $0.destination == zone && $0.cards.isEmpty
        }) {
            coordinator.perform(token)
        } else if let token = coordinator.presentation.actions.first(where: {
            $0.source == zone && $0.cards.isEmpty
        }) {
            coordinator.perform(token)
        }
    }

    // MARK: - Lifecycle

    private func runSeal(_ coordinator: GameCoordinator) {
        sealProgress = 0
        let duration = reducedMotion ? 0.0 : DeckMotion.seal
        if duration > 0 {
            withAnimation(.easeInOut(duration: duration)) { sealProgress = 1 }
        } else {
            sealProgress = 1
        }
        Task { @MainActor in
            if duration > 0 {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
            coordinator.sealingFinished()
            sealProgress = 0
        }
    }

    private func start() async {
        guard coordinator == nil else { return }

        if resumeExisting, let resumed = deck.resumeSavedGame() {
            coordinator = GameCoordinator(session: resumed.session, progress: deck.progress)
            return
        }

        if let challenge {
            guard let configuration = deck.challengeConfiguration(),
                  let session = deck.makeSession(configuration) else {
                loadFailure = String(localized: "game.challengeFailed",
                                     defaultValue: "Today's challenge could not be dealt. Try another game.")
                return
            }
            guard let attempt = deck.progress.beginChallengeAttempt(challenge) else {
                loadFailure = String(localized: "game.noAttempts",
                                     defaultValue: "You have used today's attempts.")
                return
            }
            coordinator = GameCoordinator(session: session,
                                          progress: deck.progress,
                                          challenge: challenge,
                                          attempt: attempt)
            return
        }

        guard let definition = deck.registry[gameID] else {
            loadFailure = String(localized: "game.unknown",
                                 defaultValue: "That game is not in the library.")
            return
        }
        let profile = deck.progress.profiles.primary
        let aiCount = definition.supportsAIOpponents
            ? max(0, definition.playerRange.lowerBound - 1)
            : 0
        guard let configuration = deck.configuration(gameID: gameID,
                                                     humanCount: 1,
                                                     aiCount: aiCount,
                                                     variantID: definition.defaultVariantID,
                                                     options: [:],
                                                     difficulty: deck.progress.settings.preferredDifficulty,
                                                     humanProfiles: profile.map { [$0] } ?? []),
              let session = deck.makeSession(configuration) else {
            loadFailure = String(localized: "game.dealFailed",
                                 defaultValue: "That game could not be dealt.")
            return
        }
        coordinator = GameCoordinator(session: session, progress: deck.progress)
    }

    private func restart() {
        coordinator = nil
        Task { await start() }
    }
}

/// The table itself: a painted surface that changes with the game without ever
/// competing with the cards on top of it.
public struct TableCloth: View {
    private let theme: DeckTheme
    private let gameID: GameID

    public init(theme: DeckTheme, gameID: GameID) {
        self.theme = theme
        self.gameID = gameID
    }

    public var body: some View {
        GeometryReader { proxy in
            let box = proxy.size
            ZStack {
                // One oversized suit mark, cropped hard and kept very quiet.
                SuitShape(signatureSuit, wobble: 0.02, seed: gameID.rawValue.count)
                    .fill(theme.accent.opacity(theme.isDark ? 0.09 : 0.07))
                    .frame(width: box.width * 1.1, height: box.width * 1.1)
                    .rotationEffect(.degrees(-12))
                    .offset(x: box.width * 0.34, y: -box.height * 0.18)
                PaperGrain(intensity: theme.grain * 0.8, seed: 11,
                           tint: theme.isDark ? .white : .black)
                    .opacity(theme.isDark ? 0.3 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var signatureSuit: SuitShape.Kind {
        switch gameID {
        case .hearts: return .heart
        case .spades, .euchre: return .spade
        case .texasHoldem, .cheat: return .diamond
        default: return .club
        }
    }
}
