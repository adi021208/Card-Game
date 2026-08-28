import SwiftUI
import DeckCore
import DeckProgression

/// First launch.
///
/// Two screens, not fifteen: the name, then a choice of how you want to play.
/// The rules of whatever they pick are taught inside the game, by playing it.
public struct WelcomeScreen: View {
    private let onFinish: (PlayMode?) -> Void

    @Environment(\.deckTheme) private var theme
    @Environment(\.deckReducedMotion) private var reducedMotion
    @State private var step = 0
    @State private var appeared = false

    public init(onFinish: @escaping (PlayMode?) -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            ground
            if step == 0 { titleStep } else { modeStep }
        }
        .onAppear {
            withAnimation(reducedMotion ? nil : DeckMotion.panel.delay(0.1)) { appeared = true }
        }
    }

    private var ground: some View {
        ZStack {
            DeckPalette.ink
            HalftoneField(colour: DeckPalette.vermilion.opacity(0.25), cell: 16,
                          direction: .bottomLeading)
            SprayMark(colour: DeckPalette.vermilion.opacity(0.4), seed: 77,
                      density: 1.0, spread: 1.0, drips: 3)
            PaperGrain(intensity: 0.14, seed: 4, tint: .white)
        }
        .ignoresSafeArea()
    }

    private var titleStep: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            Spacer()
            DeckLockup(scale: 1.5, colour: DeckPalette.cream,
                       accent: DeckPalette.vermilion, showsTagline: false)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "welcome.line1", defaultValue: "ONE DECK."))
                    .font(DeckType.display(46))
                    .foregroundStyle(DeckPalette.cream)
                Text(String(localized: "welcome.line2", defaultValue: "EVERY GAME."))
                    .font(DeckType.display(46))
                    .foregroundStyle(DeckPalette.vermilion)
            }
            .opacity(appeared ? 1 : 0)
            Spacer()
            DeckButton(String(localized: "welcome.start", defaultValue: "GET STARTED"),
                       emphasis: .primary) {
                withAnimation(reducedMotion ? nil : DeckMotion.panel) { step = 1 }
            }
        }
        .padding(DeckSpace.page)
        .padding(.bottom, DeckSpace.l)
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            Spacer()
            Text(String(localized: "welcome.how", defaultValue: "HOW DO YOU\nWANT TO PLAY?"))
                .font(DeckType.display(46))
                .foregroundStyle(DeckPalette.cream)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DeckSpace.m) {
                choiceCard(title: String(localized: "mode.solo", defaultValue: "PLAY SOLO"),
                           detail: String(localized: "welcome.solo",
                                          defaultValue: "Against seven opponents who each play differently."),
                           suit: .spade,
                           colour: DeckPalette.cobalt) {
                    onFinish(.solo)
                }
                choiceCard(title: String(localized: "mode.passAndPlay", defaultValue: "PASS & PLAY"),
                           detail: String(localized: "welcome.passAndPlay",
                                          defaultValue: "One phone, passed round. Nobody sees anybody else's hand."),
                           suit: .heart,
                           colour: DeckPalette.vermilion) {
                    onFinish(.passAndPlay)
                }
            }

            Button {
                onFinish(nil)
            } label: {
                Text(String(localized: "welcome.browse", defaultValue: "Just show me the library"))
                    .font(DeckType.caption)
                    .foregroundStyle(DeckPalette.cream.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(DeckSpace.page)
    }

    private func choiceCard(title: String,
                            detail: String,
                            suit: SuitShape.Kind,
                            colour: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DeckSpace.m) {
                SuitShape(suit, wobble: 0.025, seed: title.count)
                    .fill(DeckPalette.cream)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                    Text(title)
                        .font(DeckType.displayCondensed(28))
                        .foregroundStyle(DeckPalette.cream)
                    Text(detail)
                        .font(DeckType.caption)
                        .foregroundStyle(DeckPalette.cream.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(DeckSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous)
                    .fill(colour)
            )
            .rotationEffect(DeckMotion.settledAngle(seed: title.count, spread: 1.2))
        }
        .buttonStyle(.plain)
    }
}

/// The first Pass & Play game demonstrates the privacy rather than explaining
/// it: a single card, dealt face down, that only appears once the named player
/// says they are the one holding the phone.
public struct PassAndPlayIntro: View {
    private let firstPlayerName: String
    private let onContinue: () -> Void

    @Environment(\.deckTheme) private var theme
    @State private var revealed = false

    public init(firstPlayerName: String, onContinue: @escaping () -> Void) {
        self.firstPlayerName = firstPlayerName
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DeckSpace.l) {
            Spacer()
            DisplayText(String(localized: "intro.passTitle", defaultValue: "ONE PHONE.\nNO PEEKING."),
                        size: 44, colour: theme.onGround)
            Text(String(localized: "intro.passBody",
                        defaultValue: "When it is somebody else's turn, their cards are not hidden behind an animation — they are not on the device at all until they say it is them."))
                .font(DeckType.body)
                .foregroundStyle(theme.onGroundMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                ZStack {
                    if revealed {
                        CardView(card: .known(Card(.hearts, .ace)), width: 120)
                            .transition(.opacity)
                    } else {
                        CardView(card: .concealed(CardID(rawValue: 0)),
                                 width: 120,
                                 presentation: CardPresentation(isFaceUp: false))
                    }
                }
                .onTapGesture {
                    withAnimation(DeckMotion.flip) { revealed.toggle() }
                    Haptics.shared.tap(.turnChange)
                }
                Spacer()
            }
            Text(revealed
                 ? String(localized: "intro.passRevealed",
                          defaultValue: "That is what your hand looks like when it is your turn.")
                 : String(format: String(localized: "intro.passTap",
                                         defaultValue: "Tap the card as though you were %@."),
                          firstPlayerName))
                .font(DeckType.caption)
                .foregroundStyle(theme.onGroundMuted)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer()
            DeckButton(String(localized: "intro.deal", defaultValue: "DEAL"), emphasis: .primary,
                       action: onContinue)
        }
        .padding(DeckSpace.page)
        .background(theme.ground.ignoresSafeArea())
    }
}
