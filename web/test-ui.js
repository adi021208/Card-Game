/*
 * DECK — UI smoke tests for the web build.
 *
 * The engine tests never load the render layer, so a screen that throws on
 * open looked green. This drives the real UI through a minimal DOM: it
 * opens every game from the library, walks the setup screen, deals, and
 * plays turns by clicking what the page actually offers.
 *
 * It also checks the thing that matters most on a shared device — that the
 * page never puts a rank or a suit on screen for a card the current viewer
 * is not entitled to see.
 *
 *   node web/test-ui.js
 */
"use strict";
const fs = require("fs"), path = require("path");

/* ── A DOM small enough to read, big enough to run the page ────────── */
const timers = [];
function makeNode(tag) {
  const n = {
    tagName: String(tag).toUpperCase(), children: [], parentNode: null,
    style: new Proxy({}, { get: (t, k) => t[k] || "", set: (t, k, v) => (t[k] = v, true) }),
    dataset: {}, attrs: {}, _text: "", disabled: false, value: "", tabIndex: 0,
    classList: {
      _s: new Set(),
      add(...c) { c.forEach((x) => x && this._s.add(x)); },
      remove(...c) { c.forEach((x) => this._s.delete(x)); },
      contains(c) { return this._s.has(c); },
      toggle(c, on) { on === undefined ? (this._s.has(c) ? this._s.delete(c) : this._s.add(c)) : (on ? this._s.add(c) : this._s.delete(c)); },
    },
    get className() { return [...this.classList._s].join(" "); },
    set className(v) { this.classList._s = new Set(String(v).split(/\s+/).filter(Boolean)); },
    get textContent() { return this._text || this.children.map((c) => c.textContent).join(""); },
    set textContent(v) { this._text = String(v); this.children = []; },
    set innerHTML(v) { if (!v) this.children = []; this._text = String(v).replace(/<[^>]*>/g, " "); },
    get innerHTML() { return this._text; },
    append(...ns) { for (const c of ns) { if (!c) continue; c.parentNode = this; this.children.push(c); } },
    prepend(...ns) { for (const c of ns.reverse()) { if (!c) continue; c.parentNode = this; this.children.unshift(c); } },
    appendChild(c) { this.append(c); return c; },
    remove() { const p = this.parentNode; if (p) p.children = p.children.filter((x) => x !== this); },
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; },
    removeAttribute(k) { delete this.attrs[k]; },
    getBoundingClientRect() { return { width: 390, height: 700, top: 0, left: 0 }; },
    getContext() { return canvasCtx; },
    focus() {},
    addEventListener() {},
    querySelectorAll(sel) { return all(this).filter((n) => matches(n, sel)); },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
  };
  return n;
}
const canvasCtx = new Proxy({}, { get: () => () => {} });
function all(n, out = []) { for (const c of n.children) { out.push(c); all(c, out); } return out; }
function matches(n, sel) {
  return sel.split(",").map((s) => s.trim()).some((s) =>
    s.startsWith(".") ? n.classList.contains(s.slice(1)) : n.tagName === s.toUpperCase());
}

const root = makeNode("html");
const body = makeNode("body");
const byId = {};
for (const id of ["screen", "themeBtn", "quitBtn", "statsBtn"]) { byId[id] = makeNode("div"); byId[id].attrs.id = id; body.append(byId[id]); }

global.document = {
  documentElement: root, body,
  createElement: makeNode,
  getElementById: (id) => byId[id] || null,
  querySelectorAll: (sel) => all(body).filter((n) => matches(n, sel)),
  querySelector: (sel) => global.document.querySelectorAll(sel)[0] || null,
  addEventListener() {}, visibilityState: "visible",
};
global.window = { innerWidth: 390, innerHeight: 780, devicePixelRatio: 2, addEventListener() {} };
global.getComputedStyle = () => ({ getPropertyValue: () => "#E33A21" });
global.localStorage = { _d: {}, getItem(k) { return k in this._d ? this._d[k] : null; }, setItem(k, v) { this._d[k] = String(v); } };
global.ResizeObserver = class { observe() {} };
global.requestAnimationFrame = (fn) => { timers.push(fn); return 0; };
global.setTimeout = (fn) => { timers.push(fn); return timers.length; };
global.confirm = () => true;
global.fetch = () => Promise.resolve({ ok: true, json: () => Promise.resolve({ players: [], you: "" }) });
global.EventSource = class { constructor() {} close() {} };
const drain = (max = 3000) => { let n = 0; while (timers.length && n++ < max) timers.shift()(); };

