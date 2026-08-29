/*
 * DECK — engine tests for the web build.
 *
 * Reads index.html, evaluates everything above the UI layer, and exercises
 * it the way DeckEngine/Tests exercises the Swift original: the poker
 * evaluator against known hands, the generator's determinism, the Pass &
 * Play coordinator's phases, and every game played to completion by AI in
 * every seat — asserting along the way that no seat can ever read another
 * seat's hand, and that a hand is illegible when nobody is holding the
 * device.
 *
 *   node web/test.js
 */
"use strict";
const fs = require("fs"), path = require("path");
const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const body = html.slice(html.indexOf("<script>\n") + 9, html.lastIndexOf("</script>"));
const engine = body.slice(0, body.indexOf("/* \u2550\u2550\u2550"));
const marker = body.indexOf("   UI\n");
const src = body.slice(0, body.lastIndexOf("/* \u2550", marker));
const E = {};
new Function("module", "exports", src + "\nmodule.exports = { GAMES, CAST, rngFrom, B, Z, Privacy, buildDeck, evaluate, cmpHands, choose };")
  ({ get exports() { return E.x; }, set exports(v) { E.x = v; } }, null);
const { GAMES, CAST, rngFrom, B, Z, Privacy, buildDeck, evaluate, cmpHands } = E.x;
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log("  FAIL:", m); } };
const eq = (a, b, m) => ok(a === b, `${m} — got ${a}, expected ${b}`);

