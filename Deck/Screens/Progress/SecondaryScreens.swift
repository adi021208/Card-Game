import SwiftUI
import DeckCore
import DeckProgression

/// Recent games.
///
/// A short list, not a feed. Each entry keeps its seed and its move log, so a
/// game can be looked at again rather than just counted.
public struct HistoryScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.m) {
                DisplayText(String(localized: "history.title", defaultValue: "RECENT GAMES"),
                            size: 44, colour: theme.onGround)
                    .padding(.top, DeckSpace.m)
                if deck.progress.history.entries.isEmpty {
                    EmptyStateCard(title: String(localized: "history.empty.title",
                                                 defaultValue: "NOTHING PLAYED YET."),
                                   message: String(localized: "history.empty.body",
                                                   defaultValue: "Finished games land here, with the deal they came from."),
                                   emblem: .binder)
                } else {
                    ForEach(deck.progress.history.entries) { entry in
                        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                            HistoryRow(entry: entry,
                                       gameName: deck.registry[entry.gameID]?.englishName ?? "")
                            Text(entry.playedAt, style: .date)
                                .font(DeckType.footnote)
                                .foregroundStyle(theme.onGroundMuted)
                        }
                        Divider().opacity(0.15)
                    }
                }
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(theme.ground.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }
}

/// Leaderboards.
///
/// When Game Center is not signed in this says so plainly and shows the local
/// numbers instead. It never invents a table of strangers.
public struct LeaderboardsScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme

    @State private var entries: [LeaderboardEntry] = []
    @State private var board: LeaderboardID = .bestStreak
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.l) {
                DisplayText(String(localized: "leaderboards.title", defaultValue: "LEADERBOARDS"),
                            size: 42, colour: theme.onGround)
                    .padding(.top, DeckSpace.m)

                if !deck.gameServices.isAuthenticated {
                    EmptyStateCard(title: String(localized: "leaderboards.offline.title",
                                                 defaultValue: "NOT SIGNED IN."),
                                   message: deck.gameServices.statusMessage
                                        ?? String(localized: "leaderboards.offline.body",
                                                  defaultValue: "Connect Game Center to compare your streak with everybody else's. Everything else in DECK works without it."),
                                   emblem: .clock,
                                   actionTitle: String(localized: "settings.connectGameCenter",
                                                       defaultValue: "CONNECT GAME CENTER")) {
                        Task {
                            await deck.gameServices.authenticate()
                            await reload()
                        }
                    }
                    localNumbers
                } else {
                    picker
                    if isLoading {
                        DeckLoadingView(message: String(localized: "leaderboards.loading",
                                                        defaultValue: "Loading…"))
                            .frame(maxWidth: .infinity)
                    } else if entries.isEmpty {
                        EmptyStateCard(title: String(localized: "leaderboards.empty.title",
                                                     defaultValue: "NOBODY HERE YET."),
                                       message: String(localized: "leaderboards.empty.body",
                                                       defaultValue: "Be the first name on it."),
                                       emblem: .crown)
                    } else {
                        ForEach(entries) { entry in
                            HStack(spacing: DeckSpace.m) {
                                Text("\(entry.rank)")
                                    .font(DeckType.numeral(22))
                                    .foregroundStyle(entry.isLocalPlayer ? theme.accent
                                                                         : theme.onGroundMuted)
                                    .frame(width: 40, alignment: .leading)
                                Text(entry.displayName)
                                    .font(DeckType.body)
                                    .foregroundStyle(theme.onGround)
                                Spacer()
                                Text(entry.formattedScore)
                                    .font(DeckType.tabular(17, weight: .bold))
                                    .foregroundStyle(theme.onGround)
                            }
                            .padding(.vertical, DeckSpace.xxs)
                        }
                    }
                }
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(theme.ground.ignoresSafeArea())
        .task { await reload() }
    }

    private var picker: some View {
        HStack(spacing: DeckSpace.xs) {
            chip(String(localized: "leaderboards.streak", defaultValue: "Streak"), .bestStreak)
            chip(String(localized: "leaderboards.daily", defaultValue: "Days"), .dailyCompletions)
            chip(String(localized: "leaderboards.wins", defaultValue: "Wins"), .totalWins)
        }
    }

    private func chip(_ title: String, _ value: LeaderboardID) -> some View {
        Button {
            board = value
            Task { await reload() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, DeckSpace.s)
                .frame(height: 36)
                .foregroundStyle(board == value ? DeckPalette.cream : theme.onGround)
                .background(
                    RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                        .fill(board == value ? theme.accent : theme.onGround.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }

    private var localNumbers: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: String(localized: "leaderboards.yours", defaultValue: "Your numbers"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: DeckSpace.m)],
                      spacing: DeckSpace.m) {
                StatTile(value: "\(deck.progress.challenge.bestStreak)",
                         label: String(localized: "stat.bestStreak", defaultValue: "Best streak"))
                StatTile(value: "\(deck.progress.challenge.completedDays.count)",
                         label: String(localized: "stat.daysDone", defaultValue: "Days completed"))
                StatTile(value: "\(deck.progress.statistics.global.gamesWon)",
                         label: String(localized: "stat.wins", defaultValue: "Wins"))
            }
        }
    }

    private func reload() async {
        guard deck.gameServices.isAuthenticated else { return }
        isLoading = true
        deck.syncLeaderboards()
        entries = await deck.gameServices.topScores(board)
        isLoading = false
    }
}