/* ── Load the page's script ────────────────────────────────────────── */
const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const src = html.slice(html.indexOf("<script>\n") + 9, html.lastIndexOf("</script>"));
const api = {};
new Function("__out", src + "\n__out.App = App; __out.GAMES = GAMES; __out.B = B; __out.Z = Z; __out.Privacy = Privacy; __out.render = render;")(api);
const { GAMES, B, Z, Privacy } = api;

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log("  FAIL:", m); } };

const buttons = () => all(body).filter((n) => n.tagName === "BUTTON" && !n.disabled);
const byText = (t) => buttons().find((b) => b.textContent.trim().toLowerCase() === t.toLowerCase());
const click = (n) => { if (n && n.onclick) { n.onclick(); drain(); return true; } return false; };
const screenText = () => byId.screen.textContent;

/* Nothing on screen may name a card the current viewer cannot see. */
function assertNoLeak(label) {
  const run = api.App.run;
  if (!run) return;
  const viewer = Privacy.viewer(run.privacy);
  const shown = new Set(all(body).filter((n) => n.classList.contains("card"))
    .map((n) => n.getAttribute("aria-label")).filter((x) => x && x !== "Face-down card"));
  for (const seat of run.state.seats) {
    if (seat === viewer) continue;
    for (const id of B.at(run.state.board, Z.hand(seat))) {
      const c = run.state.board.cards.get(id);
      if (!c) continue;
      const name = `${["","","Two","Three","Four","Five","Six","Seven","Eight","Nine","Ten","Jack","Queen","King","Ace"][c.rank]} of ${{C:"Clubs",D:"Diamonds",H:"Hearts",S:"Spades"}[c.suit]}`;
      if (shown.has(name) && !B.canSee(run.state.board, id, viewer)) {
        ok(false, `${label} — the page showed ${name}, which seat ${viewer} may not see`);
        return;
      }
    }
  }
  pass++;
}

/* ── The library opens ─────────────────────────────────────────────── */
api.render(); drain();
ok(screenText().includes("One deck"), "library renders");
function shelfTiles() {
  const anchor = all(byId.screen).find((n) => n.getAttribute("id") === "shelfAnchor");
  return anchor ? all(anchor).filter((n) => n.classList.contains("game-card")) : [];
}
ok(shelfTiles().length === Object.keys(GAMES).length,
   `library lists all ${Object.keys(GAMES).length} games — found ${shelfTiles().length}`);

/* ── Every game opens its setup screen and deals ───────────────────── */
for (const id of Object.keys(GAMES)) {
  const g = GAMES[id];
  api.App.run = null; api.App.game = null; api.App.view = "library";
  api.render(); drain();

  const tile = shelfTiles().find((n) => n.textContent.includes(g.name));
  ok(!!tile, `${id}: has a tile in the library`);
  if (!tile) continue;

  let threw = null;
  try { click(tile); } catch (e) { threw = e; }
  ok(!threw, `${id}: opening setup did not throw — ${threw && threw.message}`);
  if (threw) continue;

  ok(api.App.view === "setup", `${id}: went to the setup screen`);
  ok(screenText().includes(g.name), `${id}: setup names the game`);
  const seatRows = all(byId.screen).filter((n) => n.classList.contains("seat-row"));
  ok(seatRows.length >= g.min && seatRows.length <= g.max,
     `${id}: setup offers ${g.min}–${g.max} seats — showed ${seatRows.length}`);
  ok(/Pass & Play|Solo|opponent/i.test(screenText()), `${id}: setup says who is playing`);

  if (!g.solo) {
    const add = byText("Add player");
    if (seatRows.length < g.max) {
      ok(!!add, `${id}: can add a player below the maximum`);
      try { click(add); } catch (e) { ok(false, `${id}: adding a player threw — ${e.message}`); }
    }
    // Turn a seat into a second person, so Pass & Play is exercised.
    const swap = all(byId.screen).filter((n) => n.tagName === "BUTTON" && n.title === "Make this a person")[0];
    if (swap) { try { click(swap); } catch (e) { ok(false, `${id}: switching a seat threw — ${e.message}`); } }
  }

  let dealt = null;
  try { dealt = click(byText("Deal")); } catch (e) { ok(false, `${id}: dealing threw — ${e.message}`); continue; }
  ok(dealt, `${id}: the Deal button worked`);
  ok(!!api.App.run, `${id}: a game is running`);
  assertNoLeak(`${id} at the deal`);

  /* Play by clicking whatever the page offers, the way a person would. */
  let steps = 0, idle = 0;
  while (api.App.run && !api.App.run.state.done && steps < 260 && idle < 6) {
    drain();
    let acted = false;
    const seal = document.querySelectorAll(".seal")[0];
    if (seal) {
      const confirmBtn = all(seal).find((n) => n.tagName === "BUTTON" && n.onclick);
      try { acted = click(confirmBtn); } catch (e) { ok(false, `${id}: the handoff button threw — ${e.message}`); break; }
      assertNoLeak(`${id} just after a handoff`);
    } else {
      const live = buttons().filter((b) => b.onclick && b !== byId.themeBtn && b !== byId.quitBtn);
      const cards = live.filter((b) => b.classList.contains("card"));
      const target = cards.length ? cards[cards.length - 1] : live.find((b) => b.classList.contains("btn"));
      try { acted = click(target); } catch (e) { ok(false, `${id}: clicking ${target && target.textContent} threw — ${e.message}`); break; }
    }
    if (!acted) idle++; else { idle = 0; assertNoLeak(`${id} mid-game`); }
    steps++;
  }
  ok(steps > 0, `${id}: the table accepted at least one interaction`);
  ok(screenText().length > 0, `${id}: the screen is never blank`);
}

