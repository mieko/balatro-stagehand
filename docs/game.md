# Balatro gameplay API

Download `/client.mjs` from the game's Stagehand address and save it as
`balatro-stagehand.mjs`. From a Node.js 22+ REPL in its directory:

```js
const { connectBalatro } = await import('./balatro-stagehand.mjs');
const game = await connectBalatro();
console.log(game.present(await game.decision()));
```

Pass `url` to use a different HTTP or HTTPS base address. If **Require Access Token**
is checked, supply `token`, for example `connectBalatro({token: 'copied-token'})`.

Retain `game` between calls. `state()` reads passively. `decision()` waits for a playable position
or native choice. Pass an observed choice to `choose(choice)`.

Gameplay commands run in order and resolve with `status: 'completed'` or `'choice_required'`. Use
`result.state` for the next move and `game.present(result)` for a compact view. Card arguments
accept observed objects or their `ref` strings. Transforming or flipping a card can replace its ref.
Earlier observations keep their old values.

Reuse the returned hand after Strength:

```js
const changed = await game.useConsumable(strength, [nine]);
const hand = changed.state.hand;

const tens = hand.filter((card) => card.rank === '10' && card.suit === 'Hearts');
if (tens.length === 1) await game.playHand(tens);
```

## Run lifecycle

- `runOptions()` lists decks, stakes per deck, challenges and saved-run availability. `startRun()`
  defaults to Red Deck, White Stake. Pass `deck` (observed ID), `stake` (unlocked number) and
  optionally `seed` (1–8 letters/digits, uppercased, `0` becomes `O`), or choose an unlocked
  `challenge` instead of deck/stake/seed. Replacing a save requires `replace: true`.
- `continueRun()` loads the native checkpoint, which can precede the last decision.
- At `WIN`, `continueEndless()` closes the victory overlay. Use/sell cards before `cashOut()` to
  affect the next shop. `returnToMenu()` exits the run screen.
- Terminal `state.result` includes statistics and visible ending text. `scores.poker_hand` is
  `{hand, name, count}` for the most-played hand. No plays gives the native None label and count
  `0`; missing usage data omits the statistic. `result.seed` and `run.seed` appear while the ending
  panel shows the seed.

## Blinds and hands

`blinds()` shows the current ante, skip tags and available controls (`canSkip`, `canReroll`). Use
`selectBlind()`, `skipBlind()` or `rerollBoss()`. A paid reroll can produce the same boss.

`selectCards(cards)` highlights cards and returns the native preview: hand type, base chips/mult and
blind rejection. Final scoring happens during `playHand(cards, options?)`. Face-down cards keep the
unknown preview. `discard(cards)` also waits for resolution. A rejection can leave selection or
order changes visible.

`sortHand('rank' | 'suit')` returns native sort order, including face-down cards, and preserves
selection. `reorderHand(cards)`, `reorderJokers(cards)` and `reorderConsumables(cards)` take full
permutations. Pinned positions stay fixed. Scoring follows physical hand order regardless of
selection order.

Play `selected` with Glass last:

```js
const handOrder = hand.filter((card) => card.ref !== glass.ref).concat(glass);
await game.playHand(selected, { handOrder });
```

`playHand(cards, {endOfRoundJokerOrder: allJokers})` applies the order after scoring, before
round-end effects. A stale permutation fails.

## Shopping and packs

`buy(offerOrList)` buys in order and stops at a pack choice or before a purchase that would exceed
capacity. `results` holds each applied purchase's state. `remaining` lists only unsubmitted offers.
An `attemptedPurchase` with `status: 'unconfirmed'` was dispatched and excluded from `remaining`.
Inspect the position before another purchase.

`buyAndUse(offer, targets?)` uses the native Buy & Use control. `useConsumable(ownedCard, targets?)`
and `pickPackCard(packCard, targets?)` use current highlights when targets are omitted. Other shop
and pack actions are `sell(ownedCard)`, `rerollShop()`, `leaveShop()` and `skipPack()`.

Death copies the right selected card onto the left, regardless of target-array order. Place
`destination` left of `source`:

```js
const others = hand.filter((card) => card.ref !== destination.ref && card.ref !== source.ref);
const arranged = await game.reorderHand(others.concat(destination, source));
await game.pickPackCard(death, arranged.state.hand.slice(-2));
```

For an owned Death, use `game.useConsumable(death, arranged.state.hand.slice(-2))`.

## Inspection and presentation

- `inspectCard(card)` gives native hover text, related definitions and visible modifiers. Owned
  cards expose `canSell`. Copy effects expose `canBeCopied` and `copyCompatibility` where
  applicable.
- Playing-card `chipsScope` is `card_bonus_before_edition`. The `chips` value includes enhancement
  and permanent bonuses (Stone omits base rank), and is zero when debuffed. A foil nine shows `9`
  plus its separate `50`-chip edition. Hand and Joker modifiers are outside this value. Edition
  metadata does not imply an active effect when debuffed.
- Consumable `targeting.kind` is `none` or `hand_selection`. For the latter, inspect `min`/`max`
  and, when a hand is available, `selectedCount`/`countSatisfied`. `useStatus` is `available`,
  `selection_required` or `native_unavailable`. `canUseWithCurrentSelection` checks native
  eligibility for the current highlights, beyond the target count.
- `handTypes()` and `state.handTypes` include descriptions, levels, chips/mult and play counts.
  `deck()` returns the unordered public deck. `deck({remaining: true})` uses Balatro's unplayed-card
  view, including face-down ambiguity. Deck entries have no actionable refs. Semantic observations
  omit hidden card identities and seeds, draw order, future offers and RNG state.

