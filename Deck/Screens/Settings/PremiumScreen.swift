import SwiftUI
import DeckProgression

/// The premium screen.
///
/// A poster, then a plain list of what you get, then the prices — every one of
/// them straight from StoreKit in the customer's own currency. No countdown, no
/// fake discount, no pre-selected expensive option, and the free experience is
/// described honestly rather than made to look broken.
public struct PremiumScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.l) {
                poster
                benefits
                offers
                footnotes
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(theme.ground.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .task { deck.store.start() }
    }

    private var poster: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                theme.accent
                HalftoneField(colour: DeckPalette.ink.opacity(0.22), cell: 12, direction: .topTrailing)
                SprayMark(colour: DeckPalette.ink.opacity(0.25), seed: 31,
                          density: 0.7, spread: 0.7, drips: 2)
            }
            .frame(height: 220)

            VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                Text(String(localized: "premium.eyebrow", defaultValue: "DECK"))
                    .font(DeckType.unit)
                    .tracking(DeckType.unitTracking * 2)
                    .foregroundStyle(DeckPalette.ink.opacity(0.7))
                Misregistered(offset: CGSize(width: 4, height: 4),
                              ghost: DeckPalette.cream.opacity(0.6)) {
                    Text(String(localized: "premium.title", defaultValue: "PREMIUM"))
                        .font(DeckType.display(64))
                        .foregroundStyle(DeckPalette.ink)
                }
            }
            .padding(DeckSpace.m)
        }
        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.poster, style: .continuous))
        .padding(.top, DeckSpace.m)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            ForEach(Array(StoreService.benefits.enumerated()), id: \.offset) { entry in
                HStack(alignment: .top, spacing: DeckSpace.s) {
                    TickMark()
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round,
                                                                 lineJoin: .round))
                        .frame(width: 18, height: 14)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(entry.element.titleKey))
                            .font(DeckType.bodyEmphasis)
                            .foregroundStyle(theme.onGround)
                        Text(LocalizedStringKey(entry.element.detailKey))
                            .font(DeckType.caption)
                            .foregroundStyle(theme.onGroundMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var offers: some View {
        switch deck.store.state {
        case .loading, .idle:
            DeckLoadingView(message: String(localized: "store.loading",
                                            defaultValue: "Checking prices…"))
                .frame(maxWidth: .infinity)
        case let .unavailable(reason):
            DeckErrorView(title: String(localized: "store.unavailable.title",
                                        defaultValue: "THE SHOP IS SHUT."),
                          message: reason,
                          retryTitle: String(localized: "common.retry", defaultValue: "TRY AGAIN")) {
                Task { await deck.store.load() }
            }
        case .ready, .purchasing:
            VStack(spacing: DeckSpace.xs) {
                if deck.progress.hasPremium {
                    Text(String(localized: "premium.active",
                                defaultValue: "Premium is active. Thank you."))
                        .font(DeckType.bodyEmphasis)
                        .foregroundStyle(theme.positive)
                } else {
                    ForEach(deck.store.offers) { offer in
                        offerRow(offer)
                    }
                }
                DeckButton(String(localized: "settings.restore", defaultValue: "RESTORE PURCHASES"),
                           emphasis: .quiet) {
                    Task { await deck.store.restore() }
                }
            }
        }
    }

    private func offerRow(_ offer: StoreOffer) -> some View {
        Button {
            Task { await deck.store.purchase(offer.product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.displayName)
                        .font(DeckType.bodyEmphasis)
                        .foregroundStyle(theme.onGround)
                    if let period = offer.periodDescription {
                        Text(period)
                            .font(DeckType.footnote)
                            .foregroundStyle(theme.onGroundMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(offer.displayPrice)
                        .font(DeckType.tabular(20, weight: .black))
                        .foregroundStyle(theme.onGround)
                    if let saving = offer.savingDescription {
                        Text(saving)
                            .font(DeckType.footnote)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(DeckSpace.m)
            .background(
                RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous)
                    .fill(theme.onGround.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: DeckSpace.xs) {
            Text(String(localized: "premium.freeNote",
                        defaultValue: "Every game, both modes, all the tutorials, your statistics and your achievements are free and always will be. Premium adds unlimited daily attempts, extra variants and the rest of the cosmetics."))
                .font(DeckType.footnote)
                .foregroundStyle(theme.onGroundMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "premium.terms",
                        defaultValue: "Subscriptions renew until cancelled. Manage or cancel in the App Store at any time."))
                .font(DeckType.footnote)
                .foregroundStyle(theme.onGroundMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
