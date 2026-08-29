#!/usr/bin/env node
/*
 * DECK — the table server.
 *
 * Run this on one machine and everybody on your tailnet plays from their
 * own phone. There is nothing to deploy and nothing to pay for: the
 * machine you start it on is the table.
 *
 *   node web/server.js            # then open the printed address
 *   node web/server.js --port 8080
 *
 * Why this is the private way to do it
 * ------------------------------------
 * The server holds the only complete game state. Each connected device is
 * sent its own redacted view and nothing else — a card you are not
 * entitled to see is never serialised, so it never crosses the network and
 * never reaches your opponent's browser. That is a stronger guarantee than
 * passing one device around, where the whole state is on the device the
 * whole time.
 *
 * There is one engine. This file reads it out of index.html at boot rather
 * than keeping a second copy, so the rules the server enforces are exactly
 * the rules the browser was written against.
 */
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

const HTML_PATH = path.join(__dirname, "index.html");

/* How long an opponent appears to think, and how long a scored hand sits
   before the next deal. Multiplied by DECK_PACE so tests can run flat out
   without changing what the game does. */
const PACE = Number(process.env.DECK_PACE ?? 1);
const paced = (ms) => Math.round(ms * PACE);

/* ── Load the shared engine out of the page ──────────────────────── */
function loadEngine() {
  const html = fs.readFileSync(HTML_PATH, "utf8");
  const src = html.slice(html.indexOf("<script>\n") + 9, html.lastIndexOf("</script>"));
  // The UI section opens with a banner comment whose heading line is "UI".
  const heading = src.indexOf("\n   UI\n");
  const uiAt = heading < 0 ? -1 : src.lastIndexOf("/*", heading);
  if (uiAt < 0) throw new Error("could not find the UI boundary in index.html");
  const api = {};
  new Function("__out", src.slice(0, uiAt) +
    "\n__out.GAMES = GAMES; __out.CAST = CAST; __out.DIFFICULTY = DIFFICULTY;" +
    "\n__out.rngFrom = rngFrom; __out.B = B; __out.Z = Z; __out.tableFor = tableFor;" +
    "\n__out.Profile = Profile; __out.Daily = Daily; __out.ACHIEVEMENTS = ACHIEVEMENTS;" +
    "\n__out.METRICS = METRICS; __out.BOSSES = BOSSES; __out.mastery = mastery; __out.metricsFrom = metricsFrom;")(api);
  return api;
}
const E = loadEngine();
const { GAMES, CAST, DIFFICULTY, rngFrom, B, Z, tableFor, Profile, Daily, ACHIEVEMENTS, METRICS, BOSSES, mastery, metricsFrom } = E;

/* ── Who you are ─────────────────────────────────────────────────────
   Identity is the device's address. On a tailnet that is exactly right:
   Tailscale hands each device a stable 100.x address that follows it
   between networks, so your statistics find you with no account, no
   password and nothing to sign into.

   It is only right on a private network. Behind shared NAT on the open
   internet, everybody would look like the same person — so the address
   is the key, and the name is yours to change. */
const PROFILES = path.join(__dirname, ".profiles.json");
let profiles = {};
try { profiles = JSON.parse(fs.readFileSync(PROFILES, "utf8")); } catch { profiles = {}; }
let saveTimer = null;
/* Written through a temporary file and renamed, so a crash mid-write
   cannot leave a half-written file where everybody's record used to be. */
function flushProfiles() {
  clearTimeout(saveTimer); saveTimer = null;
  const tmp = PROFILES + ".tmp";
  try { fs.writeFileSync(tmp, JSON.stringify(profiles, null, 1)); fs.renameSync(tmp, PROFILES); }
  catch (e) { console.error("could not save profiles:", e.message); }
}
function saveProfiles() {
  if (saveTimer) return;
  saveTimer = setTimeout(flushProfiles, 400);
  if (saveTimer.unref) saveTimer.unref();
}
/* A debounced write must never be the last word. Anything still pending
   goes to disk before the process goes away. */
for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => { flushProfiles(); process.exit(0); });
process.on("exit", () => { if (saveTimer) flushProfiles(); });
function addressOf(req) {
  const raw = (req.socket && req.socket.remoteAddress) || "unknown";
  return raw.replace(/^::ffff:/, "");             // IPv4 inside IPv6
}
function profileFor(req, name) {
  const key = addressOf(req);
  if (!profiles[key]) { profiles[key] = Profile.blank(name || "Player"); profiles[key].address = key; saveProfiles(); }
  const p = profiles[key];
  if (name && name !== p.name) { p.name = name; saveProfiles(); }
  Profile.expireStreak(p, Daily.today());
  return p;
}

