import SwiftUI
import DeckCore
import DeckProgression

/// The result.
///
/// A poster, not a dialog: the outcome set enormous, the score underneath it,
/// and the things that changed — the streak, an achievement, a boss beaten —
/// laid out like credits. The winning cards gather behind it rather than
/// confetti being thrown at it.
public struct ResultScreen: View {
    private let result: GameResult
    private let coordinator: GameCoordinator
    private let onRematch: () -> Void
    private let onDone: () -> Void

    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var revealed = false
    @State private var countedScore = 0

    public init(result: GameResult,
                coordinator: GameCoordinator,
                onRematch: @escaping () -> Void,
                onDone: @escaping () -> Void) {
        self.result = result
        self.coordinator = coordinator
        self.onRematch = onRematch
        self.onDone = onDone
    }

    private var outcome: GameResult.Outcome { result.outcome(for: coordinator.localSeat) }
    private var definition: GameDefinition? { deck.registry[coordinator.gameID] }
    private var score: Int { result.scores[coordinator.localSeat] ?? 0 }

    private var headline: String {
        switch outcome {
        case .win: return String(localized: "result.win", defaultValue: "YOU WIN")
        case .loss: return String(localized: "result.loss", defaultValue: "YOU LOSE")
        case .draw: return String(localized: "result.draw", defaultValue: "A DRAW")
        case .abandoned: return String(localized: "result.abandoned", defaultValue: "ABANDONED")
        }
    }

    private var headlineColour: Color {
        switch outcome {
        case .win: return theme.positive
        case .loss: return theme.alert
        default: return theme.onGround
        }
    }

    public var body: some View {
        ZStack {
            ground
            ScrollView {
                VStack(alignment: .leading, spacing: DeckSpace.l) {
                    headlineBlock
                    scoreBlock
                    if let outcome = coordinator.challengeOutcome {
                        challengeBlock(outcome)
                    }
                    if let change = coordinator.progressChange, !change.isEmpty {
                        unlockBlock(change)
                    }
                    highlightBlock
                    tryNextBlock
                    Spacer(minLength: DeckSpace.xl)
                    buttons
                }
                .padding(.horizontal, DeckSpace.page)
                .padding(.top, DeckSpace.xxl)
                .padding(.bottom, DeckSpace.xxl)
            }
        }
        .onAppear {
            withAnimation(reducedMotion ? nil : DeckMotion.stamp) { revealed = true }
            animateScore()
        }
        .accessibilityElement(children: .contain)
    }

