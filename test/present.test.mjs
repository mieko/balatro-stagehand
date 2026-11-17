import { test } from 'node:test';
import assert from 'node:assert/strict';
import { present } from '../client/present.mjs';

test('ordinary hands retain order and identity without repeating base-card prose', () => {
  const state = {
    kind: 'SELECTING_HAND',
    money: 0,
    handsLeft: 0,
    discardsLeft: 0,
    hand: [
      {
        ref: 'one',
        name: '2 of Hearts',
        type: 'Default',
        rank: '2',
        suit: 'Hearts',
        chips: 2,
        description: '+2 chips',
        highlighted: false,
        cost: 1,
        sellValue: 1,
        effects: [],
        traits: [],
      },
      { ref: 'hidden', hidden: true, highlighted: true },
    ],
    preview: { name: '', chips: 0, mult: 0 },
    ui: { inputLocked: false },
  };
  const before = structuredClone(state);
  const view = present(state);

  assert.equal(view.money, 0);
  assert.equal(view.handsLeft, 0);
  assert.equal(view.discardsLeft, 0);
  assert.deepEqual(view.hand[1], { ref: 'hidden', hidden: true, selected: true });
  assert.equal(view.hand[0].chips, 2);
  assert.equal(view.hand[0].cost, undefined);
  assert.equal(view.preview, undefined);
  assert.equal(view.ui, undefined);
  assert.equal(view.definitions, undefined);
  assert.deepEqual(state, before);
});

test('shared effect text is defined once while changing counters and variants survive', () => {
  const card = {
    name: 'Native card',
    type: 'Enhanced',
    description: '+ native amount',
    effects: [{ name: 'Native effect', description: 'Native meaning' }],
    traits: ['rental'],
  };
  const raw = {
    hand: [
      { ...card, ref: 'a', chips: 0, rental: true, highlighted: true },
      { ...card, ref: 'b', chips: 4, debuffed: true },
    ],
    jokers: [
      {
        ref: 'j',
        name: 'Native Joker',
        description: 'Currently +0 Mult',
        type: 'Joker',
        eternal: true,
        perishTally: 0,
        pinned: true,
      },
    ],
    preview: { name: 'Pair', chips: 10, mult: 2, rejectedByBlind: true },
  };
  const view = present(raw);

  assert.equal(view.hand[0].definition, view.hand[1].definition);
  assert.equal(view.definitions.length, 2);
  assert.equal(view.hand[0].chips, 0);
  assert.equal(view.hand[0].selected, true);
  assert.equal(view.hand[1].debuffed, true);
  assert.equal(view.jokers[0].perishTally, 0);
  assert.equal(view.jokers[0].eternal, true);
  assert.equal(view.jokers[0].pinned, true);
  assert.equal(view.preview.rejectedByBlind, true);
  assert.equal(present(raw, { diagnostics: true }), raw);
});

test('shop prices, explicit choices and partial purchase evidence stay visible', () => {
  const result = {
    status: 'choice_required',
    state: {
      kind: 'SHOP',
      money: 0,
      shop: {
        rerollCost: 0,
        cards: [{ ref: 'free', name: 'Offer', cost: 0, description: 'Native' }],
      },
      choices: [{ ref: 'blocked', enabled: false }],
      vouchers: [{ name: 'Permanent effect' }],
    },
    results: [
      {
        status: 'completed',
        offer: { ref: 'first', name: 'First' },
        state: { kind: 'SHOP', money: 0 },
      },
    ],
    remaining: [{ ref: 'next' }],
    blocker: { kind: 'inventory_full' },
  };
  const view = present(result);

  assert.equal(view.shop.cards[0].cost, 0);
  assert.equal(view.shop.rerollCost, 0);
  assert.equal(view.choices[0].enabled, false);
  assert.equal(view.steps[0].offer.historical, true);
  assert.equal(view.steps[0].offer.name, 'First');
  assert.equal(result.results[0].offer.ref, 'first');
  assert.deepEqual(view.remaining, ['next']);
  assert.deepEqual(view.blocker, { kind: 'inventory_full' });
  assert.equal(view.vouchers, undefined);
  assert.deepEqual(present(result, { inventory: true }).vouchers, result.state.vouchers);
});

