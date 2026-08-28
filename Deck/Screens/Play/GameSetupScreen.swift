import SwiftUI
import DeckCore
import DeckProgression

/// Setting a game up.
///
/// Game-aware, because the questions are: Poker asks about chips and blinds,
/// Klondike asks draw one or draw three, Hearts asks how high you are playing
/// to. There is no shared settings form that every game is pushed through — the
/// options come from the game's own definition.
public struct GameSetupScreen: View {
    private let gameID: GameID
    private let mode: PlayMode

    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var variantID: String = "standard"
    @State private var options: [String: Int] = [:]
    @State private var humanCount = 1
    @State private var aiCount = 3
    @State private var difficulty: AIDifficulty = .casual
    @State private var selectedProfiles: [String] = []
    @State private var hasLoaded = false

    public init(gameID: GameID, mode: PlayMode) {
        self.gameID = gameID
        self.mode = mode
    }

    private var definition: GameDefinition? { deck.registry[gameID] }

    public var body: some View {
        Group {
            if let definition {
                content(definition)
            } else {
                DeckErrorView(message: String(localized: "game.unknown",
                                              defaultValue: "That game is not in the library."))
            }
        }
        .background(theme.ground.ignoresSafeArea())
        .onAppear { load() }
    }

    private func content(_ definition: GameDefinition) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DeckSpace.l) {
                    header(definition)
                    playersBlock(definition)
                    if definition.supportsAIOpponents && aiCount > 0 {
                        difficultyBlock
                    }
                    if !definition.variants.isEmpty {
                        variantBlock(definition)
                    }
                    if !definition.setupOptions.isEmpty {
                        optionsBlock(definition)
                    }
                }
                .padding(.horizontal, DeckSpace.page)
                .padding(.bottom, DeckSpace.l)
            }
            .scrollIndicators(.hidden)

            DeckButton(String(localized: "setup.deal", defaultValue: "DEAL"),
                       emphasis: .primary,
                       isEnabled: isValid(definition)) {
                start(definition)
            }
            .padding(.horizontal, DeckSpace.page)
            .padding(.bottom, DeckSpace.m)
        }
    }

    private func header(_ definition: GameDefinition) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.xxs) {
            Text(LocalizedStringKey(mode.localizationKey))
                .font(DeckType.unit)
                .tracking(DeckType.unitTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            DisplayText(definition.englishName.uppercased(), size: 52, colour: theme.onGround)
        }
        .padding(.top, DeckSpace.m)
    }

    // MARK: - Players

    @ViewBuilder
    private func playersBlock(_ definition: GameDefinition) -> some View {
        if definition.playerRange.upperBound > 1 {
            VStack(alignment: .leading, spacing: DeckSpace.s) {
                SectionRule(title: String(localized: "setup.players", defaultValue: "Players"))
                if mode == .passAndPlay {
                    stepper(label: String(localized: "setup.people", defaultValue: "People here"),
                            value: $humanCount,
                            range: 2...definition.playerRange.upperBound) { newValue in
                        aiCount = max(0, min(aiCount, definition.playerRange.upperBound - newValue))
                        if newValue + aiCount < definition.playerRange.lowerBound {
                            aiCount = definition.playerRange.lowerBound - newValue
                        }
                    }
                    profilePicker
                }
                if definition.supportsAIOpponents {
                    stepper(label: String(localized: "setup.opponents", defaultValue: "AI opponents"),
                            value: $aiCount,
                            range: 0...(definition.playerRange.upperBound - humanCount)) { _ in }
                }
                Text(seatSummary(definition))
                    .font(DeckType.footnote)
                    .foregroundStyle(theme.onGroundMuted)
            }
        }
    }

    private func seatSummary(_ definition: GameDefinition) -> String {
        let total = humanCount + aiCount
        if !definition.playerRange.contains(total) {
            return String(format: String(localized: "setup.needsPlayers",
                                         defaultValue: "%@ needs %d to %d players. You have %d."),
                          definition.englishName,
                          definition.playerRange.lowerBound,
                          definition.playerRange.upperBound,
                          total)
        }
        return String(format: String(localized: "setup.seatSummary",
                                     defaultValue: "%d at the table."), total)
    }

    private var profilePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DeckSpace.s) {
                ForEach(deck.progress.profiles.profiles) { profile in
                    let isPicked = selectedProfiles.contains(profile.id)
                    Button {
                        toggleProfile(profile.id)
                    } label: {
                        VStack(spacing: DeckSpace.xxs) {
                            AvatarArt(avatarID: profile.avatarID,
                                      initials: profile.initials,
                                      size: 48)
                                .opacity(isPicked ? 1 : 0.45)
                            Text(profile.name)
                                .font(DeckType.footnote)
                                .foregroundStyle(isPicked ? theme.onGround : theme.onGroundMuted)
                                .lineLimit(1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isPicked {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 12, height: 12)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
                }
                Button {
                    router.push(.profiles)
                } label: {
                    VStack(spacing: DeckSpace.xxs) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(theme.onGround.opacity(0.3),
                                              style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                .frame(width: 48, height: 48)
                            Image(systemName: "plus")
                                .foregroundStyle(theme.onGroundMuted)
                        }
                        Text(String(localized: "play.addPlayer", defaultValue: "Add"))
                            .font(DeckType.footnote)
                            .foregroundStyle(theme.onGroundMuted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleProfile(_ id: String) {
        if let index = selectedProfiles.firstIndex(of: id) {
            selectedProfiles.remove(at: index)
        } else if selectedProfiles.count < humanCount {
            selectedProfiles.append(id)
        } else {
            selectedProfiles.removeFirst()
            selectedProfiles.append(id)
        }
        Haptics.shared.tap(.light)
    }

    // MARK: - Difficulty

    private var difficultyBlock: some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            SectionRule(title: String(localized: "setup.difficulty", defaultValue: "Opponents"))
            HStack(spacing: DeckSpace.xs) {
                ForEach(AIDifficulty.allCases, id: \.self) { value in
                    Button {
                        difficulty = value
                        Haptics.shared.tap(.light)
                    } label: {
                        Text(CalloutRow.humanised(value.localizationKey))
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(difficulty == value ? DeckPalette.cream : theme.onGround)
                            .background(
                                RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                                    .fill(difficulty == value ? theme.accent : theme.onGround.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(difficulty == value ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    // MARK: - Variants and options

    private func variantBlock(_ definition: GameDefinition) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.s) {
            SectionRule(title: String(localized: "setup.rules", defaultValue: "Rules"))
            ForEach(definition.variants) { variant in
                let locked = variant.requiresPremium && !deck.progress.hasPremium
                Button {
                    guard !locked else {
                        router.push(.premium)
                        return
                    }
                    variantID = variant.id
                    options = definition.resolvedOptions(variantID: variant.id, overrides: [:])
                    Haptics.shared.tap(.light)
                } label: {
                    HStack(alignment: .top, spacing: DeckSpace.s) {
                        SelectionDot(isOn: variantID == variant.id, colour: theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: DeckSpace.xxs) {
                                Text(LocalizedStringKey(variant.nameKey))
                                    .font(DeckType.bodyEmphasis)
                                    .foregroundStyle(theme.onGround)
                                if locked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            Text(LocalizedStringKey(variant.summaryKey))
                                .font(DeckType.caption)
                                .foregroundStyle(theme.onGroundMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(variantID == variant.id ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func optionsBlock(_ definition: GameDefinition) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: String(localized: "setup.options", defaultValue: "Options"))
            ForEach(definition.setupOptions) { option in
                optionControl(option)
            }
        }
    }

    @ViewBuilder
    private func optionControl(_ option: SetupOption) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.xs) {
            Text(LocalizedStringKey(option.titleKey))
                .font(DeckType.bodyEmphasis)
                .foregroundStyle(theme.onGround)
            switch option.control {
            case let .choice(values, labelKeys):
                HStack(spacing: DeckSpace.xs) {
                    ForEach(Array(values.enumerated()), id: \.offset) { entry in
                        let value = entry.element
                        let key = entry.offset < labelKeys.count ? labelKeys[entry.offset] : "\(value)"
                        Button {
                            options[option.id] = value
                            Haptics.shared.tap(.light)
                        } label: {
                            Text(LocalizedStringKey(key))
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .foregroundStyle(options[option.id] == value
                                                 ? DeckPalette.cream : theme.onGround)
                                .background(
                                    RoundedRectangle(cornerRadius: DeckRadius.button,
                                                     style: .continuous)
                                        .fill(options[option.id] == value
                                              ? theme.accent : theme.onGround.opacity(0.07))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            case let .stepper(range, step):
                HStack {
                    Text("\(options[option.id] ?? option.defaultValue)")
                        .font(DeckType.numeral(28))
                        .foregroundStyle(theme.onGround)
                    Spacer()
                    Stepper("", value: Binding(
                        get: { options[option.id] ?? option.defaultValue },
                        set: { options[option.id] = $0 }
                    ), in: range, step: step)
                    .labelsHidden()
                }
            case .toggle:
                Toggle(isOn: Binding(
                    get: { (options[option.id] ?? option.defaultValue) != 0 },
                    set: { options[option.id] = $0 ? 1 : 0 }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(theme.accent)
            }
            if let footnote = option.footnoteKey {
                Text(LocalizedStringKey(footnote))
                    .font(DeckType.footnote)
                    .foregroundStyle(theme.onGroundMuted)
            }
        }
    }

    private func stepper(label: String,
                         value: Binding<Int>,
                         range: ClosedRange<Int>,
                         onChange: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label)
                .font(DeckType.body)
                .foregroundStyle(theme.onGround)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(DeckType.numeral(26))
                .foregroundStyle(theme.accent)
            Stepper("", value: value, in: range.lowerBound...max(range.lowerBound, range.upperBound))
                .labelsHidden()
                .onChange(of: value.wrappedValue) { _, newValue in onChange(newValue) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value.wrappedValue)"))
    }

    // MARK: - Lifecycle

    private func load() {
        guard !hasLoaded, let definition else { return }
        hasLoaded = true
        variantID = definition.defaultVariantID
        options = definition.resolvedOptions(variantID: variantID, overrides: [:])
        difficulty = deck.progress.settings.preferredDifficulty
        if mode == .passAndPlay {
            humanCount = max(2, definition.playerRange.lowerBound)
            aiCount = max(0, definition.playerRange.lowerBound - humanCount)
            let remembered = deck.progress.profiles.recentTable
            selectedProfiles = remembered.isEmpty
                ? deck.progress.profiles.profiles.prefix(humanCount).map(\.id)
                : Array(remembered.prefix(humanCount))
        } else {
            humanCount = 1
            aiCount = definition.supportsAIOpponents
                ? max(0, definition.playerRange.lowerBound - 1)
                : 0
            selectedProfiles = deck.progress.profiles.primary.map { [$0.id] } ?? []
        }
    }

    private func isValid(_ definition: GameDefinition) -> Bool {
        definition.playerRange.contains(humanCount + aiCount)
    }

    private func start(_ definition: GameDefinition) {
        let profiles = selectedProfiles.compactMap { deck.progress.profiles.profile($0) }
        guard let configuration = deck.configuration(gameID: definition.id,
                                                     humanCount: humanCount,
                                                     aiCount: aiCount,
                                                     variantID: variantID,
                                                     options: options,
                                                     difficulty: difficulty,
                                                     humanProfiles: profiles) else { return }
        // Quick Play repeats whatever was set up last.
        var settings = deck.progress.settings
        settings.quickPlayGameID = definition.id
        settings.quickPlayVariantID = variantID
        settings.quickPlayIsPassAndPlay = mode == .passAndPlay
        settings.preferredDifficulty = difficulty
        deck.progress.update(settings: settings)

        guard deck.makeSession(configuration) != nil else { return }
        router.openGame(definition.id,
                        transition: DeckTransition.between(from: nil, to: definition.id,
                                                           registry: deck.registry))
    }
}

/// A selection mark drawn as a filled square with a painted tick, rather than a
/// system radio button.
public struct SelectionDot: View {
    private let isOn: Bool
    private let colour: Color

    @Environment(\.deckTheme) private var theme

    public init(isOn: Bool, colour: Color) {
        self.isOn = isOn
        self.colour = colour
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                .strokeBorder(isOn ? colour : theme.onGround.opacity(0.3), lineWidth: 2)
                .frame(width: 22, height: 22)
            if isOn {
                RoundedRectangle(cornerRadius: DeckRadius.tight, style: .continuous)
                    .fill(colour)
                    .frame(width: 22, height: 22)
                TickMark()
                    .stroke(DeckPalette.cream, style: StrokeStyle(lineWidth: 2.4, lineCap: .round,
                                                                  lineJoin: .round))
                    .frame(width: 12, height: 9)
            }
        }
        .accessibilityHidden(true)
    }
}
