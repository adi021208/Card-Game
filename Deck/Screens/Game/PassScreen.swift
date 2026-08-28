import SwiftUI
import DeckCore

/// The pass screen.
///
/// The moment the app is built around. Nothing private is on screen or in the
/// view hierarchy behind it — the coordinator has already dropped the viewer to
/// nobody, so the table underneath has physically nothing to leak — and the only
/// way forward is a deliberate press by the person the device is being handed to.
public struct PassScreen: View {
    private let playerName: String
    private let seatIndex: Int
    private let onReveal: () -> Void

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var hasAppeared = false

    public init(playerName: String, seatIndex: Int, onReveal: @escaping () -> Void) {
        self.playerName = playerName
        self.seatIndex = seatIndex
        self.onReveal = onReveal
    }

    /// Each seat gets its own colour, so the hand-off reads before it is read.
    private var seatColour: Color {
        let palette = [DeckPalette.vermilion, DeckPalette.cobalt, DeckPalette.acid,
                       DeckPalette.coral, DeckPalette.forest, DeckPalette.orange]
        return palette[seatIndex % palette.count]
    }

    public var body: some View {
        ZStack {
            ground
            content
        }
        .onAppear {
            withAnimation(reducedMotion ? nil : DeckMotion.panel) { hasAppeared = true }
            Haptics.shared.tap(.handoff)
        }
        // The whole screen is the affordance for a screen reader; the reveal
        // button is the only control.
        .accessibilityElement(children: .contain)
    }

    private var ground: some View {
        ZStack {
            seatColour
            HalftoneField(colour: DeckPalette.ink.opacity(0.22), cell: 14, direction: .topLeading)
            SprayMark(colour: DeckPalette.ink.opacity(0.28), seed: seatIndex &* 13 &+ 5,
                      density: 0.8, spread: 0.9, drips: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PaperGrain(intensity: 0.16, seed: 8, tint: .black)
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DeckSpace.xxl)

            // A stack of face-down cards, gathered: the visual promise that
            // whatever was on screen has been put away.
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DeckPalette.ink)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(DeckPalette.cream.opacity(0.5), lineWidth: 1.5)
                                .padding(4)
                        )
                        .frame(width: 78, height: CardMetrics.height(forWidth: 78))
                        .rotationEffect(.degrees(Double(index) * 5 - 10))
                        .offset(x: CGFloat(index - 2) * 5, y: CGFloat(index) * -2)
                }
                DeckGlyph(fan: 0.5)
                    .fill(seatColour)
                    .frame(width: 40)
                    .offset(y: -4)
            }
            .scaleEffect(hasAppeared ? 1 : 0.86)
            .opacity(hasAppeared ? 1 : 0)

            Spacer(minLength: DeckSpace.l)

            VStack(alignment: .leading, spacing: DeckSpace.xs) {
                Text(String(localized: "pass.to", defaultValue: "PASS TO"))
                    .font(DeckType.display(30))
                    .foregroundStyle(DeckPalette.ink.opacity(0.7))

                Misregistered(offset: CGSize(width: 4, height: 4),
                              ghost: DeckPalette.cream.opacity(0.55)) {
                    Text(playerName.uppercased())
                        .font(DeckType.display(78))
                        .tracking(-3)
                        .foregroundStyle(DeckPalette.ink)
                        .minimumScaleFactor(0.4)
                        .lineLimit(2)
                }

                PaintStroke(bow: 0.03, weight: 0.55, seed: seatIndex &+ 2)
                    .fill(DeckPalette.ink)
                    .frame(height: 12)
                    .padding(.trailing, DeckSpace.xxl)

                Text(String(format: String(localized: "pass.privacy",
                                           defaultValue: "Make sure %@ is the only person looking at the screen."),
                            playerName))
                    .font(DeckType.body)
                    .foregroundStyle(DeckPalette.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DeckSpace.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DeckSpace.page)
            .offset(y: hasAppeared ? 0 : 24)
            .opacity(hasAppeared ? 1 : 0)

            Spacer(minLength: DeckSpace.xl)

            Button(action: {
                Haptics.shared.tap(.turnChange)
                onReveal()
            }) {
                HStack(spacing: DeckSpace.xs) {
                    Text(String(localized: "pass.reveal", defaultValue: "REVEAL"))
                        .font(DeckType.display(28))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .black))
                }
                .foregroundStyle(seatColour)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(
                    RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                        .fill(DeckPalette.ink)
                )
                .deckShadow(DeckShadow(colour: .black.opacity(0.3), radius: 0, x: 0, y: 5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.xl)
            .accessibilityLabel(Text(String(format: String(localized: "pass.revealAccessibility",
                                                           defaultValue: "Reveal %@'s hand"),
                                            playerName)))
            .accessibilityHint(Text(String(localized: "pass.revealHint",
                                           defaultValue: "Only tap this if you are the named player.")))
        }
    }
}

/// The seal: the half-second where the cards gather and turn over before the
/// pass screen arrives.
///
/// It is drawn from nothing — no real cards are involved, because by the time
/// this runs there is nothing private left to draw.
public struct SealOverlay: View {
    private let progress: Double

    @Environment(\.deckTheme) private var theme

    public init(progress: Double) {
        self.progress = progress
    }

    public var body: some View {
        GeometryReader { proxy in
            let box = proxy.size
            let gather = min(1, progress * 1.5)
            let flip = max(0, progress * 2 - 1)
            ZStack {
                theme.ground.opacity(progress * 0.92)
                ForEach(0..<7, id: \.self) { index in
                    let spread = 1 - gather
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DeckPalette.ink)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(DeckPalette.cream.opacity(0.45), lineWidth: 1.2)
                                .padding(3)
                                .opacity(flip)
                        )
                        .frame(width: 70, height: CardMetrics.height(forWidth: 70))
                        .rotation3DEffect(.degrees(Double(flip) * 180), axis: (x: 1, y: 0, z: 0))
                        .rotationEffect(.degrees(Double(index - 3) * 7 * spread))
                        .position(x: box.width / 2 + CGFloat(spread) * CGFloat(index - 3) * box.width * 0.13,
                                  y: box.height * (0.72 - Double(gather) * 0.2))
                }
            }
            .opacity(progress > 0.02 ? 1 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(progress > 0.02)
        .accessibilityHidden(true)
    }
}
