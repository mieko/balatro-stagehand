# Balatro Stagehand

A Lua mod and JavaScript client for playing Balatro through native controls over
Stagehand's WebSocket protocol. It covers run setup, blinds, hands, shops, packs,
consumables and win/loss/endless decisions using player-visible information.

Targets vanilla Balatro `1.0.1o` / LÖVE 11.5 on Apple Silicon macOS. See the
[API guide](docs/api.md) for methods, recovery and [current limits](docs/api.md#limits).

## Install and launch

Requires Node 22+, Python 3 and Steam's Mac Balatro installation at
`~/Library/Application Support/Steam/steamapps/common/Balatro/Balatro.app`.
From the root of your clone:

```sh
git submodule update --init --recursive
npm ci
python3 tools/fetch-lovely.py
npm run prepare:game
npm run launch
```

This downloads pinned Lovely into `.local/deps/` and prepares a separate
`.local/Balatro.app`. The launcher disables Steam integration and uses the
`stagehand-balatro` save identity with an authenticated loopback listener. Fresh
profiles default to windowed and muted; saved window/audio preferences take precedence. Preparation checks that the original game archive is unchanged.
The normal Steam installation, saves and Steam Cloud are not used for play.

For later launches, use `npm run launch`. After mod edits, quit the isolated game
normally, run `npm run prepare:game`, then launch again. Keep its separate profile
to retain runs and unlocks; `info()` reports the save directory. Downloaded tools,
copied source, sessions and logs stay in ignored `.local/`.

## Play from JavaScript

In a persistent JavaScript REPL, replace the import path with your clone's path.
Import and connect once, then retain `game` between calls:

```js
var { connectLocal } = await import('/absolute/path/to/balatro-stagehand/client/local.mjs');
var game = await connectLocal();
console.log(game.present(await game.decision()));
```

For watchable automation, `game.setHumanDelay(400)` enables a pause before native
activations; the default is zero, as in StS2. Cash-out stays visible for at least
that interval. This is separate from native playback speed and passive observation.
To watch someone else's play, use a separate connection's
[`spectate()`](docs/api.md#passive-observation); it never drives the game.

Read the current decision before acting. `state()` is passive; `decision()` waits
for a usable boundary. Autoskip defaults to **off**: tutorial dialogue and earned
unlock notices remain explicit choices through `choose(observedChoice)`. Opting in
advances tutorial dialogue and acknowledges unlock notices, preserving their facts
in the command result.

At the menu, `runOptions()` lists unlocked decks/stakes/challenges and whether a
save is available. Choose **one** operation:

```js
// New default run when no active saved run needs replacing:
console.log(game.present(await game.startRun()));
```

Use `continueRun()` instead to load the native checkpoint. Only when you intend
to replace the saved run, call `startRun({replace: true})`.

At blind selection, call `selectBlind()`; at a hand decision, select observed
cards deliberately:

```js
var state = await game.state();
console.log(game.present(await game.playHand([state.hand[0], state.hand[1]])));
```

Commands wait for resolution or a real choice. Inspect each result before the
next action. Cash-out is explicit: using or selling cards before `cashOut()` can
change the next shop. Never automatically replay a timed-out or disconnected
action; follow [recovery](docs/api.md#settings-and-recovery).

For the native maximum playback speed (4× in this build):

```js
await game.setOptions({ gameSpeed: 'fastest' });
```

`present(result)` is a pure compact view; the original rich result remains
available. Descriptions come from native tooltips/localization, not a separate
effect catalog or scoring predictor. Visible cards are identified normally even
on a fresh save; face-down cards remain hidden. See the [API guide](docs/api.md) for card
ordering, purchases, targeting, inspection and optional tutorial autoskip.

`BalatroSceneTree` provides a native UI-tree fallback for controls without a
semantic binding; see [tree inspection](docs/api.md#native-tree-fallback).
For trusted debugging, [`LoveScript`](docs/api.md#runtime-lua) evaluates Lua inside
the game, with access to its globals and native libraries.

## Development

`npm ci` installs pinned StyLua and Prettier. Set up the project-local Python
formatter once, then use the shared format and check commands:

```sh
npm run setup:format
npm run format
npm run format:check
npm test
npm run test:runtime
```

`npm test` requires `lua` on PATH and runs Lua/JS behavior fixtures and Python setup checks
without launching a game. Runtime tests use Balatro's bundled LÖVE in temporary
headless fixtures. The native-model fixture copies selected proprietary Lua from
the installed archive into its temporary app; it tests eligibility/routing, not
every effect animation. Tests do not start a player game or access player saves.
Proprietary source is never distributed. See [dependency provenance](mod/vendor/README.md).
