import SwiftUI
import DeckCore
import DeckProgression

/// Today's challenge, as a poster.
///
/// The centrepiece of the app: the game's own artwork under an oversized
/// headline, with the difficulty, the boss and the objective stated plainly on
/// top of it. It reads as one printed object rather than as a card containing
/// four smaller cards.
public struct ChallengePoster: View {
    private let challenge: DailyChallenge
    private let definition: GameDefinition
    private let isCompleted: Bool
    private let attemptsRemaining: Int?
    private let bestScore: Int?
    private let bestTime: Int?
    private let canPlay: Bool
    private let onPlay: () -> Void
    private let onUpgrade: () -> Void

    @Environment(\.deckTheme) private var theme

    public init(challenge: DailyChallenge,
                definition: GameDefinition,
                isCompleted: Bool,
                attemptsRemaining: Int?,
                bestScore: Int?,
                bestTime: Int?,
                canPlay: Bool,
                onPlay: @escaping () -> Void,
                onUpgrade: @escaping () -> Void) {
        self.challenge = challenge
        self.definition = definition
        self.isCompleted = isCompleted
        self.attemptsRemaining = attemptsRemaining
        self.bestScore = bestScore
        self.bestTime = bestTime
        self.canPlay = canPlay
        self.onPlay = onPlay
        self.onUpgrade = onUpgrade
    }

    private var boss: Boss? {
        challenge.bossID.flatMap { BossCast.boss($0) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artworkBlock
            detailBlock
        }
        .background(
            RoundedRectangle(cornerRadius: DeckRadius.poster, style: .continuous)
                .fill(theme.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.poster, style: .continuous))
        .deckShadow(DeckShadow(colour: .black.opacity(0.35), radius: 0, x: 0, y: 6))
        .overlay(alignment: .topTrailing) { completedStamp }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Artwork

    private var artworkBlock: some View {
        ZStack(alignment: .topLeading) {
            GameCoverArt(artworkID: definition.artworkID,
                         title: definition.englishName,
                         size: .hero,
                         seed: challenge.date.day)
                .frame(height: 236)

            VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                Text(String(localized: "today.label", defaultValue: "TODAY"))
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking * 2)
                    .foregroundStyle(DeckPalette.cream)
                    .padding(.horizontal, DeckSpace.xs)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                            .fill(DeckPalette.ink)
                    )
                    .rotationEffect(.degrees(-2.5))
            }
            .padding(DeckSpace.m)
        }
        .overlay(alignment: .bottomTrailing) { difficultyMark }
    }

    /// The difficulty as a printed percentage, big enough to matter.
    private var difficultyMark: some View {
        let percent = challenge.difficultyPercent
        let sign = percent >= 0 ? "+" : ""
        return HStack(spacing: DeckSpace.xxs) {
            Text("\(sign)\(percent)%")
                .font(DeckType.numeral(30))
                .foregroundStyle(DeckPalette.ink)
        }
        .padding(.horizontal, DeckSpace.s)
        .padding(.vertical, DeckSpace.xxs)
        .background(
            RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                .fill(percent >= 100 ? DeckPalette.vermilion : DeckPalette.acid)
        )
        .rotationEffect(.degrees(-3))
        .padding(DeckSpace.m)
        .accessibilityLabel(Text(String(format: String(localized: "challenge.difficulty",
                                                       defaultValue: "Difficulty %@%d percent"),
                                        sign, percent)))
    }

    // MARK: - Detail

    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            if let boss {
                bossRow(boss)
            }

            VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                Text(String(localized: "challenge.objective", defaultValue: "Objective"))
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.ink.opacity(0.55))
                Text(challenge.objective.englishDescription)
                    .font(DeckType.bodyEmphasis)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let boss {
                ForEach(Array(boss.modifiers.enumerated()), id: \.offset) { entry in
                    HStack(alignment: .top, spacing: DeckSpace.xs) {
                        Rectangle()
                            .fill(DeckPalette.token(boss.colourToken))
                            .frame(width: 3)
                            .frame(maxHeight: .infinity)
                        Text(entry.element.englishExplanation)
                            .font(DeckType.caption)
                            .foregroundStyle(theme.ink.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            recordRow

            if isCompleted {
                DeckButton(String(localized: "challenge.done", defaultValue: "COMPLETED"),
                           emphasis: .secondary, isEnabled: false) {}
            } else if canPlay {
                DeckButton(String(localized: "challenge.play", defaultValue: "PLAY"),
                           emphasis: .primary,
                           action: onPlay)
            } else {
                VStack(spacing: DeckSpace.xs) {
                    Text(String(localized: "challenge.noAttempts",
                                defaultValue: "You have used today's three attempts."))
                        .font(DeckType.caption)
                        .foregroundStyle(theme.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                    DeckButton(String(localized: "challenge.unlimited",
                                      defaultValue: "GET UNLIMITED ATTEMPTS"),
                               emphasis: .secondary,
                               action: onUpgrade)
                }
            }
        }
        .padding(DeckSpace.m)
    }

    private func bossRow(_ boss: Boss) -> some View {
        HStack(spacing: DeckSpace.s) {
            BossPortrait(boss: boss, isAnimated: true, showsGround: true)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "challenge.boss", defaultValue: "BOSS"))
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking)
                    .foregroundStyle(theme.ink.opacity(0.55))
                Text(boss.displayName.uppercased())
                    .font(DeckType.display(30))
                    .foregroundStyle(DeckPalette.token(boss.colourToken))
            }
            Spacer()
        }
    }

    private var recordRow: some View {
        HStack(spacing: DeckSpace.l) {
            if let bestTime, bestTime > 0 {
                statColumn(value: formatted(seconds: bestTime),
                           label: String(localized: "challenge.best", defaultValue: "Best"))
            } else if let bestScore {
                statColumn(value: "\(bestScore)",
                           label: String(localized: "challenge.best", defaultValue: "Best"))
            }
            Spacer()
            if let attemptsRemaining {
                VStack(alignment: .trailing, spacing: DeckSpace.xxs) {
                    Text(String(localized: "challenge.attempts", defaultValue: "Attempts"))
                        .font(DeckType.unit)
                        .tracking(DeckType.unitTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.ink.opacity(0.55))
                    AttemptMarks(total: ChallengeLedger.freeAttemptsPerDay,
                                 remaining: attemptsRemaining)
                }
            } else {
                UnlimitedAttemptsMark()
            }
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
            Text(label)
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.ink.opacity(0.55))
            Text(value)
                .font(DeckType.tabular(24, weight: .black))
                .foregroundStyle(theme.ink)
        }
    }

    /// A rubber stamp lands over the poster once the day is done.
    @ViewBuilder
    private var completedStamp: some View {
        if isCompleted {
            ZStack {
                StampOutline(form: .circle, seed: challenge.date.day, breakUp: 0.18)
                    .stroke(DeckPalette.forest, lineWidth: 4)
                Text(String(localized: "challenge.stamp", defaultValue: "DONE"))
                    .font(DeckType.display(26))
                    .foregroundStyle(DeckPalette.forest)
            }
            .frame(width: 96, height: 96)
            .rotationEffect(.degrees(-14))
            .padding(DeckSpace.m)
            .accessibilityLabel(Text(String(localized: "challenge.completed",
                                            defaultValue: "Completed")))
        }
    }

    private func formatted(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