/* ── Poker hand evaluation ─────────────────────────────────────── */
const C = (t) => { const r = { "2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"9":9,"T":10,"J":11,"Q":12,"K":13,"A":14 }[t[0]]; return { id: Math.random()*1e9|0, suit: t[1], rank: r }; };
const H = (...ts) => ts.map(C);
console.log("Poker evaluator");
eq(evaluate(H("AS","KS","QS","JS","TS","2C","3D")).name, "Royal flush", "royal flush");
eq(evaluate(H("9S","8S","7S","6S","5S","2C","3D")).cat, 8, "straight flush");
eq(evaluate(H("9S","9C","9D","9H","5S","2C","3D")).cat, 7, "quads");
eq(evaluate(H("9S","9C","9D","5H","5S","2C","3D")).cat, 6, "full house");
eq(evaluate(H("AS","9S","7S","5S","3S","2C","4D")).cat, 5, "flush");
eq(evaluate(H("AS","2C","3D","4H","5S","9C","KD")).cat, 4, "wheel straight");
eq(evaluate(H("AS","2C","3D","4H","5S","9C","KD")).tie[0], 5, "wheel is five-high");
eq(evaluate(H("KS","QC","JD","TH","9S","2C","3D")).tie[0], 13, "king-high straight");
eq(evaluate(H("9S","9C","9D","5H","3S","2C","KD")).cat, 3, "trips");
eq(evaluate(H("9S","9C","5D","5H","3S","2C","KD")).cat, 2, "two pair");
eq(evaluate(H("9S","9C","5D","4H","3S","2C","KD")).cat, 1, "one pair");
eq(evaluate(H("9S","7C","5D","4H","3S","2C","KD")).cat, 0, "high card");
ok(cmpHands(evaluate(H("AS","AC","AD","AH","KS","2C","3D")), evaluate(H("KS","KC","KD","KH","AS","2C","4D"))) > 0, "aces over kings, quads");
ok(cmpHands(evaluate(H("AS","AC","KD","KH","QS","2C","3D")), evaluate(H("AS","AC","KD","KH","JS","2C","3D"))) > 0, "two pair kicker decides");
ok(cmpHands(evaluate(H("AS","AC","KD","KH","QS","2C","3D")), evaluate(H("AD","AH","KS","KC","QD","2C","3D"))) === 0, "identical hands tie");
ok(evaluate(H("KS","AC","2D","3H","4S","9C","JD")).cat < 4, "K-A-2-3-4 does not wrap");

/* ── Determinism ───────────────────────────────────────────────── */
console.log("Determinism");
{
  const a = rngFrom(12345), b = rngFrom(12345);
  ok(Array.from({length: 50}, () => a()).join() === Array.from({length: 50}, () => b()).join(), "same seed, same stream");
  const base = rngFrom(999); const br = base.branch(7);
  for (let i = 0; i < 500; i++) br();
  const after = base();
  const fresh = rngFrom(999); fresh.branch(7);
  ok(after === fresh(), "burning a branch does not disturb the parent");
}

/* ── Privacy ───────────────────────────────────────────────────── */
console.log("Privacy");
{
  const isHuman = (s) => s < 2;                 // seats 0,1 human; 2,3 AI
  const p = Privacy.make([0,1,2,3], isHuman);
  Privacy.open(p, 0);
  eq(Privacy.viewer(p), null, "opening with two humans seals first");
  eq(p.phase, "handoff", "first phase is a handoff");
  Privacy.confirm(p);
  eq(Privacy.viewer(p), 0, "after confirming, seat 0 sees");
  eq(Privacy.turnMoved(p, 2), "none", "an AI turn does not pass the device");
  /* The return value above only says no seal was raised. What matters is
     where the screen was left: on the person holding it. A computer seat
     that becomes the viewer gets the table redacted in its favour, which
     draws its hand face up. */
  eq(Privacy.viewer(p), 0, "and an AI turn leaves the screen with the person holding it");
  eq(Privacy.turnMoved(p, 3), "none", "a second AI in a row, likewise");
  eq(Privacy.viewer(p), 0, "still seat 0's screen");
  eq(Privacy.turnMoved(p, 1), "handoff", "a different human does");
  eq(Privacy.viewer(p), null, "and nobody sees anything in transit");
  Privacy.confirm(p);
  eq(Privacy.viewer(p), 1, "seat 1 sees after confirming");
  eq(Privacy.turnMoved(p, 1), "none", "same human twice is not a handoff");
  ok(Privacy.shield(p), "backgrounding re-seals");
  eq(Privacy.viewer(p), null, "and hides the hand");
  const solo = Privacy.make([0,1], (s) => s === 0);
  Privacy.open(solo, 0);
  eq(Privacy.viewer(solo), 0, "a solo game never asks for a handoff");
  eq(Privacy.turnMoved(solo, 1), "none", "and the machine's turn raises nothing");
  eq(Privacy.viewer(solo), 0, "and never becomes the viewer");
  ok(!Privacy.shield(solo), "alone against a machine there is nobody to hide from");
  eq(Privacy.viewer(solo), 0, "so backgrounding a solo game keeps your seat");

  /* A computer dealing first must not put its own hand on the screen
     while the humans are still waiting to be handed the device. */
  const aiFirst = Privacy.make([0,1,2], (s) => s < 2);
  eq(Privacy.open(aiFirst, 2), "none", "a computer opening raises no seal");
  eq(Privacy.viewer(aiFirst), null, "and shows nobody's hand");
  eq(Privacy.turnMoved(aiFirst, 0), "handoff", "the first person to act is handed the device");
  Privacy.confirm(aiFirst);
  eq(Privacy.viewer(aiFirst), 0, "and only then does a hand appear");

  /* The invariant, stated once: whatever sequence of turns arrives, the
     viewer is a person or nobody — never a machine. */
  const seats = [0,1,2,3], human = (s) => s < 2;
  const q = Privacy.make(seats, human);
  Privacy.open(q, 0); Privacy.confirm(q);
  let held = 0;
  const r = rngFrom(99);
  for (let i = 0; i < 4000; i++) {
    const seat = seats[r.int(4)];
    if (Privacy.turnMoved(q, seat) === "handoff" && r.chance(.8)) Privacy.confirm(q);
    if (r.chance(.05)) Privacy.shield(q);
    const v = Privacy.viewer(q);
    if (v !== null && !human(v)) { ok(false, `a machine held the screen after seat ${seat} moved`); break; }
    if (v !== null) held++;
  }
  ok(held > 0, "and somebody does hold it along the way");
}

/* ── Redaction ─────────────────────────────────────────────────── */
console.log("Redaction");
{
  const b = B ? null : null;
}

/* ── Every game plays to completion with AI in every seat ──────── */
console.log("Full games");
const prof = (id) => { const p = CAST.find((c) => c.id === id) || CAST[0]; return { ...p }; };

for (const g of Object.values(GAMES)) {
  for (let trial = 0; trial < 12; trial++) {
    const n = Math.min(g.max, Math.max(g.min, [1,2,3,4,5,6][trial % 6]));
    const players = Math.max(g.min, Math.min(g.max, n));
    const seats = Array.from({length: players}, (_, i) => ({ name: "P" + i, ai: CAST[i % CAST.length].id }));
    const seed = (trial * 7919 + 13) >>> 0;
    const rng = rngFrom(seed);
    let st;
    try { st = g.setup({ seats }, rng); } catch (e) { fail++; console.log(`  FAIL: ${g.id} setup threw (${players}p, seed ${seed}): ${e.message}`); continue; }
    st.names = seats.map((s) => s.name);

    // Every card is accounted for, and nobody can see another hand.
    const total = st.board.cards.size;
    ok(total > 0, `${g.id} deals cards`);
    let leak = false, transit = false;
    for (const s of st.seats) {
      for (const o of st.seats) {
        if (o === s) continue;
        for (const id of B.at(st.board, Z.hand(o))) {
          if (B.canSee(st.board, id, s)) leak = true;
          if (B.visible(st.board, id, s).known) leak = true;
        }
      }
      // Nobody at all — the device in transit — must see no hand.
      for (const id of B.at(st.board, Z.hand(s))) if (B.visible(st.board, id, null).known) transit = true;
    }
    ok(!leak, `${g.id} — a seat could read another seat's hand`);
    ok(!transit, `${g.id} — a hand is legible with no viewer (device in transit)`);

    let moves = 0, stuck = 0;
    while (!st.done && moves < 6000) {
      if (g.auto) { const ev = g.auto(st, rng); if (ev.length) { stuck = 0; continue; } }
      if (st.done) break;
      /* A simultaneous game nominates nobody, so anybody with a move may
         take one. Everything else has exactly one seat on the clock. */
      const actors = st.active === null || st.active === undefined ? st.seats : [st.active];
      let seat = null, legal = [];
      for (const cand of actors) { const l = g.legal(st, cand); if (l.length) { seat = cand; legal = l; break; } }
      if (seat === null) { if (++stuck > 3) break; continue; }
      stuck = 0;
      const think = rng.branch(moves);
      let a;
      try { a = g.agent(st, seat, legal, prof(seats[seat].ai), think) || legal[0]; }
      catch (e) { fail++; console.log(`  FAIL: ${g.id} agent threw: ${e.message}`); break; }
      ok(legal.includes(a) || legal.some((x) => JSON.stringify(x) === JSON.stringify(a)), `${g.id} agent chose an offered move`);
      try { g.apply(st, a, rng); } catch (e) { fail++; console.log(`  FAIL: ${g.id} apply threw on ${JSON.stringify(a)}: ${e.message}`); break; }
      moves++;
      // The table must always render without throwing, for every viewer.
      if (moves % 25 === 0) {
        for (const v of [null, ...st.seats]) {
          try { g.table(st, v); } catch (e) { fail++; console.log(`  FAIL: ${g.id} table(${v}) threw: ${e.message}`); break; }
        }
      }
    }
    if (!st.done && g.solo) { ok(moves > 50, `${g.id} kept offering legal moves`); }
    else if (!st.done) { fail++; console.log(`  FAIL: ${g.id} did not finish (${players}p, seed ${seed}) after ${moves} moves`); }
    else {
      ok(Array.isArray(st.done.winners) && st.done.winners.length > 0, `${g.id} named a winner`);
      ok(st.done.scores && Object.keys(st.done.scores).length === st.seats.length, `${g.id} scored every seat`);
    }
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
