# Balatro Stagehand

This repository owns the Lua service, Balatro semantics and JavaScript bindings.
The pinned Stagehand dependency supplies the external JS transport; keep Godot
contracts and game-specific behavior separate.

Use native actions and player-visible facts. Do not expose hidden deck order,
future shops, seeds or RNG internals through semantic observations. Never simulate
legal play by editing score, money, cards or unlocks.

Work on an isolated app/profile with Steam integration disabled. Preserve the
Steam installation and normal saves. Coordinate reloads with the current driver.
Keep copied proprietary source, downloaded tools, sessions, tokens, exported saves
and logs under ignored `.local/`. Keep plans and qualification history there too;
repository docs describe current use and contracts. Do not commit or publish
without authorization.

Ordinary hand play waits for completion. Optional end-of-round Joker reordering
must use a verified native boundary; never require callers to race animations.