/* ── Rooms ───────────────────────────────────────────────────────── */
const rooms = new Map();
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";   // no I/O/0/1
const newCode = () => {
  let c;
  do { c = Array.from({ length: 4 }, () => CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)]).join(""); }
  while (rooms.has(c));
  return c;
};
const newToken = () => crypto.randomBytes(16).toString("hex");

function makeRoom() {
  const code = newCode();
  const room = {
    code, players: [], clients: new Set(), run: null,
    gameId: null, difficulty: "skilled", log: [], created: Date.now(), busy: false,
  };
  rooms.set(code, room);
  return room;
}

const playerByToken = (room, token) => room.players.find((p) => p.token === token) || null;
const profileOfPlayer = (p) => (p && p.address && profiles[p.address]) || null;
const isHost = (room, p) => !!p && room.players.length > 0 && room.players[0].token === p.token;

/* ── What one device is allowed to know ──────────────────────────── */
function viewFor(room, player) {
  const base = {
    code: room.code,
    you: player ? player.seat : null,
    host: isHost(room, player),
    players: room.players.map((p) => ({
      name: p.name, ai: p.ai || null, seat: p.seat, online: p.online !== false,
    })),
    games: Object.values(GAMES)
      .filter((g) => !g.solo)
      .map((g) => ({ id: g.id, name: g.name, tagline: g.tagline, category: g.category, min: g.min, max: g.max })),
    gameId: room.gameId, difficulty: room.difficulty,
    me: player ? summarise(profileOfPlayer(player)) : null,
    phase: room.run ? (room.run.state.done ? "over" : "playing") : "lobby",
    log: room.log.slice(-6),
  };
  if (!room.run) return base;

  const run = room.run, g = run.g, st = run.state;
  const seat = player && player.seat !== null && player.seat !== undefined ? player.seat : null;
  /* Everything below is built through the same redaction the local game
     uses. A card this seat may not see is not in this payload at all. */
  return Object.assign(base, {
    names: st.names,
    seats: st.seats,
    active: st.active === undefined ? null : st.active,
    table: tableFor(g, st, seat),
    hand: seat === null ? [] : B.at(st.board, Z.hand(seat)).map((id) => B.visible(st.board, id, seat)),
    legal: seat === null || st.active !== seat || run.busy ? [] : g.legal(st, seat),
    done: st.done ? { winners: st.done.winners, scores: st.done.scores, lowWins: !!st.done.lowWins } : null,
    gameName: g.name,
  });
}

/* Everything a person is entitled to know about themselves. */
function summarise(p) {
  if (!p) return null;
  const today = Daily.today();
  return {
    name: p.name, address: p.address, played: p.played, won: p.won, lost: p.lost,
    seconds: p.seconds, byGame: p.byGame, wonGames: p.wonGames,
    streak: p.streak, bestStreak: p.bestStreak, dailyDone: p.dailyDone,
    dailyToday: p.dailyHistory.includes(today), bosses: p.bosses,
    unlocked: p.unlocked,
    achievements: ACHIEVEMENTS.map((a) => ({ id: a.id, t: a.t, d: a.d, target: a.target, at: Math.min(a.target, a.of(p)) })),
    mastery: Object.keys(GAMES).map((id) => ({ id, name: GAMES[id].name, ...mastery(p, id) })),
  };
}

function broadcast(room) {
  for (const client of room.clients) {
    if (client.res.writableEnded) { room.clients.delete(client); continue; }
    const payload = JSON.stringify(viewFor(room, playerByToken(room, client.token)));
    try { client.res.write(`data: ${payload}\n\n`); } catch { room.clients.delete(client); }
  }
}

function note(room, events) {
  for (const e of events || []) if (e) room.log.push(e);
  if (room.log.length > 60) room.log.splice(0, room.log.length - 60);
}

