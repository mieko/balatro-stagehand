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
  assert.deepEqual(view.hand[1], { ref: 'hidden', position: 2, hidden: true, selected: true });
  assert.equal(view.hand[0].chips, 2);
  assert.equal(view.hand[0].cost, undefined);
  assert.equal(view.preview, undefined);
  assert.equal(view.ui, undefined);
  assert.deepEqual(view.definitions, []);
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
  assert.equal(view.steps[0].offer.ref, 'first');
  assert.deepEqual(view.remaining, ['next']);
  assert.deepEqual(view.blocker, { kind: 'inventory_full' });
  assert.equal(view.vouchers, undefined);
  assert.deepEqual(present(result, { inventory: true }).vouchers, result.state.vouchers);
});

test('terminal reports remain distinct from per-step purchase results', () => {
  const state = {
    kind: 'WIN',
    ready: true,
    result: { outcome: 'won', scores: { hand: 123 } },
    choices: [{ ref: 'endless', enabled: true }],
  };
  assert.deepEqual(present(state).result, state.result);
  assert.deepEqual(present({ status: 'completed', state }).result, state.result);
  assert.equal(present({ status: 'completed', state }).steps, undefined);
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
  assert.deepEqual(discovery.hand[0], { ref: 'back', position: 1, hidden: true });
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
