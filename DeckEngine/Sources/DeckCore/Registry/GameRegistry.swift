import Foundation

/// The library. Games register themselves here; nothing else hard-codes the list.
///
/// The home screen, search, filters, the daily challenge picker, the statistics
/// screen and the achievement engine all read the registry, so a new game
/// appears everywhere at once without any of them being edited.
public final class GameRegistry: @unchecked Sendable {
    private var definitions: [GameID: GameDefinition] = [:]
    private var order: [GameID] = []
    private let lock = NSLock()

    public init() {}

    public func register(_ definition: GameDefinition) {
        lock.lock()
        defer { lock.unlock() }
        if definitions[definition.id] == nil {
            order.append(definition.id)
        }
        definitions[definition.id] = definition
    }

    public func register(_ newDefinitions: [GameDefinition]) {
        for definition in newDefinitions { register(definition) }
    }

    public subscript(id: GameID) -> GameDefinition? {
        lock.lock()
        defer { lock.unlock() }
        return definitions[id]
    }

    public func definition(for id: GameID) -> GameDefinition? { self[id] }

    /// Every game, in registration order.
    public var all: [GameDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { definitions[$0] }
    }

    public var ids: [GameID] {
        lock.lock()
        defer { lock.unlock() }
        return order
    }

    public var count: Int { ids.count }

    // MARK: - Discovery

    public func games(in category: GameCategory) -> [GameDefinition] {
        all.filter { $0.categories.contains(category) }
    }

    public func games(matching filter: LibraryFilter) -> [GameDefinition] {
        all.filter { filter.matches($0) }
    }

    /// Offline, allocation-light search over names, categories and keywords.
    public func search(_ query: String) -> [GameDefinition] {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        let terms = needle.split(separator: " ").map(String.init)

        func score(_ definition: GameDefinition) -> Int {
            let haystacks = [definition.englishName.lowercased()]
                + definition.categories.map { $0.englishName.lowercased() }
                + definition.searchTerms.map { $0.lowercased() }
            var total = 0
            for term in terms {
                var best = 0
                for (index, haystack) in haystacks.enumerated() {
                    if haystack == term { best = max(best, index == 0 ? 100 : 60) }
                    else if haystack.hasPrefix(term) { best = max(best, index == 0 ? 70 : 40) }
                    else if haystack.contains(term) { best = max(best, index == 0 ? 40 : 20) }
                }
                if best == 0 { return 0 }
                total += best
            }
            return total
        }

        return all
            .map { (definition: $0, score: score($0)) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.definition.englishName < rhs.definition.englishName
            }
            .map(\.definition)
    }

    /// Games eligible to be a daily challenge, in a stable order so the
    /// deterministic picker is reproducible.
    public var dailyEligible: [GameDefinition] {
        all.filter(\.supportsDailyChallenge).sorted { $0.id < $1.id }
    }

    // MARK: - Building sessions

    public func makeSession(configuration: GameConfiguration) -> GameSessionProtocol? {
        guard let definition = self[configuration.gameID] else { return nil }
        return definition.makeSession(configuration)
    }

    public func restoreSession(from checkpoint: GameCheckpoint) throws -> GameSessionProtocol? {
        guard let definition = self[checkpoint.gameID] else { return nil }
        return try definition.restoreSession(checkpoint)
    }

    /// Every achievement in the app: the global set plus each game's own.
    public func allAchievements(global: [AchievementDefinition]) -> [AchievementDefinition] {
        global + all.flatMap(\.achievements)
    }

    /// Every statistic definition, keyed for lookup by the statistics engine.
    public var statisticsIndex: [String: StatisticDefinition] {
        var index: [String: StatisticDefinition] = [:]
        for definition in all {
            for statistic in definition.statistics {
                index[statistic.key] = statistic
            }
        }
        return index
    }
}

/// Library filtering. Everything is optional and combines with AND.
public struct LibraryFilter: Hashable, Codable, Sendable {
    public var categories: Set<GameCategory>
    public var playerCount: Int?
    public var maxDuration: GameDuration?
    public var maxComplexity: GameComplexity?
    public var soloOnly: Bool
    public var passAndPlayOnly: Bool
    public var includePremium: Bool

    public init(categories: Set<GameCategory> = [],
                playerCount: Int? = nil,
                maxDuration: GameDuration? = nil,
                maxComplexity: GameComplexity? = nil,
                soloOnly: Bool = false,
                passAndPlayOnly: Bool = false,
                includePremium: Bool = true) {
        self.categories = categories
        self.playerCount = playerCount
        self.maxDuration = maxDuration
        self.maxComplexity = maxComplexity
        self.soloOnly = soloOnly
        self.passAndPlayOnly = passAndPlayOnly
        self.includePremium = includePremium
    }

    public var isEmpty: Bool {
        categories.isEmpty && playerCount == nil && maxDuration == nil
            && maxComplexity == nil && !soloOnly && !passAndPlayOnly && includePremium
    }

    public func matches(_ definition: GameDefinition) -> Bool {
        if !categories.isEmpty && categories.isDisjoint(with: Set(definition.categories)) { return false }
        if let playerCount, !definition.playerRange.contains(playerCount) { return false }
        if let maxDuration, definition.duration > maxDuration { return false }
        if let maxComplexity, definition.complexity > maxComplexity { return false }
        if soloOnly && !definition.supportsSolo { return false }
        if passAndPlayOnly && !definition.supportsPassAndPlay { return false }
        if !includePremium && definition.requiresPremium { return false }
        return true
    }
}
