import SwiftUI
import DeckCore
import DeckProgression

/// Achievements.
///
/// Grouped by what they are about, with progress shown for the ones that are
/// counted. Everything visible has a stated target, so the list reads as things
/// to go and do rather than as things you have failed to do.
public struct AchievementsScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme

    @State private var category: AchievementCategory?

    public init() {}

    private var all: [AchievementDefinition] {
        deck.registry.allAchievements(global: GlobalAchievements.all)
    }

    private var filtered: [AchievementDefinition] {
        guard let category else { return all }
        return all.filter { $0.category == category }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.l) {
                header
                categoryPicker
                if filtered.isEmpty {
                    EmptyStateCard(title: String(localized: "achievements.empty.title",
                                                 defaultValue: "NOTHING HERE YET."),
                                   message: String(localized: "achievements.empty.body",
                                                   defaultValue: "Play a few games and this fills up fast."),
                                   emblem: .stamp)
                        .padding(.horizontal, DeckSpace.page)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { definition in
                            let entry = deck.progress.achievements.entries[definition.id]
                            AchievementRow(definition: definition,
                                           isUnlocked: entry?.isUnlocked ?? false,
                                           progress: entry?.fraction ?? 0,
                                           progressText: definition.target > 1
                                                ? "\(min(entry?.progress ?? 0, definition.target))/\(definition.target)"
                                                : nil)
                            Divider().opacity(0.15)
                        }
                    }
                    .padding(.horizontal, DeckSpace.page)
                }
            }
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(theme.ground.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
            DisplayText(String(localized: "achievements.title", defaultValue: "ACHIEVEMENTS"),
                        size: 46, colour: theme.onGround)
            Text(String(format: String(localized: "achievements.count",
                                       defaultValue: "%d of %d earned"),
                        deck.progress.achievements.unlockedCount, all.count))
                .font(DeckType.caption)
                .foregroundStyle(theme.onGroundMuted)
        }
        .padding(.horizontal, DeckSpace.page)
        .padding(.top, DeckSpace.m)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DeckSpace.xs) {
                chip(title: String(localized: "common.all", defaultValue: "All"), value: nil)
                ForEach(AchievementCategory.allCases) { value in
                    chip(title: CalloutRow.humanised(value.localizationKey), value: value)
                }
            }
            .padding(.horizontal, DeckSpace.page)
        }
    }

    private func chip(title: String, value: AchievementCategory?) -> some View {
        Button {
            withAnimation(DeckMotion.select) { category = value }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, DeckSpace.s)
                .frame(height: 36)
                .foregroundStyle(category == value ? DeckPalette.cream : theme.onGround)
                .background(
                    RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                        .fill(category == value ? theme.accent : theme.onGround.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == value ? [.isButton, .isSelected] : .isButton)
    }
}

