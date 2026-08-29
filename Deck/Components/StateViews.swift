import SwiftUI
import DeckCore

/// An empty state.
///
/// Never a grey icon and the words "no data". An empty state is a designed
/// composition with a drawn mark, a sentence that says what the space is for,
/// and — where there is one — the action that fills it.
public struct EmptyStateCard: View {
    private let title: String
    private let message: String
    private let emblem: AchievementEmblem
    private let actionTitle: String?
    private let action: (() -> Void)?

    @Environment(\.deckTheme) private var theme

    public init(title: String,
                message: String,
                emblem: AchievementEmblem = .binder,
                actionTitle: String? = nil,
                action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.emblem = emblem
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            ZStack(alignment: .topLeading) {
                ScatterMarks(colour: theme.onGround.opacity(0.3), seed: 6, count: 10)
                    .frame(height: 120)
                EmblemMark(emblem, colour: theme.accent, accent: theme.onGround.opacity(0.35))
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(-6))
                    .padding(.leading, DeckSpace.xs)
            }
            .frame(height: 120)

            DisplayText(title, size: 34, colour: theme.onGround)
            Text(message)
                .font(DeckType.body)
                .foregroundStyle(theme.onGroundMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                DeckButton(actionTitle, emphasis: .secondary, action: action)
            }
        }
        .padding(DeckSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DeckRadius.poster, style: .continuous)
                .fill(theme.onGround.opacity(0.05))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Something went wrong.
///
/// Written the way a person would say it, with the reassuring part first,
/// because the thing people actually want to know is whether they lost anything.
public struct DeckErrorView: View {
    private let title: String
    private let message: String
    private let retryTitle: String?
    private let onRetry: (() -> Void)?

    @Environment(\.deckTheme) private var theme

    public init(title: String = String(localized: "error.title", defaultValue: "THE DECK GOT LOST."),
                message: String,
                retryTitle: String? = nil,
                onRetry: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(index == 0 ? theme.accent : theme.surface)
                        .frame(width: 46, height: 64)
                        .rotationEffect(.degrees(Double(index) * 27 - 40))
                        .offset(x: CGFloat(index) * 14 - 20, y: CGFloat(index % 2) * 8)
                }
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity, alignment: .leading)

            DisplayText(title, size: 32, colour: theme.onGround)
            Text(message)
                .font(DeckType.body)
                .foregroundStyle(theme.onGroundMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let retryTitle, let onRetry {
                DeckButton(retryTitle, emphasis: .primary, action: onRetry)
            }
        }
        .padding(DeckSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A short line of table state — the suit in play, the pot, the trump.
///
/// The primary one is set large; the rest sit quietly beside it. There is no
/// pill, no badge and no border.
public struct CalloutRow: View {
    private let callouts: [TableCallout]

    @Environment(\.deckTheme) private var theme

    public init(callouts: [TableCallout]) {
        self.callouts = callouts
    }

    public var body: some View {
        HStack(alignment: .center, spacing: DeckSpace.m) {
            ForEach(callouts) { callout in
                HStack(spacing: DeckSpace.xxs) {
                    if let suit = callout.suit {
                        SuitShape(SuitShape.Kind(suitToken: suit.token))
                            .fill(colour(for: callout))
                            .frame(width: fontSize(for: callout) * 0.9,
                                   height: fontSize(for: callout) * 0.9)
                    }
                    Text(text(for: callout))
                        .font(callout.emphasis == .primary
                              ? DeckType.displayCondensed(fontSize(for: callout))
                              : DeckType.caption)
                        .foregroundStyle(colour(for: callout))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func fontSize(for callout: TableCallout) -> CGFloat {
        callout.emphasis == .primary ? 22 : 13
    }

    private func colour(for callout: TableCallout) -> Color {
        switch callout.emphasis {
        case .primary: return theme.onGround
        case .secondary: return theme.onGroundMuted
        case .alert: return theme.alert
        }
    }

    /// Renders a callout's localised text with its arguments substituted.
    private func text(for callout: TableCallout) -> String {
        let format = String.deck(callout.labelKey, or: fallback(for: callout))
        return CalloutRow.interpolate(format, arguments: callout.arguments)
    }

    /// A readable English fallback so a missing translation never shows a key.
    private func fallback(for callout: TableCallout) -> String {
        switch callout.id {
        case "pot": return "Pot %@"
        case "suit": return "%@ in play"
        case "led": return "%@ led"
        case "target": return "Playing to %@"
        case "stock": return "%@ in the deck"
        case "moves": return "%@ moves"
        case "score": return "%@"
        default: return callout.arguments.isEmpty ? callout.id : "%@"
        }
    }

    /// Substitutes `%@` placeholders one at a time, translating any argument
    /// that is itself a localisation key (suit and rank names arrive this way).
    static func interpolate(_ format: String, arguments: [String]) -> String {
        var result = format
        for argument in arguments {
            let value = argument.contains(".")
                ? String.deck(argument, or: Self.humanised(argument))
                : argument
            if let range = result.range(of: "%@") {
                result.replaceSubrange(range, with: value)
            } else {
                result += " \(value)"
            }
        }
        return result
    }

    /// Turns `suit.hearts` into `Hearts` when no translation exists.
    static func humanised(_ key: String) -> String {
        guard let last = key.split(separator: ".").last else { return key }
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
