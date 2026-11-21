# Security

**The default listener lets local programs control Balatro without authentication.**
Developer Mode adds arbitrary Lua execution, like an attached DevTools console.
Enable Developer Mode only when you want that access.

## Gameplay and Lua access

The `Balatro` endpoint reports player-visible information: face-down cards stay
opaque and the deck view omits draw order. Gameplay commands use native
eligibility checks.

With Developer Mode off (the default), only `Registry` and `Balatro` are registered.
Stagehand's administrative controls are excluded from semantic gameplay choices.
Developer Mode adds `BalatroSceneTree`, `LoveScript`, `LoveInput`, `LoveScreen` and
`LoveRuntime`. Only enable it for clients you trust with the game's process permissions.

`LoveScript.evaluate` can access
`G`, `love`, `require`, `_G` and native libraries. It can inspect hidden cards,
change scores or saves, read and write files, and start programs with the game's
operating-system permissions. Spectators have the same access as drivers.
The gameplay view is not anti-cheat enforcement. See [runtime Lua](game.md#runtime-lua).

## Listener and authentication

Normal installation binds IPv4/IPv6 loopback on port 27121 without requiring a token.
**Allow Remote Connections** opens all network interfaces and requires an access
token. Every authenticated client can control the game, including running arbitrary
Lua when Developer Mode is enabled.

**Require Access Token** authenticates every connection with the launch token available
from **Copy Access Token**. Its source is `STAGEHAND_TOKEN`, or operating-system randomness
when an authenticated listener starts without a supplied token.
The generated token changes on the next game launch and is never saved to the config
file. Applying connection settings closes existing connections. Driver and observer connections
have the same permissions.

Discovery at `/`, the client and both API references are public to anyone who
can reach the listener. Those routes serve bundled files and connection instructions.
RPC runs at `/rpc`. WebSocket upgrades carrying an `Origin` header are rejected
with or without a token. Loopback listening also checks the HTTP `Host` header
for a loopback authority. Plain HTTP and WebSocket traffic is unencrypted. Use
an encrypted tunnel across untrusted networks.

The optional development launcher generates a fresh token and writes it to
`.local/session.json`; `connectLocal()` reads that file. Keep it private. Its
separate app and save identity protect ordinary progress from accidental mixing,
not from scripts that deliberately access other files.

## Timeouts and changes

Scripts run synchronously on the game thread. A blocking script can freeze both
the game and listener. A timeout cannot interrupt execution or undo changes, and
a script may change the game even if encoding its result fails.

Gameplay commands may finish after a timeout or disconnect. Read `state()` and
`recover()` before sending more input; never automatically replay an uncertain
action. Disabling or restarting the service discards pending tracking and unissued
steps, without rolling back native changes. See [command recovery](game.md#settings-and-recovery).
