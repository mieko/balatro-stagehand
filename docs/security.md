# Security

**Anyone who can authenticate to the running mod can execute arbitrary Lua in
the Balatro process.** Think of an attached browser DevTools console. You can
inspect live objects, change them and watch the running game respond. Clients
speak Stagehand's JSON-RPC protocol over WebSocket.

## Gameplay and Lua access

The `Balatro` endpoint reports player-visible information. For example, a
face-down card stays opaque and the deck view omits draw order. A gameplay
command such as `playHand` uses the game's native eligibility checks.

The mod also registers `LoveScript` by default. Its `evaluate` operation runs
Lua with access to the game's globals and native libraries, including `G`,
`love`, `require` and `_G`. Any authenticated client can call it directly. A spectator uses the same
credentials and can switch to the debugger at any time. Scripts can inspect
hidden cards, change scores or saves, read or write files and start
programs with the game's operating-system permissions. The gameplay view offers
no anti-cheat protection against such a client. See the [Lua call and result
format](api.md#runtime-lua).

## Connection and profile

The mod requires a nonempty `STAGEHAND_TOKEN`. The launcher chooses a loopback
port, generates a new token and writes both to `.local/session.json`.
`connectLocal()` reads that file. Keep it private. Loopback controls which
machines can reach the listener, and the token controls who can connect.
Neither restricts what an authenticated script can do.

The separate app and LÖVE save identity keep ordinary game progress separate
from the Steam profile. They place no restriction on files a script can open.
Plain `ws://` carries the token and traffic unencrypted. For a trusted remote
client, use an encrypted tunnel to the loopback listener.

## Timeouts and changes

Scripts execute synchronously on the game thread. A script that blocks can
freeze Balatro and the listener. A timeout cannot interrupt it or undo changes.
A script may change the game even if encoding its return value fails.

A gameplay command may also finish after a timeout or disconnect. Read
`state()` and `recover()` before sending another command. Never automatically
replay an uncertain action. See [command recovery](api.md#settings-and-recovery).