/// Statistics.
///
/// The global numbers set large, then each game's own metrics — which the games
/// declared themselves, so a new game's statistics appear here without this
/// screen knowing anything about it.
public struct StatisticsScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme

    public init() {}

    private var global: StatisticsRecord { deck.progress.statistics.global }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.section) {
                header
                globalBlock
                perGameBlock
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(theme.ground.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        DisplayText(String(localized: "statistics.title", defaultValue: "STATISTICS"),
                    size: 50, colour: theme.onGround)
            .padding(.top, DeckSpace.m)
    }

    private var globalBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            HStack(alignment: .top, spacing: DeckSpace.xl) {
                NumeralBlock(value: "\(global.gamesPlayed)",
                             unit: String(localized: "stat.gamesPlayed", defaultValue: "Games"),
                             size: 62, colour: theme.onGround, unitColour: theme.onGroundMuted)
                NumeralBlock(value: "\(global.gamesWon)",
                             unit: String(localized: "stat.wins", defaultValue: "Wins"),
                             size: 62, colour: theme.accent, unitColour: theme.onGroundMuted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: DeckSpace.m)],
                      spacing: DeckSpace.m) {
                StatTile(value: "\(global.winRateBasisPoints / 100)%",
                         label: String(localized: "stat.winRate", defaultValue: "Win rate"))
                StatTile(value: duration(global.totalSeconds),
                         label: String(localized: "stat.playTime", defaultValue: "Play time"))
                StatTile(value: global.fastestWinSeconds.map { duration($0) } ?? "—",
                         label: String(localized: "stat.fastest", defaultValue: "Fastest win"))
                StatTile(value: duration(global.averageSeconds),
                         label: String(localized: "stat.average", defaultValue: "Average game"))
                StatTile(value: "\(global.passAndPlayGames)",
                         label: String(localized: "stat.passAndPlay", defaultValue: "Pass & Play"))
                StatTile(value: "\(global.soloGames)",
                         label: String(localized: "stat.solo", defaultValue: "Solo"))
                StatTile(value: "\(deck.progress.challenge.currentStreak)",
                         label: String(localized: "stat.streak", defaultValue: "Streak"))
                StatTile(value: "\(deck.progress.challenge.bestStreak)",
                         label: String(localized: "stat.bestStreak", defaultValue: "Best streak"))
                if let favourite = deck.progress.statistics.favouriteGame,
                   let definition = deck.registry[favourite] {
                    StatTile(value: definition.englishName,
                             label: String(localized: "stat.favourite", defaultValue: "Most played"))
                }
            }
        }
    }

    private var perGameBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            SectionRule(title: String(localized: "statistics.byGame", defaultValue: "By game"))
            ForEach(played, id: \.id) { definition in
                gameRow(definition)
            }
            if played.isEmpty {
                EmptyStateCard(title: String(localized: "statistics.empty.title",
                                             defaultValue: "NOTHING PLAYED YET."),
                               message: String(localized: "statistics.empty.body",
                                               defaultValue: "Finish a game and its numbers land here."),
                               emblem: .binder)
            }
        }
    }

    private var played: [GameDefinition] {
        deck.registry.all.filter { deck.progress.statistics.record(for: $0.id).gamesPlayed > 0 }
    }

    private func gameRow(_ definition: GameDefinition) -> some View {
        let record = deck.progress.statistics.record(for: definition.id)
        let mastery = deck.progress.mastery.record(for: definition.id)
        return VStack(alignment: .leading, spacing: DeckSpace.xs) {
            HStack(alignment: .center, spacing: DeckSpace.s) {
                GameCoverArt(artworkID: definition.artworkID,
                             title: definition.englishName,
                             size: .chip,
                             seed: definition.id.rawValue.count)
                    .frame(width: 44, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(definition.englishName)
                        .font(DeckType.displayCondensed(22))
                        .foregroundStyle(theme.onGround)
                    Text(String(format: String(localized: "stat.record",
                                               defaultValue: "%d played · %d won · %d%%"),
                                record.gamesPlayed, record.gamesWon,
                                record.winRateBasisPoints / 100))
                        .font(DeckType.footnote)
                        .foregroundStyle(theme.onGroundMuted)
                }
                Spacer()
                if mastery.isMastered {
                    EmblemMark(.crown, colour: theme.accent, accent: theme.positive)
                        .frame(width: 26, height: 26)
                }
            }
            let headline = definition.statistics.filter { record.hasValue(for: $0) }
            if !headline.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: DeckSpace.xs)],
                          spacing: DeckSpace.xs) {
                    ForEach(headline, id: \.key) { statistic in
                        StatTile(value: StatisticFormatting.text(record.value(for: statistic),
                                                                 format: statistic.format),
                                 label: CalloutRow.humanised(statistic.titleKey))
                    }
                }
            }
        }
        .padding(.bottom, DeckSpace.s)
    }

    private func duration(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%dh %dm", seconds / 3600, (seconds % 3600) / 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