/// An unlock, shown as a poster once whatever was on screen has finished.
public struct UnlockPosterView: View {
    private let poster: AppRouter.UnlockPoster
    private let onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var landed = false

    public init(poster: AppRouter.UnlockPoster, onDismiss: @escaping () -> Void) {
        self.poster = poster
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            content
                .scaleEffect(landed ? 1 : 1.6)
                .rotationEffect(landed ? .degrees(-2) : .degrees(-14))
                .opacity(landed ? 1 : 0)
        }
        .onAppear {
            withAnimation(reducedMotion ? nil : DeckMotion.stamp) { landed = true }
            AudioService.shared.play(.stamp)
            Haptics.shared.tap(.achievement)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch poster {
        case let .achievement(id):
            if let definition = deck.progress.achievementEngine.definition(id) {
                posterCard(title: CalloutRow.humanised(definition.titleKey),
                           subtitle: CalloutRow.humanised(definition.descriptionKey),
                           emblem: definition.emblem,
                           label: String(localized: "unlock.achievement",
                                         defaultValue: "ACHIEVEMENT"))
            }
        case let .cosmetic(id):
            if let cosmetic = CosmeticCatalog.cosmetic(id) {
                VStack(spacing: DeckSpace.m) {
                    Text(String(localized: "unlock.unlocked", defaultValue: "UNLOCKED"))
                        .font(DeckType.display(24))
                        .foregroundStyle(theme.accent)
                    CosmeticThumbnail(cosmetic: cosmetic, size: 130)
                    Text(cosmetic.englishName.uppercased())
                        .font(DeckType.display(38))
                        .foregroundStyle(theme.ink)
                    Text(LocalizedStringKey(cosmetic.kind.localizationKey))
                        .font(DeckType.caption)
                        .foregroundStyle(theme.ink.opacity(0.7))
                    DeckButton(String(localized: "common.nice", defaultValue: "NICE"),
                               emphasis: .primary, action: onDismiss)
                }
                .padding(DeckSpace.l)
                .background(posterBackground)
                .padding(DeckSpace.page)
            }
        case let .boss(id):
            if let boss = BossCast.boss(id) {
                VStack(spacing: DeckSpace.m) {
                    BossPortrait(boss: boss)
                        .frame(width: 150, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.panel,
                                                    style: .continuous))
                    Text(boss.displayName.uppercased())
                        .font(DeckType.display(42))
                        .foregroundStyle(DeckPalette.token(boss.colourToken))
                    Text("“\(boss.englishLore)”")
                        .font(DeckType.body)
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.ink)
                    DeckButton(String(localized: "common.nice", defaultValue: "NICE"),
                               emphasis: .primary, action: onDismiss)
                }
                .padding(DeckSpace.l)
                .background(posterBackground)
                .padding(DeckSpace.page)
            }
        }
    }

    private func posterCard(title: String, subtitle: String,
                            emblem: AchievementEmblem, label: String) -> some View {
        VStack(spacing: DeckSpace.m) {
            Text(label)
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking * 2)
                .foregroundStyle(theme.accent)
            EmblemMark(emblem, colour: theme.accent, accent: theme.ink.opacity(0.5))
                .frame(width: 110, height: 110)
            Misregistered(offset: CGSize(width: 3, height: 3), ghost: theme.accent.opacity(0.5)) {
                Text(title.uppercased())
                    .font(DeckType.display(44))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }
            Text(subtitle)
                .font(DeckType.body)
                .foregroundStyle(theme.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            DeckButton(String(localized: "common.nice", defaultValue: "NICE"),
                       emphasis: .primary, action: onDismiss)
        }
        .padding(DeckSpace.l)
        .background(posterBackground)
        .padding(DeckSpace.page)
    }

    private var posterBackground: some View {
        ZStack {
            theme.surface
            HalftoneField(colour: theme.accent.opacity(0.16), cell: 11, direction: .topTrailing)
            PaperGrain(intensity: 0.12, seed: 33, tint: .black)
        }
        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.poster, style: .continuous))
    }
}
