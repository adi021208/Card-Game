import SwiftUI
import DeckCore
import DeckProgression

/// The front page.
///
/// Three things in a deliberate order: today's challenge as a poster, the streak
/// as a number you can see from across the room, and whatever game was left
/// half-played. Everything else is one tap away and none of it is on this
/// screen, because a home screen that lists everything is a menu, not a
/// front page.
public struct TodayScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme
    @Environment(AppRouter.self) private var router

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.section) {
                masthead
                challengePoster
                streakBlock
                continueBlock
                quickPlayBlock
                exploreBlock
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(groundLayer)
        .scrollIndicators(.hidden)
    }

    // MARK: - Ground

    private var groundLayer: some View {
        ZStack {
            theme.ground
            PaperGrain(intensity: theme.grain, seed: 2, tint: theme.isDark ? .white : .black)
                .opacity(theme.isDark ? 0.25 : 1)
        }
        .ignoresSafeArea()
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack(alignment: .top) {
            DeckLockup(scale: 0.72, colour: theme.onGround, accent: theme.accent)
            Spacer()
            if deck.progress.hasPremium {
                Text(String(localized: "premium.badge", defaultValue: "PREMIUM"))
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking)
                    .foregroundStyle(DeckPalette.ink)
                    .padding(.horizontal, DeckSpace.xs)
                    .padding(.vertical, DeckSpace.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                            .fill(theme.positive)
                    )
                    .rotationEffect(.degrees(-4))
            }
        }
        .padding(.top, DeckSpace.s)
    }

    // MARK: - Today's challenge

    @ViewBuilder
    private var challengePoster: some View {
        if let challenge = deck.todaysChallenge,
           let definition = deck.registry[challenge.gameID] {
            ChallengePoster(challenge: challenge,
                            definition: definition,
                            isCompleted: deck.progress.challenge.isCompleted(challenge.date),
                            attemptsRemaining: deck.attemptsRemaining,
                            bestScore: deck.progress.challenge.bestScores[challenge.id],
                            bestTime: deck.progress.challenge.bestTimes[challenge.id],
                            canPlay: deck.canPlayChallenge,
                            onPlay: { startChallenge(challenge) },
                            onUpgrade: { router.push(.premium) })
        } else {
            // Nothing to show is a designed state, not an apology.
            EmptyStateCard(title: String(localized: "today.noChallenge.title",
                                         defaultValue: "NO CHALLENGE TODAY"),
                           message: String(localized: "today.noChallenge.body",
                                           defaultValue: "The daily deal could not be built. Everything else still works."),
                           emblem: .clock)
        }
    }

    // MARK: - Streak

    private var streakBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: String(localized: "today.streak", defaultValue: "Your streak"))
            StreakStrip(progress: deck.progress.challenge, today: deck.today)
        }
    }

    // MARK: - Continue

    @ViewBuilder
    private var continueBlock: some View {
        if let saved = deck.savedGameSummary,
           let definition = deck.registry[saved.gameID] {
            VStack(alignment: .leading, spacing: DeckSpace.m) {
                SectionRule(title: String(localized: "today.continue", defaultValue: "Continue"))
                Button {
                    router.openGame(saved.gameID, transition: .deckFlip)
                } label: {
                    HStack(spacing: DeckSpace.m) {
                        GameCoverArt(artworkID: definition.artworkID,
                                     title: definition.englishName,
                                     size: .chip,
                                     seed: saved.gameID.rawValue.count)
                            .frame(width: 72, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: DeckRadius.panel,
                                                        style: .continuous))
                        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                            Text(definition.englishName)
                                .font(DeckType.displayCondensed(28))
                                .foregroundStyle(theme.onGround)
                            Text(String(format: String(localized: "today.continue.round",
                                                       defaultValue: "Round %d"),
                                        saved.roundNumber))
                                .font(DeckType.caption)
                                .foregroundStyle(theme.onGroundMuted)
                            Text(saved.savedAt, style: .relative)
                                .font(DeckType.footnote)
                                .foregroundStyle(theme.onGroundMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(DeckSpace.m)
                    .background(
                        RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous)
                            .fill(theme.onGround.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick play

    private var quickPlayBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            HStack(spacing: DeckSpace.s) {
                DeckButton(String(localized: "today.quickPlay", defaultValue: "QUICK PLAY"),
                           emphasis: .primary,
                           icon: "bolt.fill") {
                    quickPlay()
                }
                DeckButton(String(localized: "today.passAndPlay", defaultValue: "PASS & PLAY"),
                           emphasis: .secondary) {
                    router.tab = .play
                }
            }
        }
    }

    // MARK: - Explore

    private var exploreBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: String(localized: "today.explore", defaultValue: "Explore"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DeckSpace.m) {
                    ForEach(recommended, id: \.id) { definition in
                        GameShelfCard(definition: definition) {
                            router.tab = .library
                            router.push(.gameDetail(definition.id))
                        }
                        .frame(width: 168)
                    }
                }
                .padding(.horizontal, DeckSpace.page)
            }
            .padding(.horizontal, -DeckSpace.page)
        }
    }

    /// Games the player has not tried, then the ones they have played least.
    private var recommended: [GameDefinition] {
        let statistics = deck.progress.statistics
        return deck.registry.all.sorted { lhs, rhs in
            let left = statistics.record(for: lhs.id).gamesPlayed
            let right = statistics.record(for: rhs.id).gamesPlayed
            if left != right { return left < right }
            return lhs.englishName < rhs.englishName
        }.prefix(6).map { $0 }
    }

    // MARK: - Actions

    private func startChallenge(_ challenge: DailyChallenge) {
        router.openGame(challenge.gameID,
                        challenge: challenge,
                        transition: DeckTransition.between(from: nil,
                                                           to: challenge.gameID,
                                                           registry: deck.registry))
    }

    private func quickPlay() {
        let settings = deck.progress.settings
        let gameID = settings.quickPlayGameID
            ?? deck.progress.history.recentGameIDs.first
            ?? deck.registry.all.first?.id
        guard let gameID else { return }
        router.openGame(gameID,
                        transition: DeckTransition.between(from: nil, to: gameID,
                                                           registry: deck.registry))
    }
}

/// A ruled section heading: a word and a painted line, not an eyebrow.
public struct SectionRule: View {
    private let title: String
    @Environment(\.deckTheme) private var theme

    public init(title: String) { self.title = title }

    public var body: some View {
        HStack(alignment: .center, spacing: DeckSpace.s) {
            Text(title.uppercased())
                .font(DeckType.displayCondensed(20))
                .tracking(0.4)
                .foregroundStyle(theme.onGround)
            Rectangle()
                .fill(theme.onGround.opacity(0.25))
                .frame(height: 2)
        }
        .accessibilityAddTraits(.isHeader)
    }
}
