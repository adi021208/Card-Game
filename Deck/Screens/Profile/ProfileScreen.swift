import SwiftUI
import DeckCore
import DeckProgression

/// The player's own page.
///
/// A player card, not a social profile: who you are, what you have done, and the
/// way into everything you have collected. There is no feed and no follower
/// count, because there is nobody to follow.
public struct ProfileScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme

    public init() {}

    private var profile: PlayerProfile? { deck.progress.profiles.primary }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.section) {
                playerCard
                quickNumbers
                links
                recentGames
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
            PaperGrain(intensity: theme.grain, seed: 9, tint: theme.isDark ? .white : .black)
                .opacity(theme.isDark ? 0.25 : 1)
        }
        .ignoresSafeArea()
    }

    /// The card is deliberately built like one: a rectangle with a torn edge, a
    /// portrait, a name set in poster type and the numbers printed on it.
    private var playerCard: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            HStack(alignment: .center, spacing: DeckSpace.m) {
                AvatarArt(avatarID: profile?.avatarID ?? "avatar.default",
                          initials: profile?.initials ?? "",
                          size: 76)
                VStack(alignment: .leading, spacing: 2) {
                    Text((profile?.name ?? "You").uppercased())
                        .font(DeckType.display(40))
                        .foregroundStyle(DeckPalette.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let favourite = deck.progress.statistics.favouriteGame,
                       let definition = deck.registry[favourite] {
                        Text(String(format: String(localized: "profile.playsMost",
                                                   defaultValue: "Plays %@ most"),
                                    definition.englishName))
                            .font(DeckType.caption)
                            .foregroundStyle(DeckPalette.ink.opacity(0.7))
                    }
                }
                Spacer()
            }
            HStack(spacing: DeckSpace.l) {
                cardStat("\(deck.progress.challenge.currentStreak)",
                         String(localized: "streak.dayStreak", defaultValue: "Day streak"))
                cardStat("\(deck.progress.statistics.global.gamesWon)",
                         String(localized: "stat.wins", defaultValue: "Wins"))
                cardStat("\(deck.progress.achievements.unlockedCount)",
                         String(localized: "stat.achievements", defaultValue: "Achievements"))
                Spacer()
            }
        }
        .padding(DeckSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                theme.surface
                HalftoneField(colour: theme.accent.opacity(0.18), cell: 11, direction: .topTrailing)
            }
        )
        .clipShape(TornEdge(side: .bottom, depth: 0.04, seed: 14, teeth: 30))
        .deckShadow(.panel)
        .padding(.top, DeckSpace.m)
        .accessibilityElement(children: .contain)
    }

    private func cardStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(DeckType.numeral(30))
                .foregroundStyle(DeckPalette.ink)
            Text(label)
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking)
                .textCase(.uppercase)
                .foregroundStyle(DeckPalette.ink.opacity(0.65))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value)"))
    }

    private var quickNumbers: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: String(localized: "profile.mastery", defaultValue: "Mastery"))
            let mastered = deck.registry.all.filter { deck.progress.mastery.record(for: $0.id).isMastered }
            if mastered.isEmpty {
                Text(String(localized: "profile.masteryEmpty",
                            defaultValue: "Master a game by winning it, earning its achievements and beating an expert."))
                    .font(DeckType.caption)
                    .foregroundStyle(theme.onGroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(deck.registry.all.sorted { deck.progress.mastery.level(for: $0.id) > deck.progress.mastery.level(for: $1.id) }.prefix(5), id: \.id) { definition in
                let record = deck.progress.mastery.record(for: definition.id)
                HStack(spacing: DeckSpace.s) {
                    Text(definition.englishName)
                        .font(DeckType.bodyEmphasis)
                        .foregroundStyle(theme.onGround)
                        .frame(width: 116, alignment: .leading)
                        .lineLimit(1)
                    ProgressRule(fraction: Double(record.level) / 4.0, colour: theme.accent)
                        .frame(height: 8)
                    Text(LocalizedStringKey(record.levelKey))
                        .font(DeckType.footnote)
                        .foregroundStyle(theme.onGroundMuted)
                        .frame(width: 80, alignment: .trailing)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var links: some View {
        VStack(spacing: DeckSpace.xs) {
            linkRow(String(localized: "profile.achievements", defaultValue: "Achievements"),
                    detail: "\(deck.progress.achievements.unlockedCount)") {
                router.push(.achievements)
            }
            linkRow(String(localized: "profile.statistics", defaultValue: "Statistics"),
                    detail: "\(deck.progress.statistics.global.gamesPlayed)") {
                router.push(.statistics)
            }
            linkRow(String(localized: "profile.history", defaultValue: "Recent games"),
                    detail: "\(deck.progress.history.entries.count)") {
                router.push(.history)
            }
            linkRow(String(localized: "profile.players", defaultValue: "Players on this device"),
                    detail: "\(deck.progress.profiles.profiles.count)") {
                router.push(.profiles)
            }
            linkRow(String(localized: "profile.leaderboards", defaultValue: "Leaderboards"),
                    detail: deck.gameServices.isAuthenticated
                        ? String(localized: "gamecenter.connected", defaultValue: "Connected")
                        : String(localized: "gamecenter.notConnected", defaultValue: "Not signed in")) {
                router.push(.leaderboards)
            }
            linkRow(String(localized: "profile.settings", defaultValue: "Settings"), detail: nil) {
                router.push(.settings)
            }
        }
    }

    private func linkRow(_ title: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(DeckType.body)
                    .foregroundStyle(theme.onGround)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(DeckType.tabular(15, weight: .semibold))
                        .foregroundStyle(theme.onGroundMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.onGroundMuted)
            }
            .padding(.vertical, DeckSpace.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recentGames: some View {
        let entries = Array(deck.progress.history.entries.prefix(5))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                SectionRule(title: String(localized: "profile.recent", defaultValue: "Last few games"))
                ForEach(entries) { entry in
                    HistoryRow(entry: entry, gameName: deck.registry[entry.gameID]?.englishName ?? "")
                }
            }
        }
    }
}

/// One finished game in the history list.
public struct HistoryRow: View {
    private let entry: GameHistoryEntry
    private let gameName: String

    @Environment(\.deckTheme) private var theme

    public init(entry: GameHistoryEntry, gameName: String) {
        self.entry = entry
        self.gameName = gameName
    }

    public var body: some View {
        HStack(spacing: DeckSpace.s) {
            Rectangle()
                .fill(outcomeColour)
                .frame(width: 4, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(gameName)
                    .font(DeckType.bodyEmphasis)
                    .foregroundStyle(theme.onGround)
                Text(subtitle)
                    .font(DeckType.footnote)
                    .foregroundStyle(theme.onGroundMuted)
                    .lineLimit(1)
            }
            Spacer()
            Text(outcomeText)
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking)
                .foregroundStyle(outcomeColour)
        }
        .accessibilityElement(children: .combine)
    }

    private var outcomeColour: Color {
        switch entry.outcome {
        case .win: return theme.positive
        case .loss: return theme.alert
        default: return theme.onGroundMuted
        }
    }

    private var outcomeText: String {
        switch entry.outcome {
        case .win: return String(localized: "result.wonShort", defaultValue: "WON")
        case .loss: return String(localized: "result.lostShort", defaultValue: "LOST")
        case .draw: return String(localized: "result.drawShort", defaultValue: "DREW")
        case .abandoned: return String(localized: "result.leftShort", defaultValue: "LEFT")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if entry.wasChallenge {
            parts.append(String(localized: "history.challenge", defaultValue: "Daily"))
        }
        if entry.wasPassAndPlay {
            parts.append(String(localized: "mode.passAndPlay", defaultValue: "Pass & Play"))
        }
        if !entry.opponents.isEmpty {
            parts.append(entry.opponents.prefix(3).joined(separator: ", "))
        }
        parts.append(String(format: "%d:%02d", entry.durationSeconds / 60, entry.durationSeconds % 60))
        return parts.joined(separator: " · ")
    }
}