    private var ground: some View {
        ZStack {
            theme.ground
            if outcome == .win {
                HalftoneField(colour: theme.positive.opacity(0.20), cell: 13, direction: .topTrailing)
            }
            // The cards that finished it, gathered into a corner.
            GeometryReader { proxy in
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.surface.opacity(0.10))
                        .frame(width: 96, height: CardMetrics.height(forWidth: 96))
                        .rotationEffect(.degrees(Double(index) * 9 - 24))
                        .position(x: proxy.size.width * 0.82 + CGFloat(index) * 6,
                                  y: proxy.size.height * 0.24 + CGFloat(index) * 4)
                }
            }
            PaperGrain(intensity: theme.grain, seed: 21, tint: theme.isDark ? .white : .black)
                .opacity(theme.isDark ? 0.3 : 1)
        }
        .ignoresSafeArea()
    }

    private var headlineBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
            Misregistered(offset: CGSize(width: 5, height: 5), ghost: theme.accent.opacity(0.6)) {
                Text(headline)
                    .font(DeckType.display(76))
                    .tracking(-3)
                    .foregroundStyle(headlineColour)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .scaleEffect(revealed ? 1 : 0.9)
            if let definition {
                Text(definition.englishName.uppercased())
                    .font(DeckType.displayCondensed(26))
                    .foregroundStyle(theme.onGroundMuted)
            }
        }
    }

    private var scoreBlock: some View {
        HStack(alignment: .top, spacing: DeckSpace.xl) {
            NumeralBlock(value: "\(countedScore)",
                         unit: String(localized: "result.yourScore", defaultValue: "Your score"),
                         size: 62,
                         colour: theme.onGround,
                         unitColour: theme.onGroundMuted)
            VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                Text(String(localized: "result.table", defaultValue: "Table"))
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.onGroundMuted)
                ForEach(otherSeats, id: \.seat) { entry in
                    HStack(spacing: DeckSpace.xs) {
                        Text(entry.name)
                            .font(DeckType.caption)
                            .foregroundStyle(theme.onGroundMuted)
                        Spacer(minLength: DeckSpace.s)
                        Text("\(entry.score)")
                            .font(DeckType.tabular(15, weight: .bold))
                            .foregroundStyle(theme.onGround)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var otherSeats: [(seat: SeatID, name: String, score: Int)] {
        coordinator.seating.seats
            .filter { $0.id != coordinator.localSeat }
            .map { ($0.id, $0.displayName, result.scores[$0.id] ?? 0) }
    }

    private func challengeBlock(_ outcome: ChallengeOutcome) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            SectionRule(title: String(localized: "result.challenge", defaultValue: "Daily challenge"))
            if outcome.succeeded {
                HStack(alignment: .bottom, spacing: DeckSpace.m) {
                    NumeralBlock(value: "\(outcome.streak)",
                                 unit: String(localized: "streak.dayStreak",
                                              defaultValue: "Day streak"),
                                 size: 56,
                                 colour: theme.accent,
                                 unitColour: theme.onGroundMuted)
                    if outcome.isNewBestStreak {
                        Text(String(localized: "result.newBest", defaultValue: "NEW BEST"))
                            .font(DeckType.display(20))
                            .foregroundStyle(DeckPalette.ink)
                            .padding(.horizontal, DeckSpace.xs)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                                    .fill(theme.positive)
                            )
                            .rotationEffect(.degrees(-5))
                    }
                    Spacer()
                }
                if let bossID = outcome.bossDefeated, let boss = BossCast.boss(bossID) {
                    BossDefeatCard(boss: boss)
                }
            } else {
                // Failure is restrained: what happened, and what is left.
                VStack(alignment: .leading, spacing: DeckSpace.xs) {
                    Text(String(localized: "result.challengeMissed",
                                defaultValue: "The objective was not met."))
                        .font(DeckType.bodyEmphasis)
                        .foregroundStyle(theme.onGround)
                    if let remaining = outcome.attemptsRemaining {
                        Text(remaining > 0
                             ? String(format: String(localized: "result.attemptsLeft",
                                                     defaultValue: "%d attempts left today."), remaining)
                             : String(localized: "result.noAttemptsLeft",
                                      defaultValue: "No attempts left today. Come back tomorrow."))
                            .font(DeckType.caption)
                            .foregroundStyle(theme.onGroundMuted)
                    }
                }
            }
        }
    }

    private func unlockBlock(_ change: ProgressChange) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            SectionRule(title: String(localized: "result.unlocked", defaultValue: "Unlocked"))
            ForEach(change.unlockedAchievements, id: \.self) { id in
                if let definition = deck.progress.achievementEngine.definition(id) {
                    AchievementRow(definition: definition, isUnlocked: true, progress: 1)
                }
            }
            ForEach(change.unlockedCosmetics, id: \.self) { id in
                if let cosmetic = CosmeticCatalog.cosmetic(id) {
                    HStack(spacing: DeckSpace.s) {
                        CosmeticThumbnail(cosmetic: cosmetic, size: 44)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(cosmetic.englishName)
                                .font(DeckType.bodyEmphasis)
                                .foregroundStyle(theme.onGround)
                            Text(LocalizedStringKey(cosmetic.kind.localizationKey))
                                .font(DeckType.footnote)
                                .foregroundStyle(theme.onGroundMuted)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var highlightBlock: some View {
        if !result.highlights.isEmpty {
            VStack(alignment: .leading, spacing: DeckSpace.xs) {
                ForEach(result.highlights, id: \.self) { code in
                    HStack(spacing: DeckSpace.xs) {
                        EmblemMark(emblem(for: code), colour: theme.accent,
                                   accent: theme.onGround.opacity(0.4))
                            .frame(width: 28, height: 28)
                        Text(CalloutRow.humanised(code))
                            .font(DeckType.bodyEmphasis)
                            .foregroundStyle(theme.onGround)
                    }
                }
            }
        }
    }

    private func emblem(for code: String) -> AchievementEmblem {
        if code.contains("moon") { return .moon }
        if code.contains("royal") || code.contains("Flush") { return .royalFan }
        if code.contains("nil") || code.contains("president") { return .crown }
        if code.contains("speed") || code.contains("fast") { return .clock }
        return .stamp
    }

    @ViewBuilder
    private var tryNextBlock: some View {
        if let definition, !definition.recommendations.isEmpty {
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                SectionRule(title: String(localized: "result.tryNext", defaultValue: "Try next"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DeckSpace.m) {
                        ForEach(definition.recommendations, id: \.self) { id in
                            if let next = deck.registry[id] {
                                GameShelfCard(definition: next) {
                                    router.closeGame()
                                    router.tab = .library
                                    router.push(.gameDetail(id))
                                }
                                .frame(width: 150)
                            }
                        }
                    }
                }
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: DeckSpace.xs) {
            if coordinator.challenge == nil {
                DeckButton(String(localized: "result.rematch", defaultValue: "REMATCH"),
                           emphasis: .primary, action: onRematch)
            }
            DeckButton(String(localized: "result.done", defaultValue: "DONE"),
                       emphasis: .secondary, action: onDone)
        }
    }

    /// The score counts up rather than appearing, which is what makes it feel
    /// earned. Reduced motion sets it straight away.
    private func animateScore() {
        guard !reducedMotion, score != 0 else {
            countedScore = score
            return
        }
        let steps = 24
        let target = score
        Task { @MainActor in
            for step in 1...steps {
                countedScore = target * step / steps
                try? await Task.sleep(nanoseconds: 26_000_000)
            }
            countedScore = target
        }
    }
}

/// A boss's lore, revealed the first time they are beaten.
public struct BossDefeatCard: View {
    private let boss: Boss
    @Environment(\.deckTheme) private var theme

    public init(boss: Boss) { self.boss = boss }

    public var body: some View {
        HStack(alignment: .top, spacing: DeckSpace.m) {
            BossPortrait(boss: boss)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous))
            VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                Text(boss.displayName.uppercased())
                    .font(DeckType.display(30))
                    .foregroundStyle(DeckPalette.token(boss.colourToken))
                Text("“\(boss.englishLore)”")
                    .font(DeckType.body)
                    .italic()
                    .foregroundStyle(theme.onGround)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "boss.added", defaultValue: "Added to your collection."))
                    .font(DeckType.footnote)
                    .foregroundStyle(theme.onGroundMuted)
            }
        }
        .padding(DeckSpace.m)
        .background(
            RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous)
                .fill(theme.onGround.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
    }
}
