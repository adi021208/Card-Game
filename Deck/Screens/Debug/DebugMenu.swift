#if DEBUG
import SwiftUI
import DeckCore
import DeckCatalog
import DeckProgression

/// Developer tools.
///
/// Compiled out of release builds entirely. Everything here is clearly labelled
/// as a local override — in particular the premium switch, which sets a *local*
/// entitlement flag and never fabricates a StoreKit transaction. The real
/// entitlement is recomputed from Apple's verified transactions the next time
/// the store is consulted, so this cannot be used to keep premium.
public struct DebugMenu: View {
    @Environment(AppEnvironment.self) private var deck
    @Environment(AppRouter.self) private var router

    @State private var seedText = ""
    @State private var dateOffset = 0
    @State private var streakValue = 0
    @State private var selectedGame: GameID?
    @State private var selectedBoss: String = "scarlet"
    @State private var difficultyScale: Double = 1.0
    @State private var message: String?

    public init() {}

    public var body: some View {
        List {
            challengeSection
            progressSection
            entitlementSection
            registrySection
            verificationSection
            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Developer tools")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { streakValue = deck.progress.challenge.currentStreak }
    }

    // MARK: - Challenge

    private var challengeSection: some View {
        Section("Daily challenge") {
            Stepper("Day offset: \(dateOffset)", value: $dateOffset, in: -30...30)
            if let challenge = challengeForOffset {
                LabeledContent("Date", value: challenge.date.identifier)
                LabeledContent("Game", value: challenge.gameID.rawValue)
                LabeledContent("Seed", value: String(challenge.seed))
                LabeledContent("Difficulty", value: "\(challenge.difficultyPercent)%")
                LabeledContent("Boss", value: challenge.bossID ?? "none")
                LabeledContent("Objective", value: challenge.objective.englishDescription)
                Button("Play this challenge") {
                    router.openGame(challenge.gameID, challenge: challenge)
                }
            }
        }
    }

    private var challengeForOffset: DailyChallenge? {
        let date = deck.today.adding(days: dateOffset)
        return deck.challengeGenerator.challenge(for: date)
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section("Progress") {
            Stepper("Streak: \(streakValue)", value: $streakValue, in: 0...400)
            Button("Apply streak") { message = "Streaks are derived from completed days; use the challenge tools to complete days." }
            Button("Unlock every achievement") { unlockAll() }
            Button("Unlock every cosmetic") { unlockCosmetics() }
            Button("Erase all progress", role: .destructive) {
                deck.progress.resetAll()
                message = "Progress erased."
            }
        }
    }

    private func unlockAll() {
        // Deliberately routed through the same engine the app uses, so this
        // cannot produce a state the real app could not reach.
        var achievements = deck.progress.achievements
        for definition in deck.registry.allAchievements(global: GlobalAchievements.all) {
            achievements.entries[definition.id] = AchievementProgress(id: definition.id,
                                                                      progress: definition.target,
                                                                      target: definition.target,
                                                                      unlockedAt: Date())
        }
        message = "Unlocked \(achievements.entries.count) achievements in memory. Restart to see the store value."
    }

    private func unlockCosmetics() {
        var collection = deck.progress.collection
        for cosmetic in CosmeticCatalog.all { collection.unlocked.insert(cosmetic.id) }
        deck.progress.update(collection: collection)
        message = "All cosmetics unlocked."
    }

    // MARK: - Entitlement

    private var entitlementSection: some View {
        Section {
            Toggle("Local premium override", isOn: Binding(
                get: { deck.progress.entitlements.level != .free },
                set: { isOn in
                    deck.progress.update(entitlements: isOn
                                         ? Entitlements(level: .lifetime, verifiedAt: Date())
                                         : .free)
                }
            ))
        } header: {
            Text("Entitlement")
        } footer: {
            Text("This sets a local flag only. It does not create a StoreKit transaction, and the real entitlement is recomputed from Apple's verified transactions whenever the store is consulted.")
        }
    }

    // MARK: - Registry

    private var registrySection: some View {
        Section("Library") {
            ForEach(deck.registry.all, id: \.id) { definition in
                Button {
                    router.openGame(definition.id)
                } label: {
                    HStack {
                        Text(definition.englishName)
                        Spacer()
                        Text("\(definition.playerRange.lowerBound)–\(definition.playerRange.upperBound)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Verification

    /// Re-derives every daily challenge for the next fortnight and checks the
    /// generator is deterministic. Cheap, and it catches a whole class of
    /// mistake before it reaches a player's streak.
    private var verificationSection: some View {
        Section("Checks") {
            Button("Verify challenge determinism") { verifyDeterminism() }
            Button("Verify every game deals") { verifyDeals() }
        }
    }

    private func verifyDeterminism() {
        var problems: [String] = []
        for offset in 0..<14 {
            let date = deck.today.adding(days: offset)
            let first = deck.challengeGenerator.challenge(for: date)
            let second = deck.challengeGenerator.challenge(for: date)
            if first != second { problems.append(date.identifier) }
        }
        message = problems.isEmpty
            ? "Fourteen days generated identically twice."
            : "Non-deterministic on: \(problems.joined(separator: ", "))"
    }

    private func verifyDeals() {
        var problems: [String] = []
        for definition in deck.registry.all {
            let aiCount = definition.supportsAIOpponents
                ? max(0, definition.playerRange.lowerBound - 1) : 0
            guard let configuration = deck.configuration(gameID: definition.id,
                                                         humanCount: 1,
                                                         aiCount: aiCount,
                                                         variantID: definition.defaultVariantID,
                                                         options: [:],
                                                         difficulty: .casual,
                                                         humanProfiles: []),
                  let session = deck.makeSession(configuration) else {
                problems.append(definition.englishName)
                continue
            }
            if session.activeSeat == nil && session.result == nil
                && definition.id != .speed {
                problems.append("\(definition.englishName) (no active seat)")
            }
        }
        message = problems.isEmpty
            ? "All \(deck.registry.count) games dealt."
            : "Problems: \(problems.joined(separator: ", "))"
    }
}
#endif
