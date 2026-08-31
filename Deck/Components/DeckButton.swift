import SwiftUI

/// The primary control.
///
/// A physical object: it has a shadow, it compresses when pressed, and it sits
/// on the page rather than floating over it. No pill, no gradient, no glass.
public struct DeckButton: View {
    public enum Emphasis {
        /// The one thing to do on this screen.
        case primary
        /// A real alternative.
        case secondary
        /// Available, but not the point.
        case quiet
        /// Something that ends or removes.
        case destructive
    }

    private let title: String
    private let emphasis: Emphasis
    private let icon: String?
    private let isEnabled: Bool
    private let action: () -> Void

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var isPressed = false

    public init(_ title: String,
                emphasis: Emphasis = .primary,
                icon: String? = nil,
                isEnabled: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.emphasis = emphasis
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: {
            guard isEnabled else { return }
            Haptics.shared.tap(.press)
            action()
        }) {
            HStack(spacing: DeckSpace.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(titleFont)
                    .tracking(emphasis == .primary ? 0.4 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, DeckSpace.l)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
            .overlay(edge)
            .deckShadow(isPressed || !isEnabled ? .none : shadow)
            .scaleEffect(isPressed ? 0.975 : 1)
            .offset(y: isPressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(DeckMotion.respectingReduceMotion(DeckMotion.select, reduced: reducedMotion),
                   value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        // 52 points is comfortably above the 44-point minimum, and the tap area
        // extends to the full width of the control.
        .accessibilityAddTraits(.isButton)
    }

    private var titleFont: Font {
        switch emphasis {
        case .primary: return Font.system(size: 17, weight: .heavy)
        case .secondary: return Font.system(size: 16, weight: .bold)
        case .quiet, .destructive: return Font.system(size: 16, weight: .semibold)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch emphasis {
        case .primary:
            ZStack {
                theme.accent
                PaperGrain(intensity: 0.12, seed: 42, tint: .black)
            }
        case .secondary:
            theme.surface
        case .quiet:
            Color.clear
        case .destructive:
            DeckPalette.crimson
        }
    }

    private var foreground: Color {
        switch emphasis {
        case .primary: return DeckPalette.cream
        case .secondary: return theme.ink
        case .quiet: return theme.onGround
        case .destructive: return DeckPalette.cream
        }
    }

    @ViewBuilder
    private var edge: some View {
        switch emphasis {
        case .quiet:
            RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                .strokeBorder(theme.onGround.opacity(0.25), lineWidth: 1.5)
        case .secondary:
            RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                .strokeBorder(theme.ink.opacity(0.18), lineWidth: 1)
        default:
            EmptyView()
        }
    }

    private var shadow: DeckShadow {
        emphasis == .primary ? DeckShadow(colour: .black.opacity(0.28), radius: 0, x: 0, y: 4)
                             : DeckShadow(colour: .black.opacity(0.18), radius: 0, x: 0, y: 3)
    }
}

/// A small icon control for the game table: pause, rules, hint.
/// Icons only where the meaning is unambiguous, and always with a label for
/// VoiceOver.
public struct DeckIconButton: View {
    private let systemImage: String
    private let label: String
    private let isEnabled: Bool
    private let action: () -> Void

    @Environment(\.deckTheme) private var theme
    @State private var isPressed = false

    public init(systemImage: String, label: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: {
            Haptics.shared.tap(.light)
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.onGround)
                // 44 points square: the minimum comfortable target.
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(theme.onGround.opacity(isPressed ? 0.18 : 0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

/// A move offered on the action bar during a game: check, call, draw, pass.
/// Sized for the thumb, labelled in words, and never a mystery icon.
public struct MoveButton: View {
    private let title: String
    private let detail: String?
    private let tone: Tone
    private let action: () -> Void

    public enum Tone { case go, hold, stop }

    @Environment(\.deckTheme) private var theme
    @State private var isPressed = false

    public init(title: String, detail: String? = nil, tone: Tone = .go, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        Button(action: {
            Haptics.shared.tap(.press)
            action()
        }) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let detail {
                    Text(detail)
                        .font(DeckType.tabular(12))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
            .offset(y: isPressed ? 2 : 0)
            .deckShadow(isPressed ? .none : DeckShadow(colour: .black.opacity(0.25), radius: 0, x: 0, y: 3))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(Text(detail.map { "\(title), \($0)" } ?? title))
    }

    private var background: Color {
        switch tone {
        case .go: return theme.accent
        case .hold: return theme.surface
        case .stop: return DeckPalette.inkSoft
        }
    }

    private var foreground: Color {
        switch tone {
        case .go, .stop: return DeckPalette.cream
        case .hold: return theme.ink
        }
    }
}
