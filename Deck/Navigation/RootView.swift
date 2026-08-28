import SwiftUI
import DeckCore
import DeckProgression

/// The shell.
///
/// Five places, a custom bar drawn to match the rest of the app, and a game that
/// covers the whole thing when one is running — because a table with a tab bar
/// under it is a table you are not concentrating on.
public struct RootView: View {
    @Environment(AppEnvironment.self) private var deck
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    private var theme: DeckTheme { deck.theme }

    public var body: some View {
        ZStack {
            theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                tabContent
                DeckTabBar(selection: Binding(
                    get: { router.tab },
                    set: { newValue in
                        if newValue == router.tab { router.popToRoot() }
                        router.tab = newValue
                        Haptics.shared.tap(.light)
                    }
                ))
            }

            if let active = router.activeGame {
                GameScreen(gameID: active.gameID, challenge: active.challenge)
                    .transition(.opacity)
                    .zIndex(10)
            }

            if router.showsWelcome {
                WelcomeScreen { mode in
                    finishWelcome(mode)
                }
                .transition(.opacity)
                .zIndex(20)
            }

            if let poster = router.pendingPosters.first {
                UnlockPosterView(poster: poster) {
                    router.dismissTopPoster()
                }
                .zIndex(30)
            }
        }
        .environment(router)
        .environment(\.deckTheme, theme)
        .environment(\.deckReducedMotion, deck.reducedMotion)
        .animation(.easeInOut(duration: DeckMotion.quick), value: router.activeGame)
        .task { await bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                deck.refreshDay()
                AudioService.shared.resume()
            } else if phase == .background {
                AudioService.shared.suspend()
            }
        }
        .onChange(of: router.activeGame) { _, newValue in
            // Unlocks queued during a game are shown once the game is closed,
            // so a poster never lands on top of a live table.
            guard newValue == nil else { return }
            collectPendingPosters()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch router.tab {
        case .today:
            NavigationStack(path: Binding(get: { router.todayPath },
                                          set: { router.todayPath = $0 })) {
                TodayScreen().navigationDestination(for: DeckDestination.self) { destination(for: $0) }
            }
        case .play:
            NavigationStack(path: Binding(get: { router.playPath },
                                          set: { router.playPath = $0 })) {
                PlayScreen().navigationDestination(for: DeckDestination.self) { destination(for: $0) }
            }
        case .library:
            NavigationStack(path: Binding(get: { router.libraryPath },
                                          set: { router.libraryPath = $0 })) {
                LibraryScreen().navigationDestination(for: DeckDestination.self) { destination(for: $0) }
            }
        case .collection:
            NavigationStack(path: Binding(get: { router.collectionPath },
                                          set: { router.collectionPath = $0 })) {
                CollectionScreen().navigationDestination(for: DeckDestination.self) { destination(for: $0) }
            }
        case .profile:
            NavigationStack(path: Binding(get: { router.profilePath },
                                          set: { router.profilePath = $0 })) {
                ProfileScreen().navigationDestination(for: DeckDestination.self) { destination(for: $0) }
            }
        }
    }

    @ViewBuilder
    private func destination(for destination: DeckDestination) -> some View {
        switch destination {
        case let .gameDetail(id):
            GameDetailScreen(gameID: id)
        case let .gameSetup(id, mode):
            GameSetupScreen(gameID: id, mode: mode)
        case .library:
            LibraryScreen()
        case .achievements:
            AchievementsScreen()
        case .statistics:
            StatisticsScreen()
        case .mastery:
            StatisticsScreen()
        case .collection:
            CollectionScreen()
        case .bosses:
            CollectionScreen()
        case let .boss(id):
            BossScreen(bossID: id)
        case .profile:
            ProfileScreen()
        case .profiles:
            ProfilesScreen()
        case .settings:
            SettingsScreen()
        case .premium:
            PremiumScreen()
        case .history:
            HistoryScreen()
        case .leaderboards:
            LeaderboardsScreen()
        case let .rules(id):
            if let definition = deck.registry[id] {
                RulesSheet(definition: definition)
            }
        case let .tutorial(id):
            if let definition = deck.registry[id] {
                RulesSheet(definition: definition)
            }
        }
    }

    // MARK: - Lifecycle

    private func bootstrap() async {
        Haptics.shared.prepare()
        AudioService.shared.prepare()
        deck.store.start()
        if !deck.progress.settings.hasSeenWelcome {
            router.showsWelcome = true
        }
        collectPendingPosters()
        await deck.gameServices.authenticate()
        deck.syncLeaderboards()
    }

    private func finishWelcome(_ mode: PlayMode?) {
        var settings = deck.progress.settings
        settings.hasSeenWelcome = true
        deck.progress.update(settings: settings)
        router.showsWelcome = false
        switch mode {
        case .solo:
            router.tab = .play
        case .passAndPlay:
            router.tab = .play
        case nil:
            router.tab = .library
        }
    }

    private func collectPendingPosters() {
        let achievements = deck.progress.consumeAchievementCelebrations()
        let cosmetics = deck.progress.consumeCollectionReveals()
        var posters: [AppRouter.UnlockPoster] = achievements.map { .achievement($0) }
        posters += cosmetics.map { .cosmetic($0) }
        if !posters.isEmpty { router.queue(posters) }
    }
}

/// The tab bar, drawn rather than inherited.
///
/// Five destinations, each with its own drawn mark, and a painted rule under the
/// one you are on. It is a tab bar because that is what people expect at the
/// bottom of an iPhone app — it just does not have to look like everybody's.
public struct DeckTabBar: View {
    @Binding var selection: DeckTab
    @Environment(\.deckTheme) private var theme

    public init(selection: Binding<DeckTab>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(DeckTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        mark(for: tab)
                            .frame(width: 22, height: 22)
                        Text(LocalizedStringKey(tab.localizationKey))
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.3)
                            .textCase(.uppercase)
                        PaintStroke(bow: 0, weight: 0.8, seed: tab.rawValue.count)
                            .fill(theme.accent)
                            .frame(width: 26, height: 4)
                            .opacity(selection == tab ? 1 : 0)
                    }
                    .foregroundStyle(selection == tab ? theme.onGround : theme.onGroundMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(tab.localizationKey)))
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, DeckSpace.xs)
        .background(
            ZStack {
                theme.ground
                Rectangle()
                    .fill(theme.onGround.opacity(0.14))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Each tab gets a drawn mark rather than a stock glyph.
    @ViewBuilder
    private func mark(for tab: DeckTab) -> some View {
        switch tab {
        case .today:
            StampOutline(form: .block, seed: 2, breakUp: 0.12)
                .stroke(lineWidth: 2)
        case .play:
            SuitShape(.spade, wobble: 0.015, seed: 3)
        case .library:
            DeckGlyph(fan: 0.9)
        case .collection:
            SuitShape(.diamond, wobble: 0.015, seed: 5)
        case .profile:
            SuitShape(.heart, wobble: 0.015, seed: 7)
        }
    }
}
