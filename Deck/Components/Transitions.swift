import SwiftUI

/// The signature transitions.
///
/// Each one says something specific: a paint wipe means "somewhere else in the
/// app", a deck flip means "a different game", a stamp means "this is done".
/// They are used sparingly — a transition on every navigation is just latency
/// with a costume on.
public struct TransitionOverlay: View {
    private let transition: DeckTransition
    private let progress: Double
    private let theme: DeckTheme

    public init(transition: DeckTransition, progress: Double, theme: DeckTheme) {
        self.transition = transition
        self.progress = progress
        self.theme = theme
    }

    public var body: some View {
        GeometryReader { proxy in
            let box = proxy.size
            ZStack {
                switch transition {
                case .paintWipe:
                    paintWipe(box: box)
                case .deckFlip:
                    deckFlip(box: box)
                case .paperTear:
                    paperTear(box: box)
                case .cardCascade:
                    cardCascade(box: box)
                case .stamp:
                    stamp(box: box)
                case let .suitTransform(kind):
                    suitTransform(kind: kind, box: box)
                case .none:
                    Color.clear
                }
            }
            .allowsHitTesting(progress > 0.01 && progress < 0.99)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A brush loaded with ink sweeps across the screen and off the other side.
    private func paintWipe(box: CGSize) -> some View {
        let sweep = progress * 2.4 - 0.5
        return PaintStroke(bow: 0.02, weight: 3.2, seed: 3, progress: 1)
            .fill(theme.accent)
            .frame(width: box.width * 1.6, height: box.height * 1.4)
            .rotationEffect(.degrees(-7))
            .offset(x: box.width * CGFloat(sweep) - box.width * 0.8)
    }

    /// Cards gather into a stack, the stack turns over, and the next screen
    /// spreads out of it. The bridge between two games is always the deck.
    private func deckFlip(box: CGSize) -> some View {
        let gather = min(1, progress * 2)
        let spread = max(0, progress * 2 - 1)
        let cardWidth = min(box.width * 0.34, 190)
        return ZStack {
            theme.ground.opacity(progress < 0.95 ? 1 : 0)
            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) * 12 - 30
                let scatter = 1 - gather
                RoundedRectangle(cornerRadius: CardMetrics.corner(forWidth: cardWidth),
                                 style: .continuous)
                    .fill(index % 2 == 0 ? theme.surface : theme.accent)
                    .frame(width: cardWidth, height: CardMetrics.height(forWidth: cardWidth))
                    .rotationEffect(.degrees(angle * scatter + Double(spread) * 180))
                    .offset(x: CGFloat(scatter) * CGFloat(index - 3) * box.width * 0.18,
                            y: CGFloat(scatter) * CGFloat((index % 3) - 1) * box.height * 0.12)
                    .rotation3DEffect(.degrees(Double(spread) * 180), axis: (x: 0, y: 1, z: 0))
                    .scaleEffect(1 + CGFloat(spread) * 3.2)
                    .opacity(spread > 0.7 ? 0 : 1)
            }
        }
    }

    /// A sheet of paper tears away to reveal what is underneath.
    private func paperTear(box: CGSize) -> some View {
        TornEdge(side: .bottom, depth: 0.02, seed: 9, teeth: 40)
            .fill(theme.surface)
            .frame(width: box.width, height: box.height)
            .offset(y: -box.height * CGFloat(progress))
    }

    /// Cards run across the screen and off the far edge.
    private func cardCascade(box: CGSize) -> some View {
        let cardWidth = min(box.width * 0.22, 120)
        return ZStack {
            ForEach(0..<10, id: \.self) { index in
                let lead = Double(index) * 0.045
                let local = min(1, max(0, (progress - lead) * 1.8))
                RoundedRectangle(cornerRadius: CardMetrics.corner(forWidth: cardWidth),
                                 style: .continuous)
                    .fill(index % 3 == 0 ? theme.accent : theme.surface)
                    .frame(width: cardWidth, height: CardMetrics.height(forWidth: cardWidth))
                    .rotationEffect(.degrees(Double(index) * 21 - 90 + local * 220))
                    .position(x: box.width * CGFloat(-0.2 + local * 1.4),
                              y: box.height * CGFloat(0.15 + Double(index % 5) * 0.17))
                    .opacity(local > 0.95 ? 0 : 1)
            }
        }
    }

    /// A stamp lands hard, then lifts.
    private func stamp(box: CGSize) -> some View {
        let impact = min(1, progress * 2.5)
        let lift = max(0, progress * 1.4 - 0.4)
        return ZStack {
            StampOutline(form: .circle, seed: 12, breakUp: 0.14)
                .stroke(theme.accent, lineWidth: 10)
                .frame(width: box.width * 0.7, height: box.width * 0.7)
            DeckGlyph(fan: 0.6)
                .fill(theme.accent)
                .frame(width: box.width * 0.3)
        }
        .scaleEffect(3.0 - 2.0 * CGFloat(impact) + CGFloat(lift) * 0.4)
        .opacity(progress < 0.08 ? 0 : (1 - lift))
    }

    /// A suit mark expands until it swallows the screen, then keeps going.
    private func suitTransform(kind: SuitShape.Kind, box: CGSize) -> some View {
        let scale = 0.05 + pow(progress, 2.4) * 14
        return SuitShape(kind, wobble: 0.015, seed: 4)
            .fill(theme.accent)
            .frame(width: box.width * 0.6, height: box.width * 0.6)
            .scaleEffect(CGFloat(scale))
            .opacity(progress > 0.92 ? 0 : 1)
    }
}

/// Runs a transition over its content.
///
/// The overlay plays while the destination is being built underneath, so the
/// transition covers real work instead of adding to it.
public struct TransitionHost<Content: View>: View {
    private let transition: DeckTransition
    private let isActive: Bool
    private let onFinished: () -> Void
    private let content: () -> Content

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var progress: Double = 0

    public init(transition: DeckTransition,
                isActive: Bool,
                onFinished: @escaping () -> Void,
                @ViewBuilder content: @escaping () -> Content) {
        self.transition = transition
        self.isActive = isActive
        self.onFinished = onFinished
        self.content = content
    }

    public var body: some View {
        ZStack {
            content()
            if isActive && transition != .none && !reducedMotion {
                TransitionOverlay(transition: transition, progress: progress, theme: theme)
            }
        }
        .onChange(of: isActive) { _, newValue in
            guard newValue else { return }
            guard !reducedMotion, transition != .none else {
                onFinished()
                return
            }
            progress = 0
            withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: DeckMotion.deliberate)) {
                progress = 1
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(DeckMotion.deliberate * 1_000_000_000))
                onFinished()
            }
        }
    }
}

/// The branded loading state.
///
/// A deck being shuffled, not a spinner. It only appears when something is
/// genuinely being computed — a big Monte-Carlo decision, a restore — and it
/// says what it is waiting for.
public struct DeckLoadingView: View {
    private let message: String

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: DeckSpace.l) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reducedMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<5, id: \.self) { index in
                        let phase = (t * 1.6 + Double(index) * 0.2)
                            .truncatingRemainder(dividingBy: 2.0) / 2.0
                        let lift = sin(phase * .pi)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(index % 2 == 0 ? theme.surface : theme.accent)
                            .frame(width: 44, height: 62)
                            .offset(x: CGFloat(index - 2) * 9,
                                    y: -CGFloat(lift) * 22)
                            .rotationEffect(.degrees(Double(index - 2) * 6 - lift * 10))
                    }
                }
                .frame(height: 100)
            }
            Text(message)
                .font(DeckType.caption)
                .foregroundStyle(theme.onGroundMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}
