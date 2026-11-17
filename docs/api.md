# Playing through the semantic API

Follow the [setup and connection example](../README.md#play-from-javascript), then
retain `game` between calls. Commands execute in the Lua service; other languages
can call the same named operations through Stagehand's unchanged external client.

`state()` is passive. `decision()` waits for a usable native boundary and honors
the connection's autoskip preference, which defaults to off. Earned unlock notices
and tutorial dialogue remain explicit unless opted in; tutorial gameplay
instructions always remain decisions. `choose(observedChoice)`
uses current native UI references and interactivity, not English captions.

## Run lifecycle

`runOptions()` lists native deck descriptions, per-deck stakes and challenge
availability. Start with `startRun({deck, stake, seed, challenge, replace})`:

- `deck` is an observed deck id; the default is Red Deck.
- `stake` is an observed unlocked stake number; the default is White Stake.
- `seed` is optional native seed entry: 1–8 letters/digits, uppercased, `0` becomes `O`.
- `challenge` chooses an unlocked challenge instead of custom deck/stake/seed.
- `replace: true` explicitly permits replacing an existing saved run.

`continueRun()` loads the native checkpoint. It may precede the last unsaved
decision; it does not reconstruct or replay API history.

`returnToMenu()` uses native navigation. At a `WIN` decision,
`continueEndless()` closes the victory overlay; cash-out is still a separate
decision. Terminal `state.result` contains the outcome and run statistics.
`scores.poker_hand` is `{hand, name, count}`: native hand identity, localized name
and play count. Other score counters remain numeric. No played hand gives count `0`
and the native None label; missing usage data omits the statistic.

`result.seed` and `run.seed` appear only while the native ending panel displays
the seed; `result.text` retains that visible text. Active unseeded runs do not
expose their hidden seed. Starting another run or returning to menu is explicit.

Cash-out remains explicit because you can use/sell cards before the next shop is
generated; that can change the offers. It is not treated as redundant navigation.

## Blinds and hands

`blinds()` describes only the current ante: visible text, selection state and
skip-tag effects. Use `selectBlind()`, `skipBlind()` or `rerollBoss()` when its
native control is available. A reroll is paid and may produce the same boss.

`selectCards(cards)` changes native highlighting and returns the current UI
preview. `playHand(cards, options?)` and `discard(cards)` submit that selection and
wait for resolution. Native blind restrictions remain authoritative. A rejected
command may leave selection/order changes visible; inspect its outcome rather
than assuming no UI change happened.

The preview contains hand type, base chips/multiplier and native blind rejection.
It is **not a final-score prediction**. Face-down selections retain the native
unknown preview; the API does not identify them for you.

Card objects/ref strings identify observed copies. Supply a full permutation to
`reorderHand(cards)`, `reorderJokers(cards)` or `reorderConsumables(cards)`.
Pinned cards keep their native positions. Argument selection order does not
replace left-to-right scoring order. To reorder and play together, pass the full
hand as `playHand(selectedCards, {handOrder: allCards})`.

At a hand decision, `sortHand('rank')` or `sortHand('suit')` presses the native sort
button and returns the resulting order. Face-down cards remain opaque, but their
observed ordering can be used just as when sorting through the game's UI. Sorting
does not play, discard or change the selection; an already-sorted hand completes
normally too.

For deliberate end-of-round ordering, `playHand` also accepts
`endOfRoundJokerOrder: allJokers`. The service applies it at native `end_round`
entry, after the entire hand score is calculated and before round-end effects.
It cannot change that score. A stale permutation fails rather than restoring
removed Jokers; pinned positions still apply. Ordinary play does not pause for
timing decisions or require racing the scoring animation.

## Shopping and packs

`buy(offerOrList)` buys in order. Each applied purchase retains its own state in
`results`; `remaining` identifies offers not submitted after a failure or choice.
An `attemptedPurchase` with `status: 'unconfirmed'` was dispatched but not confirmed;
it is excluded from `remaining`. Inspect fresh state rather than resubmitting it.
A pack stops at its real choices, and full inventory stops before purchase.

`buyAndUse(offer, targets?)` uses the distinct native Buy & Use control.
`useConsumable(ownedCard, targets?)` and `pickPackCard(packCard, targets?)` use
explicit hand targets, or the currently highlighted selection when targets are
omitted. Order-sensitive effects use current hand order; reorder first.

`sell(ownedCard)`, `rerollShop()`, `skipPack()`, `cashOut()` and `leaveShop()`
perform their named native actions. They do not choose other offers, targets or
replacements for you. Prices, bankruptcy allowance and inventory limits come from
the game. Eternal/otherwise ineligible cards remain subject to native checks.

## Inspection and presentation

Descriptions and related definitions come from native public hover models and
localization; there is no separate card/effect catalog. Inspection does not call
RNG-consuming effect getters. Face-down cards stay opaque, and observations never
reveal hidden deck order, future offers, seeds or RNG internals.

`inspectCard(observedCard)` returns its current native description and related
definitions, edition, seal, stickers and visible values. `handTypes()` returns
native poker-hand descriptions/current levels. `deck()` returns the full unordered
public deck; `{remaining: true}` uses Balatro's public unplayed-card semantics,
including face-down-draw ambiguity. Deck records have no actionable ref or draw
position. Reacquire live refs after drawing/flipping cards.

Consumables expose `targeting.kind`: `none` needs no caller-selected cards;
`hand_selection` gives native `min`/`max`, observed `selectedCount` and
`countSatisfied`. Aura also requires an editionless card. An unavailable hand
omits its count/check rather than assuming zero. `useStatus` is `available`,
`selection_required` (count unmet), or `native_unavailable` (another native check).
`canUseWithCurrentSelection` remains authoritative for current highlights, not
proposed targets; satisfying the count does not guarantee eligibility. The final
native use guard can still refuse a use.

Playing-card `chips` uses native `get_chip_bonus()`:
`chipsScope: 'card_bonus_before_edition'`. It includes enhancement and permanent
chip bonuses (Stone excludes base-rank chips), returns zero when debuffed, and
excludes edition chips and hand/Joker modifiers. Thus a Bonus seven can report `37`,
while a foil nine reports `9` with its separate `50`-chip edition. Edition metadata
is separate from whether that edition can currently score (for example, when
debuffed). These are card facts, not a final-score prediction.

Ordinary run state includes visible `handTypes` with native descriptions, levels,
chips/mult and play counts, using the same facts as `handTypes()`. Default
`present()` shows only name/level/played; zero counts remain visible. Full raw
state and purchase snapshots retain the complete records.

Owned cards expose native `canSell`. Blind `canSkip`/`canReroll` reflect the current
controls. Joker rarity labels come from this build's native UI/localization.
Native `canBeCopied` and current `copyCompatibility` remain visible for copy
effects, without inferring a final score from them.

`present(result)` is a pure compact view; it neither mutates nor fetches data.
Array order is card order. Basic cards use `{ref, rank, suit, chips}`; modifiers,
selection, unknowns and blocked actions remain explicit. Shared effect prose goes
in `definitions`, and a repeated known `chipsScope` is shown once at the top.

Action views omit routine run configuration and lifetime totals; current-round
counters, skips, resource values and slot limits stay visible. Standalone
`present(state)` includes run context and all counters. `{inventory: true}` also
includes full run descriptions, lifetime counters and vouchers after an action.
Endings and seeded/challenge/endless exceptions retain their context.

`cardAction` summarizes the operation's card. A card no longer in the current
visible collections is marked `historical: true` without a stale actionable ref
or repeated definition. Purchase `steps` likewise summarize history. Raw results
retain `selectedCard` and every full per-step snapshot; `{diagnostics: true}`
returns that unchanged data.

Visible Jokers, consumables, vouchers and packs use their normal native names and
descriptions even when this save hasn't discovered them. This does not mark them
discovered or reveal face-down cards or unopened pack contents. Raw items retain
the original `discoveryLabel` where applicable;
the session preference below controls which names `game.present(result)` shows.
Effect descriptions remain available in either mode.

`screenshot()` and `LoveScreen.capture()` both wait and return metadata plus
`image: Buffer`.

## Settings and recovery

`setDiscoveryLabels(boolean)` controls onboarding names for this connection;
it defaults to **false**. Set it once, or connect with
`connectLocal({discoveryLabels: true})`, and subsequent `game.present(result)` calls
use that preference. `settings()` reports it alongside `autoskip`. It does not
change the save or the normal names retained in raw results.

`setAutoskip(boolean)` / `settings()` control this connection's autoskip preference;
`connectLocal({autoskip: true})` also opts in. Autoskip affects `decision()` and
command completion, advancing tutorial Next buttons and acknowledging earned unlock
notices until a gameplay choice. It never chooses cards or skips a whole tutorial
section. Unlock notices expose the revealed card and native text in `state.notice`;
autoskipped notices remain in the command result’s `notifications`.
`state()` stays passive.

`options()` reports saved playback speed and available choices.
`setOptions({gameSpeed: 'fastest'})` selects the native maximum (4× in this build),
or pass an offered numeric speed. This calls the native option callback and saves the isolated
profile's setting. Other native options are not exposed. `info()` reports installed
game/LÖVE versions, save directory and Steam status.

Commands share a client FIFO. Ordinary methods wait and return `completed` or
`choice_required`; service-reported failure or uncertainty rejects with `.outcome`. Native
acceptance is not completion. Transport requests and gameplay waits have separate
deadlines. A timeout/disconnect does not cancel or replay accepted work.

Use passive `state()` and `recover()` to inspect uncertainty. The service retains
the current/latest operation in this process; `resumeQueue()` only resets the
client's failed queue. Neither resumes/replays an uncertain game action.
`close()` disconnects. Quit explicitly with
`await (await game.client.builtin('LoveRuntime')).quit()`.

Fatal Lua errors log a traceback and emit `LoveRuntime.fatal`. The JS connection
subscribes automatically and fails pending/queued commands with the cause.
Delivery is best-effort after a socket failure; the native error screen and
private log remain. Hard native crashes cannot run a Lua handler. A fatal error
does not establish whether submitted work applied and never permits replay.

## Human delay

`setHumanDelay(400)` adds a 400ms wall-time pause before gameplay activations.
Default/reset `setHumanDelay()` is zero; accepts integer milliseconds in 0–5000,
matching StS2. It belongs to this client session; reads remain immediate and native
animation speed stays unchanged.

Cash-out has a minimum visible dwell: timing starts after the native cash-out
button is first drawn, and `cashOut()` waits only the remaining interval before
clicking it. Scoring time does not count. Ordered purchases and automatic tutorial/
unlock acknowledgements are paced individually. This does not delay physical human
input or low-level scene-tree clicks.

Other clients send `humanDelayMs` with the same game-operation parameters; the
service owns these waits and advertises its completion allowance on acceptance.
Disconnect does not cancel an accepted operation or replay it. This setting is
independent of passive spectator subscriptions.

## Native services

Discovery exposes `Registry`, `Balatro`, `BalatroSceneTree`, `LoveRuntime`,
`LoveScreen`, `LoveInput` and `LoveScript`. `LoveRuntime.info()` reports an `engine` name/version object and
`save_directory`; Balatro version and Steam status belong to `Balatro.info()`.
The authenticated connection can
drive controls, capture the window and execute Lua with the game's process
permissions. It is trusted developer access, not a sandbox for untrusted clients.

`LoveScreen.dimensions()` returns `logical_size` and `texture_size` as `{x, y}`
records. Capture metadata includes `capture`, `clock`, width/height, MIME and
`phase: 'next_rendered_image'`: LÖVE completes it on a subsequent draw, whereas
Godot captures its last rendered image. The wire protocol returns acceptance
then a correlated `captured` event; the JS wrapper handles that wait and decoding.
LÖVE exposes its current window, without Godot viewport objects.

`LoveInput.press({key})` / `release({key})` deliver LÖVE keyboard callbacks, not OS
keyboard state or overrides of `love.keyboard.isDown()`. Held callbacks belong to
their connection and are released on disconnect.

### Runtime Lua

`LoveScript.evaluate({source, bindings?})` follows Godot's `Script` call shape.
Supply Lua source defining `evaluate(bindings)`; it compiles once per call in a
fresh definition scope with access to real globals such as `G`, `love`, `require`
and `_G`. Definitions do not persist between calls, but changes to native objects
or `_G` do. There is no sandbox, rollback or execution time limit.

```js
const script = await game.client.builtin('LoveScript');
console.log(
  await script.evaluate({
    source: `function evaluate(bindings)
    return G.jokers.cards[bindings.index].ability.extra
end`,
    bindings: { index: 1 }, // Lua arrays are one-based.
  }),
);
```

Bindings and results use the existing JSON codec, without automatic card-ref
resolution or live-object handles. Return plain tables, finite numbers, strings,
booleans or nil/null; empty Lua tables encode as arrays unless marked as objects.
Decoded binding arrays/objects preserve their JSON shape. Functions, native
objects, cycles and results deeper than 64 levels are rejected. Only the first
Lua return value is used; nil becomes null. Strings and object keys must be valid
UTF-8; encode binary data (for example, as Base64) before returning it.

Source and evaluator must finish synchronously; yielding is rejected and never
resumed by the service. Syntax/missing-entry/yield errors use invalid-parameter
errors; Lua runtime errors include a traceback. Unsupported or oversized results
fail with a resource-limit error while keeping the connection usable. Changes
made before any failure remain applied: inspect rather than automatically replay.

Evaluation runs on the game's main thread and bypasses semantic scheduling,
human delay and visibility rules. Wait for gameplay to settle before using it.
A non-returning script blocks the game and listener; an RPC timeout cannot stop
it. Independently started coroutines/events are not cancelled when a call ends.

### Native tree fallback

`BalatroSceneTree` inspects Balatro's own node/UI system. It belongs to the game,
not LÖVE. Use it when a native control has no semantic helper:

```js
const tree = await game.client.builtin('BalatroSceneTree');
console.log(await tree.roots());
const { nodes } = await tree.query({ button: 'sort_hand_suit' });
if (nodes.length === 1 && nodes[0].enabled) {
  console.log(await tree.click({ node: nodes[0].node }));
}
```

`inspect({node})` describes one node; `children({node})` lists its visible children.
`query()` searches breadth-first across UI registries and public card areas, deduplicating shared
nodes. Optional `root` scopes it to one subtree. `class` matches native inheritance; `id` and `button` match
exactly; `text` matches a case-sensitive literal substring of the node's own text.
Native button names are independent of the display language.

Nodes expose `node` references, traversal parents, native `class`/UI-control metadata and current
text. Transforms use native game units; `visual_transform` is the animated position.
These are native visibility flags, not a pixel-visibility test. Entry points may
overlap. Text is capped at 2,048 UTF-8 bytes with `text_truncated`; no raw Lua tables,
model-reference targets, hidden card identities or deck order are returned.

`query` and `children` return `{nodes, more}` and accept `offset` / `limit` (default
100, maximum 256). A traversal exceeding 4,096 nodes or 64 levels fails explicitly;
scope large searches to an observed root. Pages are live queries, not a retained
snapshot. Reacquire stale refs after UI changes.

`click({node})` revalidates the currently visible native button and invokes its
handler. `{clicked: true}` acknowledges dispatch, **not** completion of animation
or gameplay; inspect the resulting UI before acting again. It refuses clicks
during another semantic action or while native controls are unavailable. Prefer
the semantic methods for their game-specific completion and recovery behavior.

## Limits

Native actions and eligibility checks remain authoritative; there is no second
scoring engine. Tooltips, compatibility fields and hand previews are not promises
of a final score, and not every card combination has been exercised through this API.

All five pack families have native paths, but live qualification covers Tarot and
Standard packs. Live consumable use is qualified only for Empress on two cards.
Natural win/endless play, challenges, higher stakes and the
Blueprint/Mime end-of-round ordering interaction remain unqualified. Ordering
timing has source/fixture coverage only. Consumable fixtures check admission and
routing, not every effect animation.

Steamodded/other mods, arbitrary graphical settings, collection browsing and
profile management are not qualified. Use the isolated app/profile described in
the README; reloads restore native checkpoints, not API history.
