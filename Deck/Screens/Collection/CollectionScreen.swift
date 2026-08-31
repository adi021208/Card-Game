import SwiftUI
import DeckCore
import DeckProgression

/// The collection.
///
/// A binder, not a store page. Card backs are shown as actual card backs you
/// can flick through, themes as swatches of their own palette, bosses as the
/// posters they are. Locked things say exactly what earns them, because a locked
/// item that will not tell you how to get it is just an advert.
public struct CollectionScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme

    @State private var kind: CosmeticKind = .cardBack

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.l) {
                header
                kindPicker
                if kind == .cardBack {
                    cardBackCarousel
                } else {
                    grid
                }
                bossShelf
            }
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(ground)
        .scrollIndicators(.hidden)
    }

    private var ground: some View {
        ZStack {
            theme.ground
            PaperGrain(intensity: theme.grain, seed: 7, tint: theme.isDark ? .white : .black)
                .opacity(theme.isDark ? 0.25 : 1)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
            DisplayText(String(localized: "collection.title", defaultValue: "COLLECTION"),
                        size: 54, colour: theme.onGround)
            Text(String(format: String(localized: "collection.count",
                                       defaultValue: "%d of %d unlocked"),
                        deck.progress.collection.unlocked.count,
                        CosmeticCatalog.all.count))
                .font(DeckType.caption)
                .foregroundStyle(theme.onGroundMuted)
        }
        .padding(.horizontal, DeckSpace.page)
        .padding(.top, DeckSpace.m)
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DeckSpace.xs) {
                ForEach(CosmeticKind.allCases) { value in
                    Button {
                        withAnimation(DeckMotion.select) { kind = value }
                        Haptics.shared.tap(.light)
                    } label: {
                        Text(CalloutRow.humanised(value.localizationKey))
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, DeckSpace.m)
                            .frame(height: 40)
                            .foregroundStyle(kind == value ? DeckPalette.cream : theme.onGround)
                            .background(
                                RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                                    .fill(kind == value ? theme.accent : theme.onGround.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(kind == value ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, DeckSpace.page)
        }
    }

    /// Card backs are flicked through at full size, because that is the only
    /// way to actually see one.
    private var cardBackCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DeckSpace.m) {
                ForEach(CosmeticCatalog.items(of: .cardBack)) { cosmetic in
                    let owned = deck.progress.collection.owns(cosmetic.id)
                    let selected = deck.progress.collection.selectedCardBack == cosmetic.id
                    VStack(spacing: DeckSpace.xs) {
                        CardBackArt(styleID: cosmetic.id, theme: theme)
                            .frame(width: 150, height: CardMetrics.height(forWidth: 150))
                            .clipShape(RoundedRectangle(cornerRadius: CardMetrics.corner(forWidth: 150),
                                                        style: .continuous))
                            .overlay(lockOverlay(owned: owned, cosmetic: cosmetic))
                            .rotationEffect(selected ? .degrees(-2.5) : .zero)
                            .deckShadow(selected ? .lifted : .resting)
                            .onTapGesture { select(cosmetic, owned: owned) }
                        Text(cosmetic.englishName)
                            .font(DeckType.bodyEmphasis)
                            .foregroundStyle(theme.onGround)
                        Text(unlockText(cosmetic, owned: owned))
                            .font(DeckType.footnote)
                            .foregroundStyle(selected ? theme.accent : theme.onGroundMuted)
                            .multilineTextAlignment(.center)
                            .frame(width: 150)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(cosmetic.englishName))
                    .accessibilityValue(Text(unlockText(cosmetic, owned: owned)))
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.vertical, DeckSpace.s)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: DeckSpace.m)],
                  spacing: DeckSpace.l) {
            ForEach(CosmeticCatalog.items(of: kind)) { cosmetic in
                let owned = deck.progress.collection.owns(cosmetic.id)
                VStack(spacing: DeckSpace.xs) {
                    CosmeticThumbnail(cosmetic: cosmetic, size: 92)
                        .overlay(lockOverlay(owned: owned, cosmetic: cosmetic))
                        .onTapGesture { select(cosmetic, owned: owned) }
                    Text(cosmetic.englishName)
                        .font(DeckType.caption)
                        .foregroundStyle(theme.onGround)
                        .lineLimit(1)
                    Text(unlockText(cosmetic, owned: owned))
                        .font(DeckType.footnote)
                        .foregroundStyle(isSelected(cosmetic) ? theme.accent : theme.onGroundMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(cosmetic.englishName))
                .accessibilityValue(Text(unlockText(cosmetic, owned: owned)))
            }
        }
        .padding(.horizontal, DeckSpace.page)
    }

    private var bossShelf: some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: String(localized: "collection.bosses", defaultValue: "The cast"))
                .padding(.horizontal, DeckSpace.page)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DeckSpace.m) {
                    ForEach(BossCast.all) { boss in
                        Button {
                            router.push(.boss(boss.id))
                        } label: {
                            BossCard(boss: boss,
                                     isDefeated: deck.progress.challenge.bossesDefeated.contains(boss.id))
                                .frame(width: 152)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DeckSpace.page)
            }
        }
    }

    @ViewBuilder
    private func lockOverlay(owned: Bool, cosmetic: Cosmetic) -> some View {
        if !owned {
            ZStack {
                Rectangle().fill(theme.ground.opacity(0.72))
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.onGround.opacity(0.8))
            }
            .clipShape(RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous))
        } else if isSelected(cosmetic) {
            RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: 3)
        }
    }

    private func isSelected(_ cosmetic: Cosmetic) -> Bool {
        let collection = deck.progress.collection
        switch cosmetic.kind {
        case .theme: return collection.selectedTheme == cosmetic.id
        case .cardBack: return collection.selectedCardBack == cosmetic.id
        case .table: return collection.selectedTable == cosmetic.id
        case .soundPack: return collection.selectedSoundPack == cosmetic.id
        case .avatar: return deck.progress.profiles.primary?.avatarID == cosmetic.id
        }
    }

    private func unlockText(_ cosmetic: Cosmetic, owned: Bool) -> String {
        if isSelected(cosmetic) {
            return String(localized: "collection.inUse", defaultValue: "In use")
        }
        if owned {
            return String(localized: "collection.owned", defaultValue: "Tap to use")
        }
        switch cosmetic.unlock {
        case .fromTheStart:
            return ""
        case let .achievement(id):
            let name = deck.progress.achievementEngine.definition(id)?.titleKey ?? id
            return String(format: String(localized: "unlock.achievement.detail",
                                         defaultValue: "Earn %@"),
                          CalloutRow.humanised(name))
        case let .streak(days):
            return String(format: String(localized: "unlock.streak.detail",
                                         defaultValue: "Reach a %d day streak"), days)
        case let .mastery(gameID, level):
            let name = deck.registry[gameID]?.englishName ?? gameID.rawValue
            return String(format: String(localized: "unlock.mastery.detail",
                                         defaultValue: "Reach mastery %d in %@"), level, name)
        case let .boss(id):
            return String(format: String(localized: "unlock.boss.detail",
                                         defaultValue: "Beat %@"),
                          BossCast.boss(id)?.displayName ?? id)
        case .premium:
            return String(localized: "unlock.premium.detail", defaultValue: "Premium")
        }
    }

    private func select(_ cosmetic: Cosmetic, owned: Bool) {
        guard owned else {
            if cosmetic.requiresPremium { router.push(.premium) }
            Haptics.shared.tap(.rejected)
            return
        }
        var collection = deck.progress.collection
        switch cosmetic.kind {
        case .theme: collection.selectedTheme = cosmetic.id
        case .cardBack: collection.selectedCardBack = cosmetic.id
        case .table: collection.selectedTable = cosmetic.id
        case .soundPack:
            collection.selectedSoundPack = cosmetic.id
            AudioService.shared.packID = cosmetic.id
        case .avatar:
            var profiles = deck.progress.profiles
            if var primary = profiles.primary {
                primary.avatarID = cosmetic.id
                profiles.upsert(primary)
                deck.progress.update(profiles: profiles)
            }
        }
        deck.progress.update(collection: collection)
        Haptics.shared.tap(.place)
        AudioService.shared.play(.cardPlace)
    }
}

