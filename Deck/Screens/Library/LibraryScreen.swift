import SwiftUI
import DeckCore

/// The library.
///
/// Browsing by category, horizontally, the way you would look along a shelf.
/// Search is instant and offline; the filters are the four questions people
/// actually ask — how many of us, how long, how hard, on my own or together.
public struct LibraryScreen: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router
    @Environment(\.deckTheme) private var theme

    @State private var query = ""
    @State private var filter = LibraryFilter()
    @State private var showsFilters = false

    public init() {}

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var results: [GameDefinition] {
        let searched = isSearching ? deck.registry.search(query) : deck.registry.all
        return filter.isEmpty ? searched : searched.filter { filter.matches($0) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DeckSpace.section) {
                header
                searchField
                if isSearching || !filter.isEmpty {
                    resultsGrid
                } else {
                    shelves
                }
            }
            .padding(.bottom, DeckSpace.xxxl)
        }
        .background(ground)
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showsFilters) {
            LibraryFilterSheet(filter: $filter)
        }
    }

    private var ground: some View {
        ZStack {
            theme.ground
            PaperGrain(intensity: theme.grain, seed: 5, tint: theme.isDark ? .white : .black)
                .opacity(theme.isDark ? 0.25 : 1)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: DeckSpace.xxs) {
                DisplayText(String(localized: "library.title", defaultValue: "LIBRARY"),
                            size: 60, colour: theme.onGround)
                Text(String(format: String(localized: "library.count",
                                           defaultValue: "%d games, all offline."),
                            deck.registry.count))
                    .font(DeckType.caption)
                    .foregroundStyle(theme.onGroundMuted)
            }
            Spacer()
            DeckIconButton(systemImage: filter.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill",
                           label: String(localized: "library.filters", defaultValue: "Filters")) {
                showsFilters = true
            }
        }
        .padding(.horizontal, DeckSpace.page)
        .padding(.top, DeckSpace.m)
    }

    private var searchField: some View {
        HStack(spacing: DeckSpace.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.onGroundMuted)
            TextField(String(localized: "library.search", defaultValue: "Search games"),
                      text: $query)
                .textFieldStyle(.plain)
                .font(DeckType.body)
                .foregroundStyle(theme.onGround)
                .autocorrectionDisabled()
            if isSearching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.onGroundMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "common.clear", defaultValue: "Clear")))
            }
        }
        .padding(DeckSpace.s)
        .background(
            RoundedRectangle(cornerRadius: DeckRadius.button, style: .continuous)
                .fill(theme.onGround.opacity(0.08))
        )
        .padding(.horizontal, DeckSpace.page)
    }

    @ViewBuilder
    private var resultsGrid: some View {
        if results.isEmpty {
            EmptyStateCard(title: String(localized: "library.noResults.title",
                                         defaultValue: "NOTHING MATCHES."),
                           message: String(localized: "library.noResults.body",
                                           defaultValue: "Try fewer filters, or a different word."),
                           emblem: .binder,
                           actionTitle: String(localized: "library.clearFilters",
                                               defaultValue: "CLEAR FILTERS")) {
                filter = LibraryFilter()
                query = ""
            }
            .padding(.horizontal, DeckSpace.page)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DeckSpace.m)],
                      spacing: DeckSpace.m) {
                ForEach(results, id: \.id) { definition in
                    GameShelfCard(definition: definition,
                                  isFavourite: deck.progress.settings.favouriteGameIDs.contains(definition.id),
                                  masteryLevel: deck.progress.mastery.level(for: definition.id)) {
                        router.push(.gameDetail(definition.id))
                    }
                }
            }
            .padding(.horizontal, DeckSpace.page)
        }
    }

    /// One horizontal shelf per category, in a fixed order.
    private var shelves: some View {
        VStack(alignment: .leading, spacing: DeckSpace.section) {
            if !favourites.isEmpty {
                shelf(title: String(localized: "library.favourites", defaultValue: "Favourites"),
                      games: favourites)
            }
            shelf(title: String(localized: "library.quick", defaultValue: "Quick"),
                  games: deck.registry.all.filter { $0.duration <= .quick })
            ForEach(GameCategory.allCases) { category in
                let games = deck.registry.games(in: category)
                if !games.isEmpty {
                    shelf(title: category.englishName, games: games)
                }
            }
        }
    }

    private var favourites: [GameDefinition] {
        deck.progress.settings.favouriteGameIDs.compactMap { deck.registry[$0] }
    }

    private func shelf(title: String, games: [GameDefinition]) -> some View {
        VStack(alignment: .leading, spacing: DeckSpace.m) {
            SectionRule(title: title)
                .padding(.horizontal, DeckSpace.page)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DeckSpace.m) {
                    ForEach(games, id: \.id) { definition in
                        GameShelfCard(definition: definition,
                                      isFavourite: deck.progress.settings.favouriteGameIDs.contains(definition.id),
                                      masteryLevel: deck.progress.mastery.level(for: definition.id)) {
                            router.push(.gameDetail(definition.id))
                        }
                        .frame(width: 164)
                    }
                }
                .padding(.horizontal, DeckSpace.page)
            }
        }
    }
}

/// The filters. Four questions, no more.
public struct LibraryFilterSheet: View {
    @Binding var filter: LibraryFilter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.deckTheme) private var theme

    public init(filter: Binding<LibraryFilter>) {
        self._filter = filter
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "filter.players", defaultValue: "Players")) {
                    ForEach([2, 3, 4, 5, 6], id: \.self) { count in
                        toggleRow(title: "\(count)", isOn: filter.playerCount == count) {
                            filter.playerCount = filter.playerCount == count ? nil : count
                        }
                    }
                    toggleRow(title: String(localized: "players.solo", defaultValue: "Solo"),
                              isOn: filter.playerCount == 1) {
                        filter.playerCount = filter.playerCount == 1 ? nil : 1
                    }
                }
                Section(String(localized: "filter.length", defaultValue: "Length")) {
                    ForEach(GameDuration.allCases, id: \.self) { duration in
                        toggleRow(title: CalloutRow.humanised(duration.localizationKey),
                                  isOn: filter.maxDuration == duration) {
                            filter.maxDuration = filter.maxDuration == duration ? nil : duration
                        }
                    }
                }
                Section(String(localized: "filter.mode", defaultValue: "Mode")) {
                    toggleRow(title: String(localized: "mode.solo", defaultValue: "Solo"),
                              isOn: filter.soloOnly) { filter.soloOnly.toggle() }
                    toggleRow(title: String(localized: "mode.passAndPlay",
                                            defaultValue: "Pass & Play"),
                              isOn: filter.passAndPlayOnly) { filter.passAndPlayOnly.toggle() }
                }
                Section(String(localized: "filter.category", defaultValue: "Category")) {
                    ForEach(GameCategory.allCases) { category in
                        toggleRow(title: category.englishName,
                                  isOn: filter.categories.contains(category)) {
                            if filter.categories.contains(category) {
                                filter.categories.remove(category)
                            } else {
                                filter.categories.insert(category)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "library.filters", defaultValue: "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "library.clearFilters", defaultValue: "Clear")) {
                        filter = LibraryFilter()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done", defaultValue: "Done")) { dismiss() }
                }
            }
        }
    }

    private func toggleRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isOn {
                    TickMark()
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round,
                                                                 lineJoin: .round))
                        .frame(width: 16, height: 12)
                }
            }
        }
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
