import SwiftUI
import Observation
import DeckCore
import DeckProgression

/// Where the app can go.
public enum DeckDestination: Hashable {
    case gameDetail(GameID)
    case gameSetup(GameID, mode: PlayMode)
    case library(GameCategory?)
    case achievements
    case statistics
    case mastery(GameID?)
    case collection(CosmeticKind?)
    case bosses
    case boss(String)
    case profile
    case profiles
    case settings
    case premium
    case history
    case leaderboards
    case rules(GameID)
    case tutorial(GameID)
}

public enum PlayMode: String, Hashable, Sendable, CaseIterable {
    case solo
    case passAndPlay

    public var localizationKey: String { "mode.\(rawValue)" }
}

/// The five places the app is organised into.
public enum DeckTab: String, CaseIterable, Identifiable, Hashable {
    case today
    case play
    case library
    case collection
    case profile

    public var id: String { rawValue }
    public var localizationKey: String { "tab.\(rawValue)" }
    public var systemImage: String {
        switch self {
        case .today: return "calendar"
        case .play: return "play.fill"
        case .library: return "square.grid.2x2.fill"
        case .collection: return "square.stack.3d.up.fill"
        case .profile: return "person.fill"
        }
    }
}

/// How the app is about to move from one place to another.
///
/// Transitions are a signature of the product, so they are chosen deliberately
/// rather than falling out of whatever `NavigationStack` does by default.
public enum DeckTransition: Equatable, Sendable {
    /// Cards gather into a deck, the deck turns, the next screen spreads out.
    case deckFlip
    /// A painted stroke wipes across.
    case paintWipe
    /// A paper layer slides away.
    case paperTear
    /// Cards cascade across and settle into the new screen.
    case cardCascade
    /// A stamp lands and the screen is revealed underneath it.
    case stamp
    /// A suit mark expands into the destination's identity.
    case suitTransform(SuitShape.Kind)
    /// Plain. Used inside a screen, where a signature transition would be noise.
    case none

    /// Picks the transition that says the most about the move being made.
    ///
    /// Going from one game to another is the moment worth spending motion on;
    /// opening a settings list is not.
    public static func between(from: GameID?, to: GameID?, registry: GameRegistry) -> DeckTransition {
        guard let to else { return .paintWipe }
        guard let destination = registry[to] else { return .paintWipe }
        // A game with a suit at the centre of its identity transforms into it.
        switch to {
        case .hearts: return .suitTransform(.heart)
        case .spades: return .suitTransform(.spade)
        case .cheat, .president, .crazyEights: return .cardCascade
        case .texasHoldem: return .deckFlip
        default:
            if destination.categories.contains(.solitaire) { return .cardCascade }
            if from != nil { return .deckFlip }
            return .paintWipe
        }
    }
}

/// Navigation state.
@MainActor
@Observable
public final class AppRouter {
    public var tab: DeckTab = .today
    public var todayPath = NavigationPath()
    public var playPath = NavigationPath()
    public var libraryPath = NavigationPath()
    public var collectionPath = NavigationPath()
    public var profilePath = NavigationPath()

    /// A game currently on screen, presented over the tabs.
    public var activeGame: ActiveGame?
    /// The transition to run when the game screen appears.
    public var pendingTransition: DeckTransition = .none
    /// Set on first launch until the player has been through the welcome.
    public var showsWelcome = false
    /// The unlock posters queued up behind whatever is on screen.
    public var pendingPosters: [UnlockPoster] = []

    public struct ActiveGame: Identifiable, Equatable {
        public var id = UUID()
        public var gameID: GameID
        public var challenge: DailyChallenge?
        public var isTutorial: Bool

        public static func == (lhs: ActiveGame, rhs: ActiveGame) -> Bool { lhs.id == rhs.id }
    }

    public enum UnlockPoster: Identifiable, Equatable {
        case achievement(String)
        case cosmetic(String)
        case boss(String)

        public var id: String {
            switch self {
            case let .achievement(value): return "a-\(value)"
            case let .cosmetic(value): return "c-\(value)"
            case let .boss(value): return "b-\(value)"
            }
        }
    }

    public init() {}

    public func push(_ destination: DeckDestination) {
        switch tab {
        case .today: todayPath.append(destination)
        case .play: playPath.append(destination)
        case .library: libraryPath.append(destination)
        case .collection: collectionPath.append(destination)
        case .profile: profilePath.append(destination)
        }
    }

    public func popToRoot() {
        switch tab {
        case .today: todayPath = NavigationPath()
        case .play: playPath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        case .collection: collectionPath = NavigationPath()
        case .profile: profilePath = NavigationPath()
        }
    }

    public func openGame(_ gameID: GameID,
                         challenge: DailyChallenge? = nil,
                         isTutorial: Bool = false,
                         transition: DeckTransition = .deckFlip) {
        pendingTransition = transition
        activeGame = ActiveGame(gameID: gameID, challenge: challenge, isTutorial: isTutorial)
    }

    public func closeGame() {
        activeGame = nil
        pendingTransition = .none
    }

    public func queue(_ posters: [UnlockPoster]) {
        pendingPosters.append(contentsOf: posters)
    }

    public func dismissTopPoster() {
        if !pendingPosters.isEmpty { pendingPosters.removeFirst() }
    }
}
