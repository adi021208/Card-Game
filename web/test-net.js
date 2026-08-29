/*
 * DECK — multi-device tests.
 *
 * Starts the real server on a port and drives it over real HTTP and a real
 * event stream, as three separate devices would. The assertions that matter
 * are the privacy ones: what the server puts on the wire for one player must
 * never contain another player's cards, and a client must not be able to
 * play out of turn, play for somebody else, or invent a move.
 *
 *   node web/test-net.js
 */
"use strict";
const http = require("http");
process.env.DECK_PACE = "0";           // opponents think instantly here
const { server, rooms, GAMES, viewFor, B } = require("./server.js");

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log("  FAIL:", m); } };
const eq = (a, b, m) => ok(a === b, `${m} — got ${JSON.stringify(a)}, expected ${JSON.stringify(b)}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let PORT = 0;
function post(path, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body || {});
    const req = http.request({ port: PORT, path, method: "POST", headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) } },
      (res) => { let s = ""; res.on("data", (c) => (s += c)); res.on("end", () => { try { resolve({ status: res.statusCode, body: JSON.parse(s || "{}") }); } catch { resolve({ status: res.statusCode, body: {} }); } }); });
    req.on("error", reject); req.write(data); req.end();
  });
}
function get(path) {
  return new Promise((resolve, reject) => {
    http.get({ port: PORT, path }, (res) => { let s = ""; res.on("data", (c) => (s += c)); res.on("end", () => resolve({ status: res.statusCode, body: s })); }).on("error", reject);
  });
}

/* A device: holds an event stream and remembers the latest view. */
function device(code, token) {
  const d = { view: null, frames: 0, req: null };
  d.req = http.get({ port: PORT, path: `/api/events?code=${code}&token=${token}` }, (res) => {
    let buf = "";
    res.on("data", (chunk) => {
      buf += chunk;
      let i;
      while ((i = buf.indexOf("\n\n")) >= 0) {
        const frame = buf.slice(0, i); buf = buf.slice(i + 2);
        const line = frame.split("\n").find((l) => l.startsWith("data: "));
        if (!line) continue;
        try { d.view = JSON.parse(line.slice(6)); d.frames++; } catch {}
      }
    });
  });
  d.close = () => d.req.destroy();
  return d;
}
const settled = async (ms = 260) => { await sleep(ms); };

(async () => {
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  PORT = server.address().port;

  /* ── The page is served, and told it is on a table ─────────────── */
  {
    const page = await get("/");
    eq(page.status, 200, "the page is served");
    ok(page.body.includes("window.DECK_SERVER = true"), "the page is told a table is serving it");
    ok(page.body.includes("<title>DECK</title>"), "and it is the real page");
  }

  /* ── Three people sit down ─────────────────────────────────────── */
  const host = (await post("/api/create", { name: "Ada" })).body;
  ok(/^[A-Z2-9]{4}$/.test(host.code), `the table has a four-character code — got ${host.code}`);
  ok(!!host.token, "the host gets a token");

  const two = (await post("/api/join", { code: host.code, name: "Grace" })).body;
  const three = (await post("/api/join", { code: host.code, name: "Alan" })).body;
  eq(two.seat, 1, "the second player takes seat 1");
  eq(three.seat, 2, "the third takes seat 2");
  ok(two.token !== host.token && three.token !== two.token, "everybody gets their own token");

  const bad = await post("/api/join", { code: "ZZZZ", name: "Nobody" });
  eq(bad.status, 404, "a wrong code is refused");
  ok(/code/i.test(bad.body.error), "and the message says what to check");

  const dA = device(host.code, host.token);
  const dB = device(host.code, two.token);
  const dC = device(host.code, three.token);
  await settled();
  ok(dA.view && dA.view.phase === "lobby", "the host's device sees the lobby");
  eq(dA.view.host, true, "the first player is the host");
  eq(dB.view.host, false, "the second is not");
  eq(dA.view.players.length, 3, "everybody is listed");
  ok(dA.view.games.length >= 8, `the lobby offers the multiplayer games — ${dA.view.games.length}`);
  ok(!dA.view.games.some((g) => g.id === "klondike"), "and does not offer solitaire");

  /* ── Only the host runs the table ──────────────────────────────── */
  {
    const r = await post("/api/start", { code: host.code, token: two.token, gameId: "hearts" });
    eq(r.status, 403, "a guest cannot start the game");
    const s = await post("/api/seat", { code: host.code, token: two.token, add: true });
    eq(s.status, 403, "a guest cannot add opponents");
  }

  /* ── Hearts needs four, so the host adds one ───────────────────── */
  {
    const tooFew = await post("/api/start", { code: host.code, token: host.token, gameId: "hearts" });
    eq(tooFew.status, 400, "starting with too few players is refused");
    ok(/at least 4/.test(tooFew.body.error), `and says how many are needed — "${tooFew.body.error}"`);
  }
  await post("/api/seat", { code: host.code, token: host.token, add: true });
  await settled();
  eq(dA.view.players.length, 4, "an opponent joined the table");
  ok(dA.view.players[3].ai, "and it is marked as an opponent");

  const started = await post("/api/start", { code: host.code, token: host.token, gameId: "hearts", difficulty: "skilled" });
  eq(started.status, 200, "the host starts the game");
  await settled(500);
  eq(dA.view.phase, "playing", "the table is playing");

  /* ── The wire carries nobody else's cards ──────────────────────── */
  const room = rooms.get(host.code);

  /* Every card a payload names, by id. A redacted card serialises as
     { known: false, id } and carries no rank or suit; a named one is
     { known: true, id, suit, rank }. */
  function namedIds(payload) {
    const out = new Set();
    const walk = (x) => {
      if (!x || typeof x !== "object") return;
      if (Array.isArray(x)) { x.forEach(walk); return; }
      if (x.known === true && typeof x.id === "number") out.add(x.id);
      for (const k of Object.keys(x)) walk(x[k]);
    };
    walk(payload);
    return out;
  }

  /* Built from the live state through the very function that feeds the
     wire, so there is no window in which the two could disagree. */
  function assertPrivate(label) {
    if (!room.run) { pass++; return; }
    const st = room.run.state;
    for (const p of room.players) {
      if (p.ai) continue;
      const view = viewFor(room, p);
      for (const id of namedIds(view)) {
        if (!B.canSee(st.board, id, p.seat)) {
          const c = st.board.cards.get(id);
          const where = st.seats.map((x) => `hand:${x}`).find((z) => (st.board.piles.get(z) || []).includes(id)) || "the table";
          ok(false, `${label} — ${p.name}'s payload named ${c ? c.rank + c.suit : id}, which is in ${where} and not theirs to see`);
          return;
        }
      }
    }
    pass++;
  }
  assertPrivate("at the deal");

  ok(dA.view.hand.length === 13, `the host holds thirteen — got ${dA.view.hand.length}`);
  ok(dA.view.hand.every((c) => c.known), "and can read every one of them");
  ok(!("board" in dA.view), "the raw board is never sent");
  ok(!("state" in dA.view), "nor the raw state");

  /* ── A client cannot move out of turn, or for anyone else ──────── */
  {
    const notYou = room.run.state.seats.find((s) => s !== dA.view.active && s < 3);
    const tok = [host.token, two.token, three.token][notYou];
    const r = await post("/api/action", { code: host.code, token: tok, action: { t: "select", id: 0 } });
    ok(r.status === 403 || r.status === 400, `a player off turn is refused — got ${r.status}`);
  }
  {
    const active = dA.view.active;
    const tok = [host.token, two.token, three.token][active];
    if (tok) {
      const r = await post("/api/action", { code: host.code, token: tok, action: { t: "select", id: 9999 } });
      eq(r.status, 400, "an invented move is refused");
      ok(/not available/i.test(r.body.error), "and says so plainly");
    }
  }
  {
    const r = await post("/api/action", { code: host.code, token: "not-a-real-token", action: { t: "select", id: 0 } });
    eq(r.status, 403, "an unknown token cannot play at all");
  }

  /* ── Play the game out over the wire ───────────────────────────── */
  const devices = { 0: [dA, host.token], 1: [dB, two.token], 2: [dC, three.token] };
  let moves = 0, idle = 0;
  while (moves < 8000 && idle < 300) {
    const v = dA.view;
    if (!v || v.phase === "over") break;
    const active = v.active;
    const pair = devices[active];
    if (pair === undefined) { await sleep(4); idle++; continue; }    // an AI seat
    const [dev, tok] = pair;
    const legal = dev.view && dev.view.legal;
    if (!legal || !legal.length) { await sleep(4); idle++; continue; }
    const r = await post("/api/action", { code: host.code, token: tok, action: legal[0] });
    if (r.status !== 200) { idle++; await sleep(4); continue; }
    idle = 0; moves++;
    if (moves % 12 === 0) assertPrivate(`after ${moves} moves`);
  }
  ok(dA.view.phase === "over", `the game finished over the wire — phase ${dA.view.phase} after ${moves} moves`);
  if (dA.view.phase === "over") {
    ok(Array.isArray(dA.view.done.winners) && dA.view.done.winners.length > 0, "a winner is named");
    ok(Object.keys(dA.view.done.scores).length === 4, "every seat is scored");
    ok(dB.view.done && JSON.stringify(dB.view.done) === JSON.stringify(dA.view.done), "everybody sees the same result");
  }

  /* ── Reconnecting keeps the seat ───────────────────────────────── */
  {
    const again = await post("/api/join", { code: host.code, token: two.token, name: "Grace" });
    eq(again.status, 200, "rejoining with a token is allowed");
    eq(again.body.seat, 1, "and lands in the same seat");
    const stranger = await post("/api/join", { code: host.code, name: "Latecomer" });
    eq(stranger.status, 409, "but a new player cannot join a game in progress");
  }

  /* ── Leaving ───────────────────────────────────────────────────── */
  {
    dC.close();
    await post("/api/leave", { code: host.code, token: three.token });
    await settled();
    const left = dA.view.players.find((p) => p.name === "Alan");
    ok(left && left.online === false, "a player who leaves mid-game keeps their seat, marked away");
  }

  dA.close(); dB.close();
  await sleep(80);
  server.close();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