`present(result)` preserves card order, puts effect text in `definitions` and summarizes purchase
`steps`. A `historical: true` card no longer has an actionable ref in that view. `present(state)`
includes run context and lifetime counters. Use `present(result, {inventory: true})` for vouchers,
full run descriptions and lifetime counters after an action. Raw results retain `selectedCard` and
every full purchase snapshot; `present(result, {diagnostics: true})` returns the original input.

## Settings and recovery

`settings()` reports two connection preferences, both off by default. Set either in
`connectBalatro({autoskip: true, discoveryLabels: true})` or change it during play:

- `setAutoskip(true)` advances tutorial Next and earned unlock notices during `decision()` and
  command completion. Gameplay choices stay explicit. Notices appear in `state.notice`, or in
  `result.notifications` when autoskipped.
- `setDiscoveryLabels(true)` shows onboarding labels in `present()`. Raw items retain native names
  and applicable `discoveryLabel` even for undiscovered items.

`setHumanDelay(ms)` paces this connection's gameplay activations. Pass 0–5000 whole milliseconds or
omit to reset to zero. Each purchase and automatic acknowledgement is paced individually. Cash-out
dwell starts when its button is first drawn.

`options()` lists the profile's saved playback speed and available speeds. Pass an offered speed to
`setOptions({gameSpeed})` or use `'fastest'`. `info()` reports mod
(`mod.version`), game/LÖVE versions, save directory and Steam status. `info().mod.resources` resolves
the bundled `agentApi` (this reference), `stagehandApi` and `client` to absolute
`path` and file `url` values on the game’s machine.

Service-reported failure or uncertainty rejects with `.outcome`. Timeout or disconnect leaves
accepted work running without replay. Read `state()` and `recover()` (current/latest operation)
before further input. `resumeQueue()` clears a failed client queue without resubmitting the action.
A settings-driven service restart discards its operation tracking and unissued steps; native changes
already made remain. Reconnect and observe fresh card/choice refs before acting.
A delivered `LoveRuntime.fatal` (Developer Mode) rejects pending and queued calls; submitted work may have applied.
`close()` disconnects. `await (await game.client.root('LoveRuntime')).quit()` quits the game.

## Passive observation

On a separate connection, `spectate()` returns the current ready position, then waits for a changed
one on subsequent calls. Each frame has a local `position`, `boundary` (`settled_position` or
`choice_required`), compact `view` and raw `state`. Readiness describes the native position, not
completion of another client's queue.

```js
const observer = await connectBalatro();
let frame = await observer.spectate();
if (frame) console.log(frame.view);

const next = await observer.spectate({ after: frame ?? undefined, timeoutMs: 20000 });
if (next) {
  frame = next;
  console.log(frame.view);
}
```

`after` is optional. Pass only this observer's last frame object. An idle timeout returns `null` and
preserves the cursor. One wait per observer, 30 seconds by default; pass `signal` to abort. Abort,
disconnect or read failure rejects. Reconnecting starts a new baseline. Selection, order, resources
and choices can produce frames. Dialogue-only changes do not. Fast positions can coalesce.

## Native services

Use `game.client.root(name)` for a discovered root. `Registry` and `Balatro`
are always available while enabled. **Developer Mode** adds `BalatroSceneTree` and:

- `LoveScreen.dimensions()` returns `logical_size` and `texture_size` as `{x, y}`.
  `LoveScreen.capture()` and `game.screenshot()` wait for the next rendered image and return
  metadata plus `image: Buffer`.
- `LoveInput.press({key})` / `release({key})` send LÖVE keyboard callbacks, without changing
  `love.keyboard.isDown()`. Held keys release on disconnect.
- `LoveRuntime.info()` returns `engine` (name/version) and `save_directory`.

### Runtime Lua

`LoveScript` executes arbitrary Lua code with the game's process permissions. See
[security](https://github.com/mieko/balatro-stagehand/blob/main/docs/security.md). Supply synchronous Lua defining `evaluate(bindings)`:

```js
const script = await game.client.root('LoveScript');
const extra = await script.evaluate({
  source: `function evaluate(bindings)
    return G.jokers.cards[bindings.index].ability.extra
  end`,
  bindings: { index: 1 },
});
```

Bindings and the first return value are JSON data. Each call has a fresh definition scope and live
globals. Evaluation runs on the game thread, outside the gameplay queue; wait for gameplay to
settle. A blocking script freezes the game, and an RPC timeout cannot stop it. Changes persist even
if evaluation or result encoding fails.

### Native tree fallback

Use `BalatroSceneTree` for native controls without a semantic helper. `roots()`, `inspect({node})`,
`children({node})` and `query(filters)` expose visible UI and public card areas.

```js
const tree = await game.client.root('BalatroSceneTree');
const { nodes } = await tree.query({ button: 'sort_hand_suit' });
if (nodes.length === 1 && nodes[0].enabled) await tree.click({ node: nodes[0].node });
```

Filter by subtree `root`, inherited `class`, exact `id`/`button`, or case-sensitive literal `text`.
`children` and `query` return `{nodes, more}` and accept `offset`/`limit` (default 100, max 256).
Scope large queries to a root. Pages are live; reacquire stale refs after UI changes. `click`
rechecks availability and refuses during a semantic action. `{clicked: true}` confirms dispatch;
inspect the resulting position for completion.

## Limits

Tested on Balatro 1.0.1o and LÖVE 11.5.