test('terminal reports remain distinct from per-step purchase results', () => {
  const state = {
    kind: 'WIN',
    ready: true,
    run: { seeded: false, seed: 'PUBLIC42' },
    result: {
      outcome: 'won',
      seed: 'PUBLIC42',
      scores: {
        hand: 123,
        poker_hand: { hand: 'Pair', name: 'Localized Pair', count: 4 },
      },
    },
    choices: [{ ref: 'endless', enabled: true }],
  };
  assert.deepEqual(present(state).result, state.result);
  assert.deepEqual(present({ status: 'completed', state }).result, state.result);
  assert.equal(present({ status: 'completed', state }).steps, undefined);
  assert.equal(present(state).run.seed, 'PUBLIC42');
});

test('normal names are the default while native discovery labels remain optional', () => {
  const card = {
    ref: 'visible',
    name: 'Joker',
    discoveryLabel: 'Non découvert',
    type: 'Joker',
    description: '+4 Mult',
  };
  const raw = { shop: { cards: [card] }, hand: [{ ref: 'back', hidden: true }] };
  const before = structuredClone(raw);

  const ordinary = present(raw);
  const discovery = present(raw, { discoveryLabels: true });

  assert.equal(ordinary.shop.cards[0].name, 'Joker');
  assert.equal(ordinary.shop.cards[0].discoveryLabel, undefined);
  assert.equal(discovery.shop.cards[0].name, 'Non découvert');
  assert.equal(ordinary.definitions[0].description, '+4 Mult');
  assert.deepEqual(discovery.hand[0], { ref: 'back', hidden: true });
  assert.equal(present(raw, { diagnostics: true }), raw);
  assert.deepEqual(raw, before);
});

test('earned unlocks and autoskipped notifications retain names and shared definitions', () => {
  const notice = {
    kind: 'unlock',
    text: 'Earned criterion',
    advance: 'native-continue',
    card: { ref: 'earned', name: 'Native Joker', description: 'Native effect', type: 'Joker' },
  };
  const raw = { status: 'completed', state: { kind: 'MENU' }, notifications: [notice] };
  const view = present(raw);

  assert.equal(view.notifications[0].card.name, 'Native Joker');
  assert.equal(view.definitions[0].description, 'Native effect');
  assert.equal(present({ kind: 'MENU', notice }).notice.advance, 'native-continue');
  assert.equal(present(raw, { diagnostics: true }), raw);
});

test('ordinary decisions show hand levels and play counts without repeating their descriptions', () => {
  const raw = {
    kind: 'SELECTING_HAND',
    handTypes: [
      { name: 'Pair', level: 3, played: 4, chips: 35, mult: 4, description: 'Native pair rule' },
      {
        name: 'High Card',
        level: 1,
        played: 0,
        chips: 5,
        mult: 1,
        description: 'Native high card rule',
      },
    ],
  };
  const before = structuredClone(raw);
  const view = present(raw);

  assert.deepEqual(view.handTypes, [
    { name: 'Pair', level: 3, played: 4 },
    { name: 'High Card', level: 1, played: 0 },
  ]);
  assert.deepEqual(raw, before);
  assert.equal(present(raw, { diagnostics: true }), raw);
});

test('an uncertain purchase remains visible separately from never-submitted offers', () => {
  const raw = {
    status: 'unconfirmed',
    state: { kind: 'SHOP', money: 5 },
    results: [],
    attemptedPurchase: {
      status: 'unconfirmed',
      offer: { ref: 'first', name: 'Attempted Joker', cost: 5, description: 'Native effect' },
    },
    remaining: ['second'],
  };
  const view = present(raw);

  assert.equal(view.attemptedPurchase.status, 'unconfirmed');
  assert.equal(view.attemptedPurchase.offer.name, 'Attempted Joker');
  assert.deepEqual(view.remaining, ['second']);
  assert.equal(present(raw, { diagnostics: true }), raw);
});

