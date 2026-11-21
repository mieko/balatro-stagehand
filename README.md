# Balatro Stagehand

Control Balatro through Stagehand for automated tests, bots, agents and
interactive debugging. The Lua mod uses the game's own controls to start runs,
play hands, shop and open packs. The JavaScript client lets you take a turn from
a REPL, or watch someone else's run without sending input.

**The default listener is open to local programs.** Developer Mode adds arbitrary
Lua execution and other debugging services. Only enable it for trusted clients.
See [security](docs/security.md).

## Install

1. Install [Lovely](https://github.com/ethangreen-dev/lovely-injector#manual-installation)
   for your platform.
2. Download a `BalatroStagehand-<version>.zip` from
   [Releases](https://github.com/mieko/balatro-stagehand/releases). Extract its
   `BalatroStagehand` folder into Lovely's `Mods` directory.
3. Launch Balatro as usual for Lovely mods. Stagehand listens at
   `http://localhost:27121`; no token, environment variables or custom launcher are required.

Node is needed for the JavaScript client and development tools, not to load the
mod. [Installation and configuration](docs/install.md) covers platform paths,
network access and the optional isolated development launcher.

## Play from JavaScript

**Options → Stagehand** shows the game's address. Fetch the address to read the
Markdown index of the matching client and docs. With the game running, download
the client and open a Node.js 22+ REPL:

```sh
curl -fsS http://localhost:27121/client.mjs -o balatro-stagehand.mjs
node
```

```js
const { connectBalatro } = await import('./balatro-stagehand.mjs');
const game = await connectBalatro();
console.log(game.present(await game.decision()));
```

The installed mod folder also contains the same `client.mjs` and the docs.
See the [Stagehand API](docs/api.md) for generic JavaScript and wire-level access.

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

- [Gameplay API](docs/game.md) covers card order, targeting, purchases and run settings.
- [Spectator mode](docs/game.md#passive-observation) watches settled positions from a second connection. To slow a driver's inputs, call `game.setHumanDelay(400)`. The default is zero.
- [Native tree inspection](docs/game.md#native-tree-fallback) finds UI controls. [Runtime Lua](docs/game.md#runtime-lua) evaluates a script against live game objects.
- [Limits](docs/game.md#limits) lists the tested game features and platform scope.

## Development

Clone with `--recurse-submodules` and run `npm ci` for source development.
`npm run format` and `npm run format:check` use pinned StyLua and Prettier.
`npm run build:mod` creates a folder and `BalatroStagehand-<version>.zip` under
`.local/dist/`, using the `package.json` version for Lua and mod metadata too. Use
`npm version <version> --no-git-tag-version` to update the version and lockfile.
Pushing the matching `v<version>` tag builds and publishes the ZIP as a GitHub Release.
`npm run update:manifest` refreshes module declarations after adding Lua files.

`npm test` runs JS and Lua fixtures (requires `lua` on PATH).
`npm run test:setup` checks installation tools without launching the game.
`npm run test:runtime` uses temporary headless LÖVE fixtures; see
[development setup](docs/install.md#development) and [dependency provenance](mod/vendor/README.md).

Licensed under [MIT](LICENSE). Third-party notices remain with their sources.
