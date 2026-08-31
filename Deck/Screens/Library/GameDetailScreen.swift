import SwiftUI
import DeckCore
import DeckProgression

/// A game's own page.
///
/// The artwork fills the top and the page runs out of it — the same composition
/// the cover uses, opened up. Everything a player needs to decide is here, and
/// the two ways to start are the last things on the page.
public struct GameDetailScreen: View {
    private let gameID: GameID

    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme

    public init(gameID: GameID) {
        self.gameID = gameID
    }

    private var definition: GameDefinition? { deck.registry[gameID] }

    public var body: some View {
        Group {
            if let definition {
                content(definition)
            } else {
                DeckErrorView(message: String(localized: "game.unknown",
                                              defaultValue: "That game is not in the library."))
            }
        }
        .background(theme.ground.ignoresSafeArea())
    }

    private func content(_ definition: GameDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.l) {
                GameCoverArt(artworkID: definition.artworkID,
                             title: definition.englishName,
                             size: .hero,
                             seed: definition.id.rawValue.count)
                    .frame(height: 300)
                    .clipShape(TornEdge(side: .bottom, depth: 0.035,
                                        seed: definition.id.rawValue.count, teeth: 34))

                VStack(alignment: .leading, spacing: DeckSpace.l) {
                    tagline(definition)
                    factsRow(definition)
                    Text(LocalizedStringKey(definition.descriptionKey))
                        .font(DeckType.body)
                        .foregroundStyle(theme.onGround)
                        .fixedSize(horizontal: false, vertical: true)

                    masteryBlock(definition)
                    variantsBlock(definition)
                    statisticsBlock(definition)
                    achievementsBlock(definition)
                    actions(definition)
                }
                .padding(.horizontal, DeckSpace.page)
                .padding(.bottom, DeckSpace.xxxl)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }

    private func tagline(_ definition: GameDefinition) -> some View {
        HStack(alignment: .top) {
            Text(LocalizedStringKey(definition.taglineKey))
                .font(DeckType.displayCondensed(24))
                .foregroundStyle(theme.accent)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                toggleFavourite(definition.id)
            } label: {
                SuitShape(.heart, wobble: 0.02, seed: 4)
                    .fill(isFavourite ? DeckPalette.vermilion : theme.onGround.opacity(0.25))
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isFavourite
                                     ? String(localized: "library.unfavourite",
                                              defaultValue: "Remove from favourites")
                                     : String(localized: "library.favourite",
                                              defaultValue: "Add to favourites")))
        }
    }

    private var isFavourite: Bool {
        deck.progress.settings.favouriteGameIDs.contains(gameID)
    }

    private func toggleFavourite(_ id: GameID) {
        var settings = deck.progress.settings
        if let index = settings.favouriteGameIDs.firstIndex(of: id) {
            settings.favouriteGameIDs.remove(at: index)
        } else {
            settings.favouriteGameIDs.append(id)
        }
        deck.progress.update(settings: settings)
        Haptics.shared.tap(.light)
    }

    private func factsRow(_ definition: GameDefinition) -> some View {
        HStack(spacing: DeckSpace.xl) {
            fact(String(localized: "rules.players", defaultValue: "Players"),
                 definition.playerRange.lowerBound == definition.playerRange.upperBound
                    ? "\(definition.playerRange.lowerBound)"
                    : "\(definition.playerRange.lowerBound)–\(definition.playerRange.upperBound)")
            fact(String(localized: "rules.length", defaultValue: "Length"),
                 CalloutRow.humanised(definition.duration.localizationKey))
            fact(String(localized: "rules.complexity", defaultValue: "Learning"),
                 CalloutRow.humanised(definition.complexity.localizationKey))
            Spacer()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.onGroundMuted)
            Text(value)
                .font(DeckType.displayCondensed(20))
                .foregroundStyle(theme.onGround)
        }
    }

    @ViewBuilder
    private func masteryBlock(_ definition: GameDefinition) -> some View {
        let record = deck.progress.mastery.record(for: definition.id)
        if record.wins > 0 || record.achievementsUnlocked > 0 {
            VStack(alignment: .leading, spacing: DeckSpace.xs) {
                SectionRule(title: String(localized: "detail.mastery", defaultValue: "Mastery"))
                HStack(alignment: .bottom, spacing: DeckSpace.l) {
                    NumeralBlock(value: "\(record.wins)",
                                 unit: String(localized: "stat.wins", defaultValue: "Wins"),
                                 size: 44, colour: theme.onGround,
                                 unitColour: theme.onGroundMuted)
                    NumeralBlock(value: "\(record.achievementsUnlocked)/\(record.achievementsAvailable)",
                                 unit: String(localized: "stat.achievements",
                                              defaultValue: "Achievements"),
                                 size: 30, colour: theme.onGround,
                                 unitColour: theme.onGroundMuted)
                    Spacer()
                    if record.isMastered {
                        EmblemMark(.crown, colour: theme.accent, accent: theme.positive)
                            .frame(width: 46, height: 46)
                    }
                }
                ProgressRule(fraction: record.progressToNextLevel, colour: theme.accent)
                    .frame(height: 6)
                Text(LocalizedStringKey(record.levelKey))
                    .font(DeckType.caption)
                    .foregroundStyle(theme.onGroundMuted)
            }
        }
    }

    @ViewBuilder
    private func variantsBlock(_ definition: GameDefinition) -> some View {
        if !definition.variants.isEmpty {
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                SectionRule(title: String(localized: "detail.variants", defaultValue: "Variants"))
                ForEach(definition.variants) { variant in
                    HStack(alignment: .top, spacing: DeckSpace.s) {
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: DeckSpace.xxs) {
                                Text(LocalizedStringKey(variant.nameKey))
                                    .font(DeckType.bodyEmphasis)
                                    .foregroundStyle(theme.onGround)
                                if variant.requiresPremium && !deck.progress.hasPremium {
                                    Text(String(localized: "premium.badge", defaultValue: "PREMIUM"))
                                        .font(DeckType.unit)
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            Text(LocalizedStringKey(variant.summaryKey))
                                .font(DeckType.caption)
                                .foregroundStyle(theme.onGroundMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func statisticsBlock(_ definition: GameDefinition) -> some View {
        let record = deck.progress.statistics.record(for: definition.id)
        if record.gamesPlayed > 0 {
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                SectionRule(title: String(localized: "detail.yourRecord", defaultValue: "Your record"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DeckSpace.m)],
                          spacing: DeckSpace.m) {
                    StatTile(value: "\(record.gamesWon)",
                             label: String(localized: "stat.wins", defaultValue: "Wins"))
                    StatTile(value: "\(record.winRateBasisPoints / 100)%",
                             label: String(localized: "stat.winRate", defaultValue: "Win rate"))
                    if let fastest = record.fastestWinSeconds {
                        StatTile(value: String(format: "%d:%02d", fastest / 60, fastest % 60),
                                 label: String(localized: "stat.fastest", defaultValue: "Fastest"))
                    }
                    ForEach(definition.statistics.filter(\.isHeadline), id: \.key) { statistic in
                        if record.hasValue(for: statistic) {
                            StatTile(value: StatisticFormatting.text(record.value(for: statistic),
                                                                     format: statistic.format),
                                     label: CalloutRow.humanised(statistic.titleKey))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func achievementsBlock(_ definition: GameDefinition) -> some View {
        if !definition.achievements.isEmpty {
            VStack(alignment: .leading, spacing: DeckSpace.xs) {
                SectionRule(title: String(localized: "detail.achievements",
                                          defaultValue: "Achievements"))
                ForEach(definition.achievements) { achievement in
                    let entry = deck.progress.achievements.entries[achievement.id]
                    AchievementRow(definition: achievement,
                                   isUnlocked: entry?.isUnlocked ?? false,
                                   progress: entry?.fraction ?? 0,
                                   progressText: achievement.target > 1
                                        ? "\(entry?.progress ?? 0)/\(achievement.target)" : nil)
                }
            }
        }
    }

    private func actions(_ definition: GameDefinition) -> some View {
        VStack(spacing: DeckSpace.xs) {
            if definition.supportsSolo {
                DeckButton(String(localized: "detail.playSolo", defaultValue: "PLAY SOLO"),
                           emphasis: .primary) {
                    router.push(.gameSetup(definition.id, mode: .solo))
                }
            }
            if definition.supportsPassAndPlay {
                DeckButton(String(localized: "detail.passAndPlay", defaultValue: "PASS & PLAY"),
                           emphasis: .secondary) {
                    router.push(.gameSetup(definition.id, mode: .passAndPlay))
                }
            }
            DeckButton(String(localized: "detail.howToPlay", defaultValue: "HOW TO PLAY"),
                       emphasis: .quiet) {
                router.push(.rules(definition.id))
            }
        }
        .padding(.top, DeckSpace.s)
    }
}

/// One number with its label. The only repeated statistic layout in the app,
/// used where a grid genuinely is the clearest thing.
public struct StatTile: View {
    private let value: String
    private let label: String

    @Environment(\.deckTheme) private var theme

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DeckType.numeral(30))
                .foregroundStyle(theme.onGround)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(DeckType.footnote)
                .foregroundStyle(theme.onGroundMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DeckSpace.s)
        .background(
            RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                .fill(theme.onGround.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value)"))
    }
}

/// Formats a statistic according to the format its game declared.
public enum StatisticFormatting {
    public static func text(_ value: Int, format: StatisticDefinition.Format) -> String {
        switch format {
        case .integer:
            return "\(value)"
        case .duration:
            return String(format: "%d:%02d", value / 60, value % 60)
        case .percentage:
            return "\(value / 100)%"
        case .chips:
            return value.formatted(.number.grouping(.automatic))
        }
    }
}
