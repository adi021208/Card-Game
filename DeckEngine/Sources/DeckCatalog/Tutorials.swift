import Foundation
import DeckCore

/// The interactive tutorials.
///
/// Each one is a handful of beats: say one thing, then wait for the player to
/// make the move it just described. No wall of text, and no step that cannot be
/// completed by doing the thing being taught.
public enum Tutorials {

    public static let crazyEights = TutorialScript(steps: [
        TutorialStep(id: "goal",
                     titleKey: "tutorial.crazy8.goal.title",
                     bodyKey: "tutorial.crazy8.goal.body"),
        TutorialStep(id: "match",
                     titleKey: "tutorial.crazy8.match.title",
                     bodyKey: "tutorial.crazy8.match.body",
                     goal: .moveOfKind(.playCard)),
        TutorialStep(id: "draw",
                     titleKey: "tutorial.crazy8.draw.title",
                     bodyKey: "tutorial.crazy8.draw.body",
                     goal: .moveOfKind(.drawCard)),
        TutorialStep(id: "eights",
                     titleKey: "tutorial.crazy8.eights.title",
                     bodyKey: "tutorial.crazy8.eights.body",
                     spotlight: ["8H", "8S"]),
        TutorialStep(id: "finish",
                     titleKey: "tutorial.crazy8.finish.title",
                     bodyKey: "tutorial.crazy8.finish.body",
                     goal: .finishRound)
    ], seed: 0x8EE_0001)

    public static let hearts = TutorialScript(steps: [
        TutorialStep(id: "goal",
                     titleKey: "tutorial.hearts.goal.title",
                     bodyKey: "tutorial.hearts.goal.body"),
        TutorialStep(id: "pass",
                     titleKey: "tutorial.hearts.pass.title",
                     bodyKey: "tutorial.hearts.pass.body",
                     goal: .moveOfKind(.selectCards)),
        TutorialStep(id: "follow",
                     titleKey: "tutorial.hearts.follow.title",
                     bodyKey: "tutorial.hearts.follow.body",
                     goal: .moveOfKind(.playCard)),
        TutorialStep(id: "queen",
                     titleKey: "tutorial.hearts.queen.title",
                     bodyKey: "tutorial.hearts.queen.body",
                     spotlight: ["QS"]),
        TutorialStep(id: "moon",
                     titleKey: "tutorial.hearts.moon.title",
                     bodyKey: "tutorial.hearts.moon.body")
    ], seed: 0x4EA_0001)

    public static let texasHoldem = TutorialScript(steps: [
        TutorialStep(id: "goal",
                     titleKey: "tutorial.poker.goal.title",
                     bodyKey: "tutorial.poker.goal.body"),
        TutorialStep(id: "blinds",
                     titleKey: "tutorial.poker.blinds.title",
                     bodyKey: "tutorial.poker.blinds.body"),
        TutorialStep(id: "act",
                     titleKey: "tutorial.poker.act.title",
                     bodyKey: "tutorial.poker.act.body",
                     goal: .anyMove),
        TutorialStep(id: "board",
                     titleKey: "tutorial.poker.board.title",
                     bodyKey: "tutorial.poker.board.body"),
        TutorialStep(id: "ranking",
                     titleKey: "tutorial.poker.ranking.title",
                     bodyKey: "tutorial.poker.ranking.body",
                     spotlight: ["AS", "KS", "QS", "JS", "TS"]),
        TutorialStep(id: "showdown",
                     titleKey: "tutorial.poker.showdown.title",
                     bodyKey: "tutorial.poker.showdown.body",
                     goal: .finishRound)
    ], seed: 0x901_0001, options: ["startingChips": 500, "smallBlind": 5, "bigBlind": 10])

    public static let klondike = TutorialScript(steps: [
        TutorialStep(id: "goal",
                     titleKey: "tutorial.klondike.goal.title",
                     bodyKey: "tutorial.klondike.goal.body"),
        TutorialStep(id: "tableau",
                     titleKey: "tutorial.klondike.tableau.title",
                     bodyKey: "tutorial.klondike.tableau.body",
                     goal: .moveOfKind(.moveCards)),
        TutorialStep(id: "stock",
                     titleKey: "tutorial.klondike.stock.title",
                     bodyKey: "tutorial.klondike.stock.body",
                     goal: .moveOfKind(.drawCard)),
        TutorialStep(id: "foundation",
                     titleKey: "tutorial.klondike.foundation.title",
                     bodyKey: "tutorial.klondike.foundation.body"),
        TutorialStep(id: "kings",
                     titleKey: "tutorial.klondike.kings.title",
                     bodyKey: "tutorial.klondike.kings.body")
    ], seed: 0xC10_0001)