/// A boss as a collectible poster.
public struct BossCard: View {
    private let boss: Boss
    private let isDefeated: Bool

    @Environment(\.deckTheme) private var theme

    public init(boss: Boss, isDefeated: Bool) {
        self.boss = boss
        self.isDefeated = isDefeated
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BossPortrait(boss: boss, isAnimated: isDefeated)
                .frame(height: 168)
                .grayscale(isDefeated ? 0 : 0.85)
                .opacity(isDefeated ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(boss.displayName.uppercased())
                    .font(DeckType.display(26))
                    .foregroundStyle(DeckPalette.token(boss.colourToken))
                Text(LocalizedStringKey(boss.titleKey))
                    .font(DeckType.footnote)
                    .foregroundStyle(theme.onGroundMuted)
                    .lineLimit(1)
            }
            .padding(DeckSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.onGround.opacity(0.07))
        }
        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.panel, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isDefeated {
                StampOutline(form: .circle, seed: boss.id.count, breakUp: 0.2)
                    .stroke(DeckPalette.forest, lineWidth: 2.5)
                    .frame(width: 40, height: 40)
                    .overlay(
                        TickMark()
                            .stroke(DeckPalette.forest, style: StrokeStyle(lineWidth: 3,
                                                                           lineCap: .round,
                                                                           lineJoin: .round))
                            .frame(width: DeckSpace.l, height: DeckSpace.s)
                    )
                    .rotationEffect(.degrees(-12))
                    .padding(DeckSpace.xs)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(boss.displayName))
        .accessibilityValue(Text(isDefeated
                                 ? String(localized: "boss.defeated", defaultValue: "Defeated")
                                 : String(localized: "boss.notDefeated",
                                          defaultValue: "Not yet defeated")))
    }
}