/* ── Running the table ───────────────────────────────────────────── */
function startGame(room, gameId, difficulty) {
  const g = GAMES[gameId];
  if (!g) return "There is no such game.";
  const n = room.players.length;
  if (n < g.min) return `${g.name} needs at least ${g.min} players — there are ${n}.`;
  if (n > g.max) return `${g.name} seats at most ${g.max} — there are ${n}.`;

  room.players.forEach((p, i) => { p.seat = i; });
  const seed = crypto.randomInt(0x7fffffff);
  const rng = rngFrom(seed);
  const state = g.setup({ seats: room.players.map((p) => ({ name: p.name, ai: p.ai })) }, rng);
  state.names = room.players.map((p) => p.name);
  room.gameId = gameId;
  room.difficulty = difficulty || room.difficulty;
  room.log = [];
  room.run = { g, rng, state, seed, busy: false, steps: 0, started: Date.now(), recorded: false };
  settle(room);
  return null;
}

function aiProfileFor(room, seat) {
  const p = room.players[seat];
  const base = CAST.find((c) => c.id === p.ai) || CAST[0];
  return { ...base, mistake: Math.max(0, base.mistake + (DIFFICULTY[room.difficulty] || 0)) };
}

/* Runs everything that needs no person: automatic scoring and dealing,
   then any AI seat, stopping the moment a human is on the clock. */
function settle(room) {
  const run = room.run;
  if (!run || run.busy) return;
  const { g, state } = run;
  let guard = 0;

  const step = () => {
    if (room.run !== run) return;

    if (state.done && !run.recorded) {
      run.recorded = true;
      const secs = Math.round((Date.now() - (run.started || Date.now())) / 1000);
      for (const p of room.players) {
        const prof = profileOfPlayer(p);
        if (!prof || p.ai) continue;
        const fresh = Profile.record(prof, {
          gameId: g.id, won: state.done.winners.includes(p.seat), seconds: secs,
          score: state.done.scores[p.seat], metrics: metricsFrom(g, state, p.seat),
          difficulty: room.difficulty, daily: room.daily ? room.daily.date : null,
          bossId: room.daily ? room.daily.bossId : null,
        });
        if (fresh.length) note(room, fresh.map((id) => {
          const a = ACHIEVEMENTS.find((x) => x.id === id);
          return `${p.name} earned "${a ? a.t : id}".`;
        }));
      }
      saveProfiles();
    }
    if (state.done || guard++ > 4000) { broadcast(room); return; }

    if (g.auto) {
      const ev = g.auto(state, run.rng);
      if (ev.length) {
        note(room, ev);
        run.busy = true; broadcast(room);
        setTimeout(() => { run.busy = false; step(); }, paced(450));
        return;
      }
    }
    if (state.done) { broadcast(room); return; }

    /* A simultaneous game nominates nobody, so find an opponent who can
       actually move rather than assuming one seat is on the clock. */
    let seat = state.active;
    if (seat === null || seat === undefined) {
      seat = state.seats.find((s) => room.players[s] && room.players[s].ai && g.legal(state, s).length);
      if (seat === undefined) { broadcast(room); return; }
    }
    const player = room.players[seat];
    if (!player || !player.ai) { broadcast(room); return; }

    const legal = g.legal(state, seat);
    if (!legal.length) { broadcast(room); return; }
    const action = g.agent(state, seat, legal, aiProfileFor(room, seat), run.rng.branch(run.steps++)) || legal[0];
    run.busy = true; broadcast(room);
    setTimeout(() => {
      if (room.run !== run) return;
      run.busy = false;
      note(room, g.apply(state, action, run.rng));
      step();
    }, paced(500 + Math.random() * 400));
  };
  step();
}

/* ── HTTP ────────────────────────────────────────────────────────── */
function send(res, code, body, type = "application/json") {
  const data = typeof body === "string" ? body : JSON.stringify(body);
  res.writeHead(code, {
    "Content-Type": type,
    "Cache-Control": "no-store",
    "Content-Length": Buffer.byteLength(data),
  });
  res.end(data);
}
const fail = (res, code, why) => send(res, code, { error: why });

