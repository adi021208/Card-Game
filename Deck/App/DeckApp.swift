import SwiftUI

/// DECK.
///
/// One deck. Every game.
@main
@MainActor
struct DeckApp: App {
    @State private var environment = AppEnvironment.makeLive()

    var body: some Scene {
        WindowGroup {
            LaunchGate()
                .environment(environment)
                // The whole app is dark-on-light or light-on-dark by theme, not
                // by system appearance: a printed poster does not have a dark
                // mode. The theme picker in the collection is where that choice
                // lives, and `preferredColorScheme` keeps system chrome in step.
                .preferredColorScheme(environment.theme.isDark ? .dark : .light)
        }
    }
}

/// The launch sequence.
///
/// The mark appears, the cards come out of it, and the app is behind them. It
/// runs once, it is under a second, and it is skipped entirely under reduced
/// motion.
struct LaunchGate: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var phase: Phase = .mark

    enum Phase { case mark, spreading, done }

    var body: some View {
        ZStack {
            if phase == .done {
                RootView()
                    .transition(.opacity)
            } else {
                launchArtwork
            }
        }
        .task { await run() }
    }

    private var launchArtwork: some View {
        ZStack {
            DeckPalette.ink.ignoresSafeArea()
            GeometryReader { proxy in
                let box = proxy.size
                let spread = phase == .spreading ? 1.0 : 0.0
                ZStack {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(index == 2 ? DeckPalette.vermilion : DeckPalette.cream)
                            .frame(width: 84, height: CardMetrics.height(forWidth: 84))
                            .rotationEffect(.degrees(Double(index - 2) * 13 * spread))
                            .offset(x: CGFloat(index - 2) * box.width * 0.16 * CGFloat(spread),
                                    y: -CGFloat(abs(index - 2)) * 10 * CGFloat(spread))
                            .opacity(spread)
                    }
                    DeckLockup(scale: 1.2,
                               colour: DeckPalette.cream,
                               accent: DeckPalette.vermilion)
                        .scaleEffect(phase == .mark ? 1 : 1.08)
                        .opacity(phase == .mark ? 1 : 0.0)
                }
                .position(x: box.width / 2, y: box.height / 2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("DECK"))
    }

    private func run() async {
        let reduced = systemReduceMotion || deck.progress.settings.reduceMotion
        guard !reduced else {
            phase = .done
            return
        }
        try? await Task.sleep(nanoseconds: 520_000_000)
        withAnimation(.easeOut(duration: 0.36)) { phase = .spreading }
        try? await Task.sleep(nanoseconds: 380_000_000)
        withAnimation(.easeInOut(duration: 0.28)) { phase = .done }
    }
}