test('plain card identity is concise while variants, zero values and unknowns stay explicit', () => {
  const raw = {
    kind: 'SELECTING_HAND',
    hand: [
      {
        ref: 'plain',
        name: '2 of Hearts',
        type: 'Default',
        rank: '2',
        suit: 'Hearts',
        chips: 2,
        chipsScope: 'card_bonus_before_edition',
        description: '+2 chips',
        effects: [],
        traits: [],
      },
      {
        ref: 'bonus',
        name: 'Bonus seven',
        type: 'Enhanced',
        rank: '7',
        suit: 'Diamonds',
        chips: 37,
        chipsScope: 'card_bonus_before_edition',
        enhancement: 'm_bonus',
        edition: { foil: true, chips: 50 },
        seal: 'Gold',
        description: '+7 chips +30 extra chips',
        effects: [],
        traits: [],
        forcedSelection: true,
      },
      {
        ref: 'unknown',
        name: 'Unknown rank',
        type: 'Default',
        rank: null,
        suit: 'Hearts',
        chips: null,
        chipsScope: null,
        effects: null,
        highlighted: null,
        debuffed: null,
      },
      { ref: 'back', hidden: true, rank: 'Ace', suit: 'Spades', chips: 11 },
    ],
  };
  const before = structuredClone(raw);
  const view = present(raw);

  assert.deepEqual(
    view.hand.map((card) => card.ref),
    ['plain', 'bonus', 'unknown', 'back'],
  );
  assert.deepEqual(view.hand[0], { ref: 'plain', rank: '2', suit: 'Hearts', chips: 2 });
  assert.equal(view.chipsScope, 'card_bonus_before_edition');
  assert.equal(view.hand[1].enhancement, 'm_bonus');
  assert.equal(view.hand[1].edition.chips, 50);
  assert.equal(view.hand[1].seal, 'Gold');
  assert.equal(view.hand[1].forcedSelection, true);
  assert.equal(view.hand[2].name, 'Unknown rank');
  assert.equal(view.hand[2].rank, null);
  assert.equal(view.hand[2].chips, null);
  assert.equal(view.hand[2].selected, null);
  assert.equal(view.hand[2].debuffed, null);
  assert.equal(view.hand[2].chipsScope, null);
  assert.deepEqual(view.hand[3], { ref: 'back', hidden: true });
  assert.deepEqual(raw, before);
});

test('action views omit routine context while observations and explicit inspection remain self-contained', () => {
  const state = {
    kind: 'SHOP',
    ready: true,
    money: 0,
    bankruptAt: 0,
    run: {
      deck: { id: 'b_red', name: 'Red Deck', description: 'Native deck rule' },
      seeded: false,
      endless: false,
    },
    slots: { jokers: 0, consumables: 2 },
    hand: [],
    jokers: [],
    consumables: [],
    tags: [],
    choices: [],
    shop: { cards: [], packs: [], vouchers: [], rerollCost: 0 },
    counters: {
      handsPlayed: 10,
      cardsDiscarded: 12,
      unusedDiscards: 3,
      roundHandsPlayed: 0,
      roundDiscardsUsed: 0,
      skips: 0,
    },
  };
  const raw = { status: 'completed', kind: 'cashOut', state };
  const before = structuredClone(raw);
  const view = present(raw);

  assert.equal(view.run, undefined);
  assert.deepEqual(view.counters, { roundHandsPlayed: 0, roundDiscardsUsed: 0, skips: 0 });
  assert.equal(view.hand, undefined);
  assert.equal(view.tags, undefined);
  assert.equal(view.choices, undefined);
  assert.equal(view.definitions, undefined);
  assert.equal(view.money, 0);
  assert.equal(view.bankruptAt, 0);
  assert.equal(view.slots.jokers, 0);
  assert.deepEqual(view.jokers, []);
  assert.deepEqual(view.consumables, []);
  assert.equal(view.shop.rerollCost, 0);
  assert.equal(present(state).run.deck.id, 'b_red');
  assert.deepEqual(present(state).counters, state.counters);
  assert.deepEqual(present(raw, { inventory: true }).run, state.run);
  assert.deepEqual(present(raw, { inventory: true }).counters, state.counters);
  assert.equal(present(raw, { diagnostics: true }), raw);
  assert.deepEqual(raw, before);
});

