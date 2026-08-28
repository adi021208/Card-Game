import SwiftUI
import DeckProgression

/// A boss's page.
///
/// Built like a collectible poster: the portrait full bleed, the name enormous,
/// and — underneath — exactly what facing them changes about the game, in
/// sentences. A boss whose modifier is not stated is just a difficulty slider
/// with a face on it.
public struct BossScreen: View {
    private let bossID: String

    @Environment(AppEnvironment.self) private var deck
    @Environment(\.deckTheme) private var theme

    public init(bossID: String) {
        self.bossID = bossID
    }

    private var boss: Boss? { BossCast.boss(bossID) }
    private var isDefeated: Bool { deck.progress.challenge.bossesDefeated.contains(bossID) }

    public var body: some View {
        Group {
            if let boss {
                content(boss)
            } else {
                DeckErrorView(message: String(localized: "boss.unknown",
                                              defaultValue: "That opponent is not in the cast."))
            }
        }
        .background(theme.ground.ignoresSafeArea())
    }

    private func content(_ boss: Boss) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.l) {
                ZStack(alignment: .bottomLeading) {
                    BossPortrait(boss: boss, isAnimated: true)
                        .frame(height: 340)
                        .grayscale(isDefeated ? 0 : 0.7)
                    LinearGradient(colors: [.clear, theme.ground.opacity(0.9)],
                                   startPoint: .center, endPoint: .bottom)
                        .frame(height: 340)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 0) {
                        Misregistered(offset: CGSize(width: 4, height: 4),
                                      ghost: DeckPalette.token(boss.colourToken).opacity(0.7)) {
                            Text(boss.displayName.uppercased())
                                .font(DeckType.display(64))
                                .foregroundStyle(theme.onGround)
                        }
                        Text(LocalizedStringKey(boss.titleKey))
                            .font(DeckType.displayCondensed(22))
                            .foregroundStyle(DeckPalette.token(boss.colourToken))
                    }
                    .padding(DeckSpace.page)
                }
                .clipShape(TornEdge(side: .bottom, depth: 0.03, seed: boss.id.count, teeth: 30))

                VStack(alignment: .leading, spacing: DeckSpace.l) {
                    loreBlock(boss)
                    abilityBlock(boss)
                    styleBlock(boss)
                    recordBlock(boss)
                }
                .padding(.horizontal, DeckSpace.page)
                .padding(.bottom, DeckSpace.xxxl)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }

    /// The lore is the reward for beating them, so it stays sealed until then.
    private func loreBlock(_ boss: Boss) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.xs) {
            if isDefeated {
                Text("“\(boss.englishLore)”")
                    .font(DeckType.title)
                    .italic()
                    .foregroundStyle(theme.onGround)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: DeckSpace.xs) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(theme.onGroundMuted)
                    Text(String(localized: "boss.loreLocked",
                                defaultValue: "Beat them to learn what they are about."))
                        .font(DeckType.body)
                        .foregroundStyle(theme.onGroundMuted)
                }
            }
        }
    }

    private func abilityBlock(_ boss: Boss) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            SectionRule(title: String(localized: "boss.ability", defaultValue: "What changes"))
            ForEach(Array(boss.modifiers.enumerated()), id: \.offset) { entry in
                HStack(alignment: .top, spacing: DeckSpace.s) {
                    Rectangle()
                        .fill(DeckPalette.token(boss.colourToken))
                        .frame(width: 4)
                    Text(entry.element.englishExplanation)
                        .font(DeckType.body)
                        .foregroundStyle(theme.onGround)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The AI parameters, drawn as bars. Showing them is honest and it is also
    /// the most interesting thing about the cast.
    private func styleBlock(_ boss: Boss) -> some View {
        let profile = AICast.personality(boss.personalityID).profile
        return VStack(alignment: .leading, spacing: DeckSpace.s) {
            SectionRule(title: String(localized: "boss.style", defaultValue: "How they play"))
            traitRow(String(localized: "trait.aggression", defaultValue: "Aggression"),
                     profile.aggression, boss)
            traitRow(String(localized: "trait.risk", defaultValue: "Risk"),
                     profile.riskTolerance, boss)
            traitRow(String(localized: "trait.bluff", defaultValue: "Bluffing"),
                     profile.bluffFrequency, boss)
            traitRow(String(localized: "trait.memory", defaultValue: "Memory"),
                     profile.memoryStrength, boss)
            traitRow(String(localized: "trait.adaptability", defaultValue: "Adapts to you"),
                     profile.adaptability, boss)
        }
    }

    private func traitRow(_ label: String, _ value: Double, _ boss: Boss) -> some View {
        HStack(spacing: DeckSpace.m) {
            Text(label)
                .font(DeckType.caption)
                .foregroundStyle(theme.onGroundMuted)
                .frame(width: 110, alignment: .leading)
            ProgressRule(fraction: value, colour: DeckPalette.token(boss.colourToken))
                .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(Int(value * 100)) percent"))
    }

    private func recordBlock(_ boss: Boss) -> some View {
        HStack(spacing: DeckSpace.xl) {
            NumeralBlock(value: isDefeated ? "1" : "0",
                         unit: String(localized: "boss.defeatedCount", defaultValue: "Defeated"),
                         size: 44,
                         colour: isDefeated ? theme.positive : theme.onGroundMuted,
                         unitColour: theme.onGroundMuted)
            NumeralBlock(value: "\(BossCast.threat(boss))",
                         unit: String(localized: "boss.threat", defaultValue: "Threat"),
                         size: 44,
                         colour: DeckPalette.token(boss.colourToken),
                         unitColour: theme.onGroundMuted)
            Spacer()
        }
    }
}
