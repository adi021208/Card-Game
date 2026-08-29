import SwiftUI
import DeckCore
import DeckProgression

/// One achievement in a list.
///
/// Locked ones still show what they are, because an achievement nobody can see
/// is not something to aim at. The only exception is the handful marked secret.
public struct AchievementRow: View {
    private let definition: AchievementDefinition
    private let isUnlocked: Bool
    private let progress: Double
    private let progressText: String?

    @Environment(\.deckTheme) private var theme

    public init(definition: AchievementDefinition,
                isUnlocked: Bool,
                progress: Double,
                progressText: String? = nil) {
        self.definition = definition
        self.isUnlocked = isUnlocked
        self.progress = progress
        self.progressText = progressText
    }

    private var isHidden: Bool { definition.isSecret && !isUnlocked }

    public var body: some View {
        HStack(alignment: .center, spacing: DeckSpace.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                    .fill(isUnlocked ? theme.accent.opacity(0.16) : theme.onGround.opacity(0.06))
                EmblemMark(definition.emblem,
                           colour: isUnlocked ? theme.accent : theme.onGround.opacity(0.35),
                           accent: isUnlocked ? theme.onGround.opacity(0.45) : .clear,
                           seed: definition.id.count)
                    .frame(width: 34, height: 34)
            }
            .frame(width: 54, height: 54)
            .rotationEffect(isUnlocked
                            ? DeckMotion.settledAngle(seed: definition.id.count, spread: 3)
                            : .zero)

            VStack(alignment: .leading, spacing: 3) {
                Text(isHidden
                     ? String(localized: "achievement.secret", defaultValue: "Secret")
                     : title)
                    .font(DeckType.bodyEmphasis)
                    .foregroundStyle(theme.onGround)
                Text(isHidden
                     ? String(localized: "achievement.secret.detail",
                              defaultValue: "You will know it when you do it.")
                     : detail)
                    .font(DeckType.footnote)
                    .foregroundStyle(theme.onGroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if !isUnlocked && definition.target > 1 {
                    ProgressRule(fraction: progress, colour: theme.accent)
                        .frame(height: 5)
                }
            }
            Spacer(minLength: 0)
            if let progressText, !isUnlocked {
                Text(progressText)
                    .font(DeckType.tabular(13, weight: .bold))
                    .foregroundStyle(theme.onGroundMuted)
            } else if isUnlocked {
                TickMark()
                    .stroke(theme.positive, style: StrokeStyle(lineWidth: 3,
                                                               lineCap: .round,
                                                               lineJoin: .round))
                    .frame(width: 18, height: 14)
            }
        }
        .padding(.vertical, DeckSpace.xs)
        .opacity(isUnlocked ? 1 : 0.82)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isHidden ? String(localized: "achievement.secret",
                                                    defaultValue: "Secret") : title))
        .accessibilityValue(Text(isUnlocked
                                 ? String(localized: "achievement.unlocked", defaultValue: "Unlocked")
                                 : (progressText ?? "")))
    }

    private var title: String {
        String.deck(definition.titleKey, or: CalloutRow.humanised(definition.titleKey))
    }

    private var detail: String {
        String.deck(definition.descriptionKey, or: CalloutRow.humanised(definition.descriptionKey))
    }
}

/// Progress drawn as a painted rule filling up, not a rounded capsule.
public struct ProgressRule: View {
    private let fraction: Double
    private let colour: Color

    @Environment(\.deckTheme) private var theme

    public init(fraction: Double, colour: Color) {
        self.fraction = min(1, max(0, fraction))
        self.colour = colour
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.onGround.opacity(0.12))
                PaintStroke(bow: 0.0, weight: 1.0, seed: 17, progress: 1)
                    .fill(colour)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A cosmetic in the collection, drawn as the thing itself.
public struct CosmeticThumbnail: View {
    private let cosmetic: Cosmetic
    private let size: CGFloat

    @Environment(\.deckTheme) private var theme

    public init(cosmetic: Cosmetic, size: CGFloat = 72) {
        self.cosmetic = cosmetic
        self.size = size
    }

    public var body: some View {
        Group {
            switch cosmetic.kind {
            case .cardBack:
                CardBackArt(styleID: cosmetic.id, theme: theme)
                    .frame(width: size, height: CardMetrics.height(forWidth: size))
            case .avatar:
                AvatarArt(avatarID: cosmetic.id, size: size)
            case .theme:
                themeSwatch
            case .table:
                tableSwatch
            case .soundPack:
                soundSwatch
            }
        }
        .accessibilityHidden(true)
    }

    private var themeSwatch: some View {
        let resolved = DeckTheme.theme(cosmetic.id)
        return ZStack {
            resolved.ground
            VStack(spacing: 0) {
                Rectangle().fill(resolved.accent).frame(height: size * 0.22)
                Rectangle().fill(resolved.surface).frame(height: size * 0.22)
            }
            .frame(width: size * 0.62)
            .rotationEffect(.degrees(-14))
        }
        .frame(width: size, height: CardMetrics.height(forWidth: size))
        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
    }

    private var tableSwatch: some View {
        ZStack {
            DeckPalette.token(cosmetic.palette.first ?? "ink")
            SuitShape(.club, wobble: 0.02, seed: cosmetic.id.count)
                .fill(DeckPalette.token(cosmetic.palette.last ?? "cream").opacity(0.35))
                .frame(width: size * 0.7, height: size * 0.7)
                .offset(x: size * 0.2, y: -size * 0.1)
        }
        .frame(width: size, height: CardMetrics.height(forWidth: size))
        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
    }

    private var soundSwatch: some View {
        ZStack {
            theme.onGround.opacity(0.08)
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: 4, height: size * (0.2 + Double(index % 3) * 0.22))
                }
            }
        }
        .frame(width: size, height: CardMetrics.height(forWidth: size))
        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
    }
}
