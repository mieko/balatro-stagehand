# Balatro Stagehand

Control Balatro over a JSON WebSocket for automated tests, bots, agents and
interactive debugging. The Lua mod uses the game's own controls to start runs,
play hands, shop and open packs. The JavaScript client lets you take a turn from
a REPL, or watch someone else's run without sending input.

**The default developer endpoints let any authenticated client run arbitrary
code in the Balatro process.** The gameplay API shows player-visible
information. The Lua console can inspect and change game internals. See
[security](docs/security.md) before connecting a client.

## Install and launch

The included tools target vanilla Balatro `1.0.1o` (LÖVE 11.5) on Apple Silicon
macOS. Install Node.js 22+, Python 3 and the Steam version of Balatro. The
preparation script reads the app at
`~/Library/Application Support/Steam/steamapps/common/Balatro/Balatro.app`.

```sh
git clone --recurse-submodules https://github.com/mieko/balatro-stagehand.git
cd balatro-stagehand
npm ci
python3 tools/fetch-lovely.py
npm run prepare:game
npm run launch
```

These commands download and verify the pinned Lovely injector, prepare
`.local/Balatro.app` and launch the copy with Steam disabled. It has its own
`stagehand-balatro` save identity. A fresh profile starts windowed and muted.
The launcher records its connection details in the private `.local/session.json`.

Use `npm run launch` for subsequent sessions. After changing the mod, quit the
isolated game, run `npm run prepare:game` and launch again. The profile retains
runs, unlocks and saved settings. Call `game.info()` to find its save directory.

## Play from JavaScript

Start `node` in the checkout with the isolated game running:

```js
const { connectLocal } = await import('./client/local.mjs');
const game = await connectLocal();
console.log(game.present(await game.decision()));
```

At the menu, `runOptions()` lists unlocked decks, stakes, challenges and whether
there is a saved run. Call `startRun()` for a new run or `continueRun()` to load
the native checkpoint. Replacing a saved run requires `startRun({replace: true})`.

At blind selection, call `selectBlind()`. At a hand decision, play cards from
the current observation. For example, to play the first two cards:

```js
const state = await game.state();
const result = await game.playHand([state.hand[0], state.hand[1]]);
console.log(game.present(result));
```

Commands wait for the next decision. Tutorial dialogue, unlock notices and
cash-out require an explicit choice by default. Use `state()` for a passive read.
If a command times out, use `recover()` and inspect the resulting position before
sending more input.

- [Gameplay API](docs/api.md) covers card order, targeting, purchases and run settings.
- [Spectator mode](docs/api.md#passive-observation) watches settled positions from a second connection. To slow a driver's inputs, call `game.setHumanDelay(400)`. The default is zero.
- [Native tree inspection](docs/api.md#native-tree-fallback) finds UI controls. [Runtime Lua](docs/api.md#runtime-lua) evaluates a script against live game objects.
- [Limits](docs/api.md#limits) lists the tested game features and platform scope.

## Development

`npm ci` installs the pinned StyLua and Prettier formatters. Run
`npm run setup:format` once for the project-local Python formatter, then use
`npm run format` and `npm run format:check`.

`npm test` runs JS, Lua and Python fixtures and requires `lua` on PATH.
`npm run test:runtime` uses Balatro's bundled LÖVE in temporary headless fixtures.
The native-model fixture reads selected Lua from the installed game archive to
check eligibility and action routing. It uses temporary files and leaves player
saves alone. See [dependency provenance](mod/vendor/README.md).