function readBody(req) {
  return new Promise((resolve, reject) => {
    let n = 0; const chunks = [];
    req.on("data", (c) => {
      n += c.length;
      if (n > 64 * 1024) { reject(new Error("too big")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => { try { resolve(JSON.parse(Buffer.concat(chunks).toString() || "{}")); } catch { reject(new Error("bad json")); } });
    req.on("error", reject);
  });
}

function pageHtml() {
  const html = fs.readFileSync(HTML_PATH, "utf8");
  // Tell the page it is being served by a table, so it offers to play
  // with other devices as well as on this one.
  const body = html.replace("<script>\n\"use strict\";", "<script>window.DECK_SERVER = true;</script>\n<script>\n\"use strict\";");
  // index.html is a fragment: it carries no document shell so it can also
  // be published as a hosted page. Serving it to a phone needs one, and
  // the viewport line is the difference between a card table and a
  // 980px-wide postage stamp.
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#F2E9D8" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0E0D0C" media="(prefers-color-scheme: dark)">
<meta name="color-scheme" content="light dark">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="DECK">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
</head>
<body>
${body}
</body>
</html>
`;
}

const ROUTES = {
  async "/api/create"(req, res, body) {
    const name = String(body.name || "Player").slice(0, 24).trim() || "Player";
    const me = profileFor(req, name);
    const room = makeRoom();
    const player = { token: newToken(), name: me.name, seat: 0, ai: null, online: true, address: addressOf(req) };
    room.players.push(player);
    send(res, 200, { code: room.code, token: player.token, seat: 0 });
    broadcast(room);
  },

  async "/api/join"(req, res, body) {
    const code = String(body.code || "").toUpperCase().trim();
    const room = rooms.get(code);
    if (!room) return fail(res, 404, "No table with that code. Check the letters and try again.");
    if (body.token) {
      const existing = playerByToken(room, body.token);
      if (existing) {                                   // rejoining after a reload
        existing.online = true;
        send(res, 200, { code: room.code, token: existing.token, seat: existing.seat });
        broadcast(room);
        return;
      }
    }
    if (room.run) return fail(res, 409, "That game has already started.");
    if (room.players.length >= 8) return fail(res, 409, "That table is full.");
    const name = String(body.name || "Player").slice(0, 24).trim() || "Player";
    const me = profileFor(req, name);
    const player = { token: newToken(), name: me.name, seat: room.players.length, ai: null, online: true, address: addressOf(req) };
    room.players.push(player);
    note(room, [`${me.name} sits down.`]);
    send(res, 200, { code: room.code, token: player.token, seat: player.seat });
    broadcast(room);
  },

  async "/api/seat"(req, res, body) {
    const room = rooms.get(String(body.code || "").toUpperCase());
    if (!room) return fail(res, 404, "No such table.");
    const me = playerByToken(room, body.token);
    if (!isHost(room, me)) return fail(res, 403, "Only the host can change the seats.");
    if (room.run) return fail(res, 409, "The game has already started.");
    if (body.add) {
      if (room.players.length >= 8) return fail(res, 409, "That table is full.");
      const used = new Set(room.players.map((p) => p.ai));
      const pick = CAST.find((c) => !used.has(c.id)) || CAST[0];
      room.players.push({ token: newToken(), name: pick.name, ai: pick.id, seat: room.players.length, online: true });
    } else if (body.remove !== undefined) {
      const i = Number(body.remove);
      if (i > 0 && i < room.players.length && room.players[i].ai) room.players.splice(i, 1);
      room.players.forEach((p, k) => { p.seat = k; });
    }
    send(res, 200, { ok: true });
    broadcast(room);
  },

  async "/api/start"(req, res, body) {
    const room = rooms.get(String(body.code || "").toUpperCase());
    if (!room) return fail(res, 404, "No such table.");
    const me = playerByToken(room, body.token);
    if (!isHost(room, me)) return fail(res, 403, "Only the host can start the game.");
    if (room.run && !room.run.state.done) return fail(res, 409, "That game is already running.");
    const why = startGame(room, body.gameId, body.difficulty);
    if (why) return fail(res, 400, why);
    send(res, 200, { ok: true });
  },

  async "/api/action"(req, res, body) {
    const room = rooms.get(String(body.code || "").toUpperCase());
    if (!room || !room.run) return fail(res, 404, "No game is running.");
    const me = playerByToken(room, body.token);
    if (!me) return fail(res, 403, "You are not at this table.");
    const run = room.run;
    if (run.busy) return fail(res, 409, "Hold on — somebody else is moving.");
    if (run.state.active !== me.seat) return fail(res, 403, "It is not your turn.");

    /* The action is checked against this seat's own legal moves. A client
       cannot invent a move, and cannot play for anybody else. */
    const legal = run.g.legal(run.state, me.seat);
    const wanted = JSON.stringify(body.action);
    const match = legal.find((a) => JSON.stringify(a) === wanted);
    if (!match) return fail(res, 400, "That move is not available.");

    note(room, run.g.apply(run.state, match, run.rng));
    send(res, 200, { ok: true });
    settle(room);
  },

  async "/api/me"(req, res, body) {
    const me = profileFor(req, body.name);
    if (body.rename) { me.name = String(body.rename).slice(0, 24).trim() || me.name; saveProfiles(); }
    send(res, 200, { me: summarise(me), metrics: METRICS, today: Daily.today(), daily: Daily.for(Daily.today()), bosses: BOSSES });
  },

  async "/api/leaderboard"(req, res) {
    const all = Object.values(profiles).map((p) => ({
      name: p.name, address: p.address, played: p.played, won: p.won,
      rate: p.played ? Math.round((p.won / p.played) * 100) : 0,
      games: (p.wonGames || []).length, streak: p.bestStreak || 0,
    })).sort((a, b) => b.won - a.won).slice(0, 30);
    send(res, 200, { players: all, you: addressOf(req) });
  },

  async "/api/leave"(req, res, body) {
    const room = rooms.get(String(body.code || "").toUpperCase());
    if (!room) return fail(res, 404, "No such table.");
    const me = playerByToken(room, body.token);
    if (me) {
      if (room.run) me.online = false;                 // keep the seat mid-game
      else {
        room.players = room.players.filter((p) => p.token !== me.token);
        room.players.forEach((p, i) => { p.seat = i; });
      }
    }
    send(res, 200, { ok: true });
    if (room.players.length === 0) rooms.delete(room.code); else broadcast(room);
  },
};

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
    return send(res, 200, pageHtml(), "text/html; charset=utf-8");
  }

  if (req.method === "GET" && url.pathname === "/api/events") {
    const room = rooms.get(String(url.searchParams.get("code") || "").toUpperCase());
    if (!room) return fail(res, 404, "No such table.");
    const token = url.searchParams.get("token") || "";
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-store",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    const client = { res, token };
    room.clients.add(client);
    const me = playerByToken(room, token);
    if (me) me.online = true;
    res.write(`data: ${JSON.stringify(viewFor(room, me))}\n\n`);
    const beat = setInterval(() => { try { res.write(": beat\n\n"); } catch {} }, 25000);
    req.on("close", () => {
      clearInterval(beat);
      room.clients.delete(client);
      const p = playerByToken(room, token);
      if (p && ![...room.clients].some((c) => c.token === token)) { p.online = false; broadcast(room); }
    });
    return;
  }

  if (req.method === "POST" && ROUTES[url.pathname]) {
    let body;
    try { body = await readBody(req); } catch (e) { return fail(res, 400, "That request did not make sense."); }
    try { return await ROUTES[url.pathname](req, res, body); }
    catch (e) { console.error(e); return fail(res, 500, "The table hit a problem."); }
  }

  fail(res, 404, "Not found.");
});

/* ── Boot ────────────────────────────────────────────────────────── */
function addresses(port) {
  const out = [];
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const net of ifaces[name] || []) {
      if (net.family !== "IPv4" || net.internal) continue;
      const tailscale = net.address.startsWith("100.") || name.startsWith("tailscale");
      out.push({ name, address: net.address, tailscale });
    }
  }
  out.sort((a, b) => Number(b.tailscale) - Number(a.tailscale));
  return out.map((a) => ({ ...a, url: `http://${a.address}:${port}` }));
}

if (require.main === module) {
  const argPort = process.argv.indexOf("--port");
  const port = Number(argPort > -1 ? process.argv[argPort + 1] : process.env.PORT || 4173);
  server.listen(port, "0.0.0.0", () => {
    const found = addresses(port);
    const tail = found.filter((a) => a.tailscale);
    console.log("");
    console.log("  DECK — the table is open.");
    console.log("");
    console.log(`  On this machine    http://localhost:${port}`);
    for (const a of found.filter((x) => !x.tailscale)) console.log(`  On this network    ${a.url}   (${a.name})`);
    if (tail.length) {
      for (const a of tail) console.log(`  On your tailnet    ${a.url}   (${a.name})`);
      console.log("");
      console.log("  Everybody on the tailnet opens that address and joins with the code.");
    } else {
      console.log("");
      console.log("  No Tailscale address found. Start Tailscale and restart this,");
      console.log("  or use the network address above if you are all on one wifi.");
    }
    console.log("");
  });
}

module.exports = { server, rooms, makeRoom, startGame, viewFor, loadEngine, addresses, GAMES, B, Z, flushProfiles, PROFILES };
