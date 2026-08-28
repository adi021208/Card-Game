import Foundation
import DeckCore
import DeckGames
import DeckAI

/// Builds the pair of closures every `GameDefinition` needs, so registering a
/// game is one line rather than a page of boilerplate.
///
/// This is the only place a concrete rules type meets its AI agent. Everything
/// above this line works with `GameSessionProtocol` and never learns which game
/// is running.
public enum GameFactory {

    public static func session<Rules: GameRules>(
        _ rules: Rules,
        agent: @escaping GameAgentFunction<Rules>
    ) -> (make: (GameConfiguration) -> GameSessionProtocol,
          restore: (GameCheckpoint) throws -> GameSessionProtocol) {
        let make: (GameConfiguration) -> GameSessionProtocol = { configuration in
            GameSession(rules: rules, configuration: configuration, agent: agent)
        }
        let restore: (GameCheckpoint) throws -> GameSessionProtocol = { checkpoint in
            try GameSession.restore(rules: rules, checkpoint: checkpoint, agent: agent)
        }
        return (make, restore)
    }

    /// For games with no opponent to model — the solitaires.
    public static func soloSession<Rules: GameRules>(
        _ rules: Rules
    ) -> (make: (GameConfiguration) -> GameSessionProtocol,
          restore: (GameCheckpoint) throws -> GameSessionProtocol) {
        session(rules) { _, legal, _, _ in legal.first }
    }
}