    public static let spades = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.spades.goal.title", bodyKey: "tutorial.spades.goal.body"),
        TutorialStep(id: "bid", titleKey: "tutorial.spades.bid.title", bodyKey: "tutorial.spades.bid.body",
                     goal: .moveOfKind(.bid)),
        TutorialStep(id: "trump", titleKey: "tutorial.spades.trump.title", bodyKey: "tutorial.spades.trump.body",
                     goal: .moveOfKind(.playCard)),
        TutorialStep(id: "bags", titleKey: "tutorial.spades.bags.title", bodyKey: "tutorial.spades.bags.body")
    ], seed: 0x5AD_0001)

    public static let ginRummy = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.gin.goal.title", bodyKey: "tutorial.gin.goal.body"),
        TutorialStep(id: "melds", titleKey: "tutorial.gin.melds.title", bodyKey: "tutorial.gin.melds.body"),
        TutorialStep(id: "draw", titleKey: "tutorial.gin.draw.title", bodyKey: "tutorial.gin.draw.body",
                     goal: .moveOfKind(.drawCard)),
        TutorialStep(id: "discard", titleKey: "tutorial.gin.discard.title", bodyKey: "tutorial.gin.discard.body",
                     goal: .moveOfKind(.discardCard)),
        TutorialStep(id: "knock", titleKey: "tutorial.gin.knock.title", bodyKey: "tutorial.gin.knock.body")
    ], seed: 0x61A_0001)

    public static let goFish = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.gofish.goal.title", bodyKey: "tutorial.gofish.goal.body"),
        TutorialStep(id: "ask", titleKey: "tutorial.gofish.ask.title", bodyKey: "tutorial.gofish.ask.body",
                     goal: .anyMove),
        TutorialStep(id: "books", titleKey: "tutorial.gofish.books.title", bodyKey: "tutorial.gofish.books.body")
    ], seed: 0x60F_0001)

    public static let cheat = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.cheat.goal.title", bodyKey: "tutorial.cheat.goal.body"),
        TutorialStep(id: "lay", titleKey: "tutorial.cheat.lay.title", bodyKey: "tutorial.cheat.lay.body",
                     goal: .moveOfKind(.claim)),
        TutorialStep(id: "call", titleKey: "tutorial.cheat.call.title", bodyKey: "tutorial.cheat.call.body"),
        TutorialStep(id: "count", titleKey: "tutorial.cheat.count.title", bodyKey: "tutorial.cheat.count.body")
    ], seed: 0xC4E_0001)

    public static let freeCell = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.freecell.goal.title", bodyKey: "tutorial.freecell.goal.body"),
        TutorialStep(id: "cells", titleKey: "tutorial.freecell.cells.title", bodyKey: "tutorial.freecell.cells.body"),
        TutorialStep(id: "lift", titleKey: "tutorial.freecell.lift.title", bodyKey: "tutorial.freecell.lift.body",
                     goal: .moveOfKind(.moveCards))
    ], seed: 0xF0E_0001)

    public static let spider = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.spider.goal.title", bodyKey: "tutorial.spider.goal.body"),
        TutorialStep(id: "suits", titleKey: "tutorial.spider.suits.title", bodyKey: "tutorial.spider.suits.body"),
        TutorialStep(id: "deal", titleKey: "tutorial.spider.deal.title", bodyKey: "tutorial.spider.deal.body",
                     goal: .moveOfKind(.dealNext))
    ], seed: 0x5D1_0001)

    public static let president = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.president.goal.title", bodyKey: "tutorial.president.goal.body"),
        TutorialStep(id: "sets", titleKey: "tutorial.president.sets.title", bodyKey: "tutorial.president.sets.body",
                     goal: .moveOfKind(.playCard)),
        TutorialStep(id: "pass", titleKey: "tutorial.president.pass.title", bodyKey: "tutorial.president.pass.body"),
        TutorialStep(id: "swap", titleKey: "tutorial.president.swap.title", bodyKey: "tutorial.president.swap.body")
    ], seed: 0x9E5_0001)

    public static let euchre = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.euchre.goal.title", bodyKey: "tutorial.euchre.goal.body"),
        TutorialStep(id: "bowers", titleKey: "tutorial.euchre.bowers.title", bodyKey: "tutorial.euchre.bowers.body",
                     spotlight: ["JS", "JC"]),
        TutorialStep(id: "order", titleKey: "tutorial.euchre.order.title", bodyKey: "tutorial.euchre.order.body",
                     goal: .moveOfKind(.bid)),
        TutorialStep(id: "alone", titleKey: "tutorial.euchre.alone.title", bodyKey: "tutorial.euchre.alone.body")
    ], seed: 0xE0C_0001)

    public static let rummy = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.rummy.goal.title", bodyKey: "tutorial.rummy.goal.body"),
        TutorialStep(id: "meld", titleKey: "tutorial.rummy.meld.title", bodyKey: "tutorial.rummy.meld.body",
                     goal: .moveOfKind(.meld)),
        TutorialStep(id: "layoff", titleKey: "tutorial.rummy.layoff.title", bodyKey: "tutorial.rummy.layoff.body"),
        TutorialStep(id: "out", titleKey: "tutorial.rummy.out.title", bodyKey: "tutorial.rummy.out.body")
    ], seed: 0x4044_0001)

    public static let speed = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.speed.goal.title", bodyKey: "tutorial.speed.goal.body"),
        TutorialStep(id: "adjacent", titleKey: "tutorial.speed.adjacent.title", bodyKey: "tutorial.speed.adjacent.body",
                     goal: .moveOfKind(.playCard)),
        TutorialStep(id: "stuck", titleKey: "tutorial.speed.stuck.title", bodyKey: "tutorial.speed.stuck.body")
    ], seed: 0x59E_0001)

    public static let war = TutorialScript(steps: [
        TutorialStep(id: "goal", titleKey: "tutorial.war.goal.title", bodyKey: "tutorial.war.goal.body"),
        TutorialStep(id: "flip", titleKey: "tutorial.war.flip.title", bodyKey: "tutorial.war.flip.body",
                     goal: .moveOfKind(.flipCard)),
        TutorialStep(id: "war", titleKey: "tutorial.war.war.title", bodyKey: "tutorial.war.war.body")
    ], seed: 0x1A2_0001)
}
