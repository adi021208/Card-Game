# Playing on more than one device

DECK plays two ways, and the same rules run both:

- **On one device** — pass a phone round the table. The game seals itself
  between players. This works anywhere, including the published web page,
  with nothing to install.
- **On several devices** — one machine hosts the table, everybody else
  plays from their own phone over your tailnet. Nothing is deployed
  anywhere and nothing costs anything.

## Start a table

On the machine that will host — a laptop, a desktop, a Raspberry Pi:

```
git clone https://github.com/adi021208/Card-Game.git
cd Card-Game
node web/server.js
```

No install step, no dependencies. It prints where to go:

```
  DECK — the table is open.

  On this machine    http://localhost:4173
  On your tailnet    http://100.92.14.7:4173   (tailscale0)

  Everybody on the tailnet opens that address and joins with the code.
```

Pick a different port with `--port 8080` or `PORT=8080`.

## Get everyone on the tailnet

[Tailscale](https://tailscale.com) puts your devices on a private network
wherever they are — same room, or different countries. The free tier covers
far more devices than a card table needs.

1. Install Tailscale on the host machine and on each phone.
2. Sign everybody into the **same tailnet** — either one account, or invite
   the others as users on yours.
3. Start the server on the host.
4. Everybody opens the printed `100.x.y.z` address in their browser.

With MagicDNS on you can use the machine's name instead of its number:
`http://your-laptop:4173`.

Tailscale is doing two useful things here. It gets through NAT, so nobody
has to forward a port or expose anything to the internet. And it encrypts
the traffic between devices, so the plain HTTP the server speaks is only
ever plain inside your own network.

**On one wifi and don't want Tailscale?** Use the `On this network`
address instead. It works the same; it just won't reach anybody who isn't
in the building.

## On an iPhone

Open the address in Safari, then **Share → Add to Home Screen**. It gets
its own icon and opens without the browser bars, which is worth the twenty
seconds: a card table wants the whole screen.

The page is built for a phone held either way. Cards size themselves to
the screen you are on — Spider's ten columns fit an iPhone SE, and turning
the phone sideways makes them bigger rather than wider. It does not bounce,
zoom on a double tap, or wait to find out whether you meant to tap twice,
and it keeps its content clear of the notch and the home indicator.

## Playing

One person taps **Play with friends** → **Start a table** and reads out the
four-letter code. Everybody else taps **Play with friends**, types the code
and their name, and sits down.

The host can add computer opponents to fill the table, then picks the game.
Games appear greyed out until the number of players suits them — Hearts
wants exactly four, Cheat wants at least three.

Twelve games work on several devices. The three solitaires only
appear in the single-device library.

Reloading puts you back in your seat: the browser keeps a token, and the
server keeps the seat. If somebody's phone dies mid-game their seat stays,
marked away, and picks up where it left off when they come back.

## Who you are

There are no accounts. The server knows you by your device's address, and
on a tailnet that is exactly the right key: Tailscale hands each device a
stable `100.x` address that follows it between networks, so your record
finds you with nothing to sign into. Change your name whenever you like —
the address is the identity, the name is a label.

Your statistics, achievements, mastery bands, daily streak and which of
the seven you have beaten are all kept against that address, in
`web/.profiles.json` next to the server. They survive restarts, and are
written through a temporary file and renamed so a crash cannot corrupt
them.

**This only works on a private network.** Two people behind one home
router share an address, so they would share a record. That is fine on a
tailnet, where every device has its own; it would be wrong on the open
internet, and is another reason not to put this there.

## Why this is the private way to do it

The host machine holds the only complete game state. Every device is sent
its own view and nothing else — a card you are not entitled to see is never
serialised, so it never crosses the network and never arrives in your
opponent's browser. Opening the developer tools on a rival's phone shows
their own hand and the cards already on the table, and nothing more.

That is a stronger guarantee than passing one device round, where the whole
game is on the device the whole time and the privacy comes from the app
refusing to draw it.

The server also checks every move against the rules for the seat that sent
it. A client cannot play out of turn, play for somebody else, or invent a
move; the request is matched against that seat's own legal moves and
refused if it is not among them.

`web/test-net.js` asserts all of this against the running server: it walks
every payload the server would send and fails if any names a card the
recipient may not see.

## What it does not do

- **No matchmaking, no accounts, no cloud.** A table exists in the host's
  memory. Stop the server and the table is gone.
- **No play over the open internet** unless you put it there deliberately.
  The server binds to all interfaces so Tailscale can reach it; if the
  machine is also on a public IP, that port is reachable from the public
  internet. Firewall it, or bind to the Tailscale address, if that matters
  to you.
- **No spectators.** Every connected device holds a seat.

## Running the tests

```
node web/test.js       # the engine: rules, determinism, privacy, full games
node web/test-ui.js    # the interface: every screen, driven by clicking
node web/test-net.js   # the table: real HTTP, real event streams, three devices
```

All three run in CI on every push.