test('a consumed action card is labeled history without stale refs or redundant definitions', () => {
  const raw = {
    status: 'completed',
    kind: 'pickPackCard',
    state: {
      kind: 'SHOP',
      ready: true,
      shop: { cards: [], rerollCost: 5 },
      jokers: [],
      consumables: [],
    },
    selectedCard: {
      ref: 'old-earth',
      name: 'Earth',
      type: 'Planet',
      description: 'Native level effect',
    },
    results: [
      {
        status: 'completed',
        offer: { ref: 'old-pack', name: 'Celestial Pack', cost: 4 },
        state: { kind: 'PLANET_PACK', money: 5 },
      },
    ],
  };
  const before = structuredClone(raw);
  const view = present(raw);

  assert.deepEqual(view.cardAction, {
    kind: 'pickPackCard',
    card: { name: 'Earth', type: 'Planet', historical: true },
  });
  assert.equal(view.selectedCard, undefined);
  assert.equal(view.definitions, undefined);
  assert.equal(view.steps[0].offer.ref, undefined);
  assert.equal(view.steps[0].offer.name, 'Celestial Pack');
  assert.equal(view.steps[0].offer.cost, 4);
  assert.equal(view.steps[0].money, 5);
  assert.deepEqual(raw, before);
});

test('meaningful exceptions, blocked choices and unavailable positions do not become routine omissions', () => {
  const raw = {
    status: 'choice_required',
    state: {
      kind: 'WIN',
      ready: true,
      ui: { inputLocked: true },
      money: null,
      handsLeft: 0,
      run: { seeded: true, seed: 'PUBLIC42', endless: true },
      result: { outcome: 'won', seed: 'PUBLIC42', scores: { hand: 0 } },
      slots: null,
      counters: null,
      choices: [{ ref: 'blocked', enabled: false }],
      handTypes: [{ name: 'Pair', level: 1, played: 0 }],
      consumables: [
        {
          ref: 'target',
          name: 'Aura',
          canUseWithCurrentSelection: false,
          useStatus: 'selection_required',
          targeting: {
            kind: 'hand_selection',
            min: 1,
            max: 1,
            selectedCount: 0,
            countSatisfied: false,
          },
        },
      ],
    },
  };
  const view = present(raw);

  assert.equal(view.money, null);
  assert.equal(view.inputLocked, true);
  assert.equal(view.handsLeft, 0);
  assert.equal(view.slots, null);
  assert.equal(view.counters, null);
  assert.equal(view.run.seed, 'PUBLIC42');
  assert.deepEqual(view.result, raw.state.result);
  assert.equal(view.choices[0].enabled, false);
  assert.equal(view.handTypes[0].played, 0);
  assert.equal(view.consumables[0].canUseWithCurrentSelection, false);
  assert.equal(view.consumables[0].targeting.countSatisfied, false);

  const unavailable = present({
    status: 'unconfirmed',
    state: null,
    remaining: null,
    error: 'Observation failed',
  });
  assert.equal(unavailable.state, null);
  assert.equal(unavailable.remaining, null);
  assert.equal(unavailable.error, 'Observation failed');
});
