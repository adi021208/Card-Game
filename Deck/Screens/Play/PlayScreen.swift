import SwiftUI
import DeckCore
import DeckProgression

/// Choosing a game to play right now.
///
/// Two doors — on your own, or round a table — and then the shortest path to
/// dealing. Solo defaults to the last thing played; Pass & Play asks who is
/// here, once, and remembers.
public struct PlayScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme

    @State private var mode: PlayMode = .solo

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.section) {
                header
                modePicker
                gamesForMode
                if mode == .passAndPlay { tableBlock }
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(ground)
        .scrollIndicators(.hidden)
    }

    private var ground: some View {
        ZStack {
            theme.ground
            PaperGrain(intensity: theme.grain, seed: 3, tint: theme.isDark ? .white : .black)
                .opacity(theme.isDark ? 0.25 : 1)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
            DisplayText(String(localized: "play.title", defaultValue: "PLAY"),
                        size: 66, colour: theme.onGround)
            PaintStroke(bow: 0.03, weight: 0.4, seed: 21)
                .fill(theme.accent)
                .frame(height: 10)
                .frame(maxWidth: 180)
        }
        .padding(.top, DeckSpace.m)
    }

    /// Two big choices, drawn as two cards rather than as a segmented control.
    private var modePicker: some View {
        HStack(spacing: DeckSpace.m) {
            modeCard(.solo,
                     title: String(localized: "mode.solo", defaultValue: "SOLO"),
                     detail: String(localized: "mode.solo.detail",
                                    defaultValue: "You against the cast."),
                     suit: .spade)
            modeCard(.passAndPlay,
                     title: String(localized: "mode.passAndPlay", defaultValue: "PASS & PLAY"),
                     detail: String(localized: "mode.passAndPlay.detail",
                                    defaultValue: "One phone, everybody round it."),
                     suit: .heart)
        }
    }

    private func modeCard(_ value: PlayMode, title: String, detail: String,
                          suit: SuitShape.Kind) -> some View {
        let isSelected = mode == value
        return Button {
            withAnimation(DeckMotion.select) { mode = value }
            Haptics.shared.tap(.light)
        } label: {
            VStack(alignment: .leading, spacing: DeckSpace.xs) {
                SuitShape(suit, wobble: 0.02, seed: value.rawValue.count)
                    .fill(isSelected ? DeckPalette.cream : theme.onGround.opacity(0.35))
                    .frame(width: 34, height: 34)
                Text(title)
                    .font(DeckType.displayCondensed(24))
                    .foregroundStyle(isSelected ? DeckPalette.cream : theme.onGround)
                Text(detail)
                    .font(DeckType.footnote)
                    .foregroundStyle(isSelected ? DeckPalette.cream.opacity(0.85)
                                                : theme.onGroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DeckSpace.m)
            .background(
                RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous)
                    .fill(isSelected ? theme.accent : theme.onGround.opacity(0.07))
            )
            .rotationEffect(isSelected ? .degrees(-1.2) : .zero)
            .deckShadow(isSelected ? .panel : .none)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var gamesForMode: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: mode == .solo
                        ? String(localized: "play.soloGames", defaultValue: "Play on your own")
                        : String(localized: "play.tableGames", defaultValue: "Play round a table"))
            if available.isEmpty {
                EmptyStateCard(title: String(localized: "play.empty.title",
                                             defaultValue: "YOUR TABLE IS EMPTY."),
                               message: String(localized: "play.empty.body",
                                               defaultValue: "No game in the library fits that mode yet."),
                               emblem: .binder)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DeckSpace.m)],
                          spacing: DeckSpace.m) {
                    ForEach(available, id: \.id) { definition in
                        GameShelfCard(definition: definition,
                                      isFavourite: deck.progress.settings.favouriteGameIDs.contains(definition.id),
                                      masteryLevel: deck.progress.mastery.level(for: definition.id)) {
                            router.push(.gameSetup(definition.id, mode: mode))
                        }
                    }
                }
            }
        }
    }

    private var available: [GameDefinition] {
        deck.registry.all.filter {
            mode == .solo ? $0.supportsSolo : $0.supportsPassAndPlay
        }
    }

    private var tableBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: String(localized: "play.whoIsHere", defaultValue: "Who is here"))
            HStack(spacing: DeckSpace.s) {
                ForEach(deck.progress.profiles.profiles) { profile in
                    VStack(spacing: DeckSpace.xxs) {
                        AvatarArt(avatarID: profile.avatarID, initials: profile.initials, size: 52)
                        Text(profile.name)
                            .font(DeckType.footnote)
                            .foregroundStyle(theme.onGround)
                            .lineLimit(1)
                    }
                }
                Button {
                    router.push(.profiles)
                } label: {
                    VStack(spacing: DeckSpace.xxs) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 52 * 0.28, style: .continuous)
                                .strokeBorder(theme.onGround.opacity(0.3),
                                              style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                .frame(width: 52, height: 52)
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(theme.onGroundMuted)
                        }
                        Text(String(localized: "play.addPlayer", defaultValue: "Add"))
                            .font(DeckType.footnote)
                            .foregroundStyle(theme.onGroundMuted)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }
}
