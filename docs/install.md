# Installation

Install [Lovely](https://github.com/ethangreen-dev/lovely-injector#manual-installation),
then extract the `BalatroStagehand` folder from the release ZIP into its `Mods`
directory, so the mod is at `Mods/BalatroStagehand/lovely.toml`. Steamodded is optional;
when installed, it lists the mod as **Balatro Stagehand**.

Typical Lovely mod locations:

| Platform     | Mods directory                               |
| ------------ | -------------------------------------------- |
| Windows      | `%AppData%/Balatro/Mods`                     |
| macOS        | `~/Library/Application Support/Balatro/Mods` |
| Native Linux | `~/.local/share/love/Mods`                   |

For Proton, Steam Deck and Flatpak, follow Lovely's platform instructions for the
correct prefix. Windows launches through Steam; macOS and native Linux use
Lovely's loader script. Restart Balatro after installing or updating the mod.
Remove its folder to uninstall.

The normal installation uses your normal game profile. The optional development
setup below keeps a separate profile. Runtime testing is on Apple Silicon macOS;
Windows, Intel macOS and Linux setup paths have fixture coverage.

## Configuration

By default Stagehand accepts **`http://localhost:27121` without a token**, binding
`127.0.0.1` and `::1` when available. Connected clients can control the game;
Developer Mode adds arbitrary Lua execution. See [security](security.md).

Open **Stagehand** in **Options**, or the mod's **Config** tab in Steamodded.
Settings save and apply on **Back** or dismissal. **Copy Connection Details** also
applies pending changes before copying. Reconfiguration disconnects existing clients.
Developer Mode defaults off.

**Allow Remote Connections** switches between loopback and all network interfaces
and enables **Require Access Token**.
**Require Access Token** enables authentication. When the listener requires a token,
the panel offers **Copy Access Token**. A nonempty `STAGEHAND_TOKEN` supplies the token
and enables authentication by default for that launch. An explicit saved
`requireToken` setting takes precedence. Without a supplied token, Stagehand generates
one when it first starts an authenticated listener for that game launch.

**Copy Connection Details** copies a URL you can paste directly when no token is
required. With authentication enabled, it copies the address and token together
for use by a client or agent. The base address serves a Markdown index of the
JavaScript client and API references. It uses `localhost` for the default listener
and a literal loopback address for wildcard listeners. Substitute the game machine's
network address when connecting remotely.

For a custom port or listen address, edit `stagehand.json` in Balatro's LÖVE save
directory and restart the game. The save directory is `%AppData%/Balatro` on
Windows or `~/Library/Application Support/Balatro` on macOS. `game.info()` reports `save_directory`. For example:

```json
{
  "host": "::1",
  "port": 30000,
  "requireToken": true
}
```

The default port is 27121. `*` listens on IPv4 and IPv6 when available;
`0.0.0.0` selects all IPv4 interfaces, `::` all IPv6 interfaces. A specific IP also
works. Non-loopback addresses require `requireToken: true`. `localhost` binds all
available loopback families. `127.0.0.1` and `::1` each select one. Other saved
switches are `enabled` and `developerMode`.

Connect with the token when required:

```js
const game = await connectBalatro({ url: 'http://192.168.1.10:27121', token: 'copied-token' });
// IPv6 URLs use brackets: http://[::1]:27121
```

A bad configuration or occupied port leaves Balatro running and shows the error
in the panel. Once the port is available, choose **Retry Stagehand**. If the port
must change or the configuration file is invalid, correct `stagehand.json` and
restart Balatro. If a setting saves successfully and the listener cannot start,
the panel reports both outcomes. An unsuccessful save offers **Retry Save**, and
you can go Back to discard those edits. `STAGEHAND_HOST` and `STAGEHAND_PORT`
override the file at startup. In-game edits save only the settings you change.

## Development

The isolated launcher is optional. It copies the Steam installation, disables
Steam integration and uses the `stagehand-balatro` save identity. A fresh profile
starts windowed and muted. With Node.js 22+ and a recursive checkout:

```sh
npm ci
npm run fetch:lovely
npm run prepare:game
npm run launch
```

The tools support macOS arm64/x64, Windows x64 and native Linux x64. Linux needs
LÖVE 11.5 installed separately. Use `npm run prepare:game -- --game "/path/to/Balatro"`
for a custom Steam library (point to `Balatro.app` on macOS), or
`npm run launch -- --love "/path/to/love"` for a nonstandard Linux LÖVE executable.

This launcher binds IPv4 loopback, chooses a port and private token, and writes
`.local/session.json`.
Use `connectLocal()` from `client/local.mjs` for that session. Subsequent launches
reuse the profile; after changing the mod, quit, prepare and launch again.

To install from source without the launcher, run `npm run build:mod` and use the
folder or ZIP in `.local/dist/`.

`npm run test:runtime` uses temporary headless fixtures. macOS uses Balatro's
bundled LÖVE; elsewhere set `LOVE_BIN` to an unfused LÖVE 11.5 executable.
`BALATRO_APP` overrides the native-source installation path for tests (the app on
macOS, game directory elsewhere). Fixtures leave player saves untouched.
