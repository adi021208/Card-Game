import SwiftUI
import DeckCore

/// How to play, available mid-game without ending it.
///
/// It sheets over the table rather than replacing it, so nothing private is torn
/// down and put back, and the game is exactly where it was when the sheet closes.
public struct RulesSheet: View {
    private let definition: GameDefinition

    @Environment(\.dismiss) private var dismiss
    @Environment(\.deckTheme) private var theme

    public init(definition: GameDefinition) {
        self.definition = definition
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DeckSpace.l) {
                    GameCoverArt(artworkID: definition.artworkID,
                                 title: definition.englishName,
                                 size: .shelf,
                                 seed: definition.id.rawValue.count)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: DeckRadius.poster,
                                                    style: .continuous))

                    Text(LocalizedStringKey(definition.descriptionKey))
                        .font(DeckType.body)
                        .foregroundStyle(theme.onGround)
                        .fixedSize(horizontal: false, vertical: true)

                    factsBlock

                    if !definition.tutorial.steps.isEmpty {
                        VStack(alignment: .leading, spacing: DeckSpace.m) {
                            SectionRule(title: String(localized: "rules.howItWorks",
                                                      defaultValue: "How it works"))
                            ForEach(Array(definition.tutorial.steps.enumerated()), id: \.element.id) { entry in
                                stepRow(index: entry.offset + 1, step: entry.element)
                            }
                        }
                    }

                    if !definition.variants.isEmpty {
                        VStack(alignment: .leading, spacing: DeckSpace.m) {
                            SectionRule(title: String(localized: "rules.variants",
                                                      defaultValue: "Variants"))
                            ForEach(definition.variants) { variant in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(variant.nameKey))
                                        .font(DeckType.bodyEmphasis)
                                        .foregroundStyle(theme.onGround)
                                    Text(LocalizedStringKey(variant.summaryKey))
                                        .font(DeckType.caption)
                                        .foregroundStyle(theme.onGroundMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(DeckSpace.page)
            }
            .background(theme.ground.ignoresSafeArea())
            .navigationTitle(definition.englishName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done", defaultValue: "Done")) { dismiss() }
                }
            }
        }
    }

    private var factsBlock: some View {
        HStack(spacing: DeckSpace.l) {
            fact(String(localized: "rules.players", defaultValue: "Players"), playerText)
            fact(String(localized: "rules.length", defaultValue: "Length"),
                 String.deck(definition.duration.localizationKey, or: CalloutRow.humanised(definition.duration.localizationKey)))
            fact(String(localized: "rules.complexity", defaultValue: "Learning"),
                 String.deck(definition.complexity.localizationKey, or: CalloutRow.humanised(definition.complexity.localizationKey)))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.onGroundMuted)
            Text(value)
                .font(DeckType.bodyEmphasis)
                .foregroundStyle(theme.onGround)
        }
    }

    private var playerText: String {
        let range = definition.playerRange
        return range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
    }

    private func stepRow(index: Int, step: TutorialStep) -> some View {
        HStack(alignment: .top, spacing: DeckSpace.s) {
            Text("\(index)")
                .font(DeckType.numeral(24))
                .foregroundStyle(theme.accent)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(step.titleKey))
                    .font(DeckType.bodyEmphasis)
                    .foregroundStyle(theme.onGround)
                Text(LocalizedStringKey(step.bodyKey))
                    .font(DeckType.caption)
                    .foregroundStyle(theme.onGroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
