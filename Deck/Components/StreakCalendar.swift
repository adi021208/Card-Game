import SwiftUI
import DeckCore
import DeckProgression

/// The streak, as a run of days you can read at a glance.
///
/// Not a calendar grid: a horizontal strip of marks, each one drawn rather than
/// filled in. A completed day gets a hand-stamped tick, a failed one a struck
/// box, today an open frame with the accent inside it. The whole thing is about
/// two centimetres tall and tells you everything.
public struct StreakStrip: View {
    private let progress: ChallengeProgress
    private let today: ChallengeDate
    private let dayCount: Int

    @Environment(\.deckTheme) private var theme

    public init(progress: ChallengeProgress, today: ChallengeDate, dayCount: Int = 14) {
        self.progress = progress
        self.today = today
        self.dayCount = dayCount
    }

    private enum DayState {
        case completed, failed, today, upcoming, untouched
    }

    private var days: [(date: ChallengeDate, state: DayState)] {
        (0..<dayCount).reversed().map { offset in
            let date = today.adding(days: -offset)
            let state: DayState
            if progress.completedDays.contains(date) {
                state = .completed
            } else if date == today {
                state = .today
            } else if progress.failedDays.contains(date) {
                state = .failed
            } else if date > today {
                state = .upcoming
            } else {
                state = .untouched
            }
            return (date, state)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            HStack(alignment: .lastTextBaseline, spacing: DeckSpace.s) {
                NumeralBlock(value: "\(progress.currentStreak)",
                             unit: String(localized: "streak.dayStreak", defaultValue: "Day streak"),
                             size: 76,
                             colour: theme.accent,
                             unitColour: theme.onGroundMuted)
                Spacer(minLength: 0)
                if progress.bestStreak > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(progress.bestStreak)")
                            .font(DeckType.tabular(22, weight: .black))
                            .foregroundStyle(theme.onGround)
                        Text(String(localized: "streak.best", defaultValue: "Best"))
                            .font(DeckType.unit)
                            .tracking(DeckType.unitTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.onGroundMuted)
                    }
                }
            }

            HStack(spacing: DeckSpace.xxs) {
                ForEach(days, id: \.date) { entry in
                    dayMark(entry.state, seed: entry.date.day &* 31 &+ entry.date.month)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    private func dayMark(_ state: DayState, seed: Int) -> some View {
        switch state {
        case .completed:
            ZStack {
                RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                    .fill(theme.accent)
                TickMark()
                    .stroke(DeckPalette.cream, style: StrokeStyle(lineWidth: 2.6,
                                                                  lineCap: .round,
                                                                  lineJoin: .round))
                    .padding(7)
            }
            .rotationEffect(DeckMotion.settledAngle(seed: seed, spread: 4))
        case .failed:
            ZStack {
                RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                    .strokeBorder(theme.onGroundMuted, lineWidth: 2)
                Path { path in
                    path.move(to: CGPoint(x: 6, y: 24))
                    path.addLine(to: CGPoint(x: 24, y: 6))
                }
                .stroke(theme.onGroundMuted, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            .rotationEffect(DeckMotion.settledAngle(seed: seed, spread: 3))
        case .today:
            ZStack {
                RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: 3)
                Circle()
                    .fill(theme.accent)
                    .frame(width: 9, height: 9)
            }
        case .upcoming:
            RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                .strokeBorder(theme.onGround.opacity(0.16),
                              style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        case .untouched:
            RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                .fill(theme.onGround.opacity(0.10))
        }
    }

    private var accessibilityLabel: String {
        let completed = days.filter { $0.state == .completed }.count
        return String(format: String(localized: "streak.accessibility",
                                     defaultValue: "Streak %d days, best %d. %d of the last %d days completed."),
                      progress.currentStreak, progress.bestStreak, completed, dayCount)
    }
}

/// A hand-drawn tick.
public struct TickMark: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// The attempts left today, drawn as card backs being spent rather than as a
/// row of hearts.
public struct AttemptMarks: View {
    private let total: Int
    private let remaining: Int

    @Environment(\.deckTheme) private var theme

    public init(total: Int, remaining: Int) {
        self.total = total
        self.remaining = remaining
    }

    public var body: some View {
        HStack(spacing: DeckSpace.xxs) {
            ForEach(0..<max(0, total), id: \.self) { index in
                let isSpent = index >= remaining
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(isSpent ? theme.onGround.opacity(0.15) : theme.accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(isSpent ? theme.onGround.opacity(0.25) : .clear, lineWidth: 1.5)
                    )
                    .frame(width: 14, height: 20)
                    .rotationEffect(DeckMotion.settledAngle(seed: index &* 17, spread: 6))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(format: String(localized: "attempts.remaining",
                                                       defaultValue: "%d of %d attempts left"),
                                        remaining, total)))
    }
}

/// The unlimited-attempts badge for premium players.
public struct UnlimitedAttemptsMark: View {
    @Environment(\.deckTheme) private var theme
    public init() {}
    public var body: some View {
        HStack(spacing: DeckSpace.xxs) {
            Text("∞")
                .font(DeckType.numeral(22))
                .foregroundStyle(theme.accent)
            Text(String(localized: "attempts.unlimited", defaultValue: "Unlimited"))
                .font(DeckType.caption)
                .foregroundStyle(theme.onGroundMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