/* ── A solitaire must put every one of its columns on the screen ────
 * Spider deals ten columns and FreeCell eight. A renderer that assumes
 * Klondike's seven drops the rest without any error, and the game simply
 * cannot be won. Count what reaches the DOM against what the board holds.
 */
for (const id of ["klondike", "freecell", "spider"]) {
  api.App.run = null; api.App.game = null; api.App.view = "library";
  api.render(); drain();
  const tile = shelfTiles().find((n) => n.textContent.includes(GAMES[id].name));
  click(tile); click(byText("Deal")); drain();

  const run = api.App.run;
  ok(!!run, `${id}: dealt`);
  if (!run) continue;

  const t = GAMES[id].table(run.state, null);
  const nCols = t.columns || 7;
  let inPlay = 0;
  for (let c = 0; c < nCols; c++) inPlay += B.at(run.state.board, Z.tableau(c)).length;
  ok(inPlay > 0, `${id}: the board deals into ${nCols} columns`);
  for (const z of t.zones) inPlay += z.cards.length;

  const felt = all(body).find((n) => n.classList.contains("felt") && n.classList.contains("tableau"));
  ok(!!felt, `${id}: the tableau felt is on screen`);
  const drawn = felt ? all(felt).filter((n) => n.classList.contains("card")).length : 0;
  ok(drawn === inPlay,
     `${id}: every card in play is drawn — board holds ${inPlay}, screen shows ${drawn}`);

  // And an empty column still has to be a target you can drop onto.
  let empties = 0;
  for (let c = 0; c < nCols; c++) if (!B.at(run.state.board, Z.tableau(c)).length) empties++;
  const slots = felt ? all(felt).filter((n) => n.classList.contains("pile") && n.classList.contains("empty")) : [];
  ok(slots.length >= empties, `${id}: empty columns get a slot to drop onto`);
}
api.App.run = null; api.App.game = null; api.App.view = "library"; api.render(); drain();

/* ── The screens that show what you have done ──────────────────────── */
{
  api.App.run = null; api.App.game = null; api.App.remote = null;
  for (const view of ["stats", "daily", "library"]) {
    api.App.view = view;
    let threw = null;
    try { api.render(); drain(); } catch (e) { threw = e; }
    ok(!threw, `the ${view} screen opens — ${threw && threw.message}`);
    ok(screenText().length > 20, `the ${view} screen has content`);
  }
  api.App.view = "stats"; api.render(); drain();
  const txt = screenText();
  ok(/Achievements/i.test(txt), "the record lists achievements");
  ok(/seven/i.test(txt), "and the seven");
  ok(/Win rate/i.test(txt), "and a win rate");
  api.App.view = "daily"; api.render(); drain();
  ok(/Daily challenge/i.test(screenText()), "the daily names itself");
  ok(/Objective|Difficulty/i.test(screenText()), "and says what it wants");
  api.App.view = "library"; api.render(); drain();
}

/* ── The error boundary catches a thrown view instead of blanking ──── */
{
  const realTable = GAMES.hearts.table;
  const realError = console.error;
  console.error = () => {};                      // the throw below is on purpose
  GAMES.hearts.table = () => { throw new Error("deliberate"); };
  api.App.view = "library"; api.App.run = null; api.App.game = GAMES.hearts;
  api.App.view = "setup";
  try {
    api.render(); drain();
    click(byText("Deal")); drain();
    ok(screenText().length > 0, "a throwing view shows a message, not a blank screen");
    ok(/did not open|deliberate/i.test(screenText()), "and the message says what happened");
  } catch (e) { ok(false, "the error boundary let an exception escape — " + e.message); }
  GAMES.hearts.table = realTable;
  console.error = realError;
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
