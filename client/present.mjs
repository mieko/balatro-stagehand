const CARD_FLAGS = {
  highlighted: 'selected',
  debuffed: 'debuffed',
  pinned: 'pinned',
  forcedSelection: 'forcedSelection',
  eternal: 'eternal',
  rental: 'rental',
  perishable: 'perishable',
};

function isEmptyList(value) {
  return Array.isArray(value) && value.length === 0;
}

function definitionFor(card, context) {
  if (
    card.type === 'Default' &&
    isEmptyList(card.effects) &&
    isEmptyList(card.traits) &&
    !card.debuffed
  ) {
    return undefined;
  }

  const definition = {};
  for (const key of ['description', 'effects', 'traits']) {
    if (card[key] !== undefined && !isEmptyList(card[key])) definition[key] = card[key];
  }
  if (Object.keys(definition).length === 0) return undefined;

  const key = JSON.stringify(definition);
  let index = context.definitions.findIndex((item) => item.key === key);
  if (index < 0) {
    index = context.definitions.length;
    context.definitions.push({ key, ...definition });
  }

  return index + 1;
}

function compactPlayingIdentity(view) {
  if (
    view.type !== 'Default' ||
    typeof view.rank !== 'string' ||
    !view.rank ||
    typeof view.suit !== 'string' ||
    !view.suit
  )
    return;

  delete view.type;
  if (typeof view.name === 'string') delete view.name;
}

function compactFlags(view, card) {
  for (const [source, target] of Object.entries(CARD_FLAGS)) {
    delete view[source];
    if (card[source] !== false && card[source] !== undefined) view[target] = card[source];
  }
}

function cardView(card, context, prices = false) {
  if (card == null) return card;

  if (card.hidden) {
    const view = { ref: card.ref, hidden: true };
    if (card.highlighted !== false && card.highlighted !== undefined)
      view.selected = card.highlighted;
    return view;
  }

  const { description, effects, traits, discoveryLabel, position, ...view } = card;
  if (context.discoveryLabels && discoveryLabel !== undefined) view.name = discoveryLabel;

  compactFlags(view, card);
  compactPlayingIdentity(view);
  delete view[prices ? 'sellValue' : 'cost'];
  if (['Default', 'Enhanced'].includes(card.type)) delete view.sellValue;

  if (view.chipsScope === 'card_bonus_before_edition') {
    context.chipsScope = view.chipsScope;
    delete view.chipsScope;
  }

  const definition = definitionFor(card, context);
  if (definition !== undefined) view.definition = definition;
  return view;
}

function cardList(list, context, prices = false) {
  return Array.isArray(list) ? list.map((card) => cardView(card, context, prices)) : list;
}

function currentCardViews(view, context) {
  for (const area of ['hand', 'jokers', 'consumables']) {
    if (view[area] !== undefined) view[area] = cardList(view[area], context);
  }
  if (view.kind === 'SHOP' && isEmptyList(view.hand)) delete view.hand;

  if (view.shop) {
    const shop = { ...view.shop };
    for (const area of ['cards', 'packs', 'vouchers']) {
      if (isEmptyList(shop[area])) delete shop[area];
      else if (shop[area] !== undefined) shop[area] = cardList(shop[area], context, true);
    }
    view.shop = shop;
  }
  if (view.pack) view.pack = { ...view.pack, cards: cardList(view.pack.cards, context) };
}

function compactRun(run, inventory) {
  if (run == null || inventory) return run;

  const view = { ...run };
  for (const key of ['deck', 'stake']) {
    if (view[key]) {
      view[key] = { ...view[key] };
      delete view[key].description;
    }
  }
  return view;
}

function exceptionalRun(run) {
  if (run === null) return true;

  return (
    run.seed !== undefined ||
    run.challenge !== undefined ||
    [run.seeded, run.endless].some((flag) => flag !== undefined && flag !== false)
  );
}

function positionContext(view, { inventory, detailed }) {
  if (view.run !== undefined) {
    if (detailed || exceptionalRun(view.run)) view.run = compactRun(view.run, inventory);
    else delete view.run;
  }
  if (!detailed && view.counters != null) {
    const { handsPlayed, cardsDiscarded, unusedDiscards, ...current } = view.counters;
    if (Object.keys(current).length) view.counters = current;
    else delete view.counters;
  }
  if (!inventory) delete view.vouchers;
}

function noticeView(notice, context) {
  if (notice == null) return notice;

  return notice.card ? { ...notice, card: cardView(notice.card, context) } : { ...notice };
}

function positionView(state, context, options) {
  if (state == null) return { state: null };

  const view = { ...state };
  delete view.ui;
  currentCardViews(view, context);
  positionContext(view, options);

  if (isEmptyList(view.tags)) delete view.tags;
  const choiceScreen =
    state.ui?.overlay || state.ui?.tutorial || state.result !== undefined || state.kind === 'MENU';
  if (isEmptyList(view.choices) && !choiceScreen) delete view.choices;
  if (view.blinds) view.blinds = view.blinds.map(({ display, ...blind }) => blind);
  if (view.notice !== undefined) view.notice = noticeView(view.notice, context);
  if (view.handTypes)
    view.handTypes = view.handTypes.map(({ name, level, played }) => ({ name, level, played }));
  if (view.preview && view.preview.name === '') delete view.preview;
  if (state.ui?.inputLocked !== undefined && state.ui.inputLocked !== false)
    view.inputLocked = state.ui.inputLocked;

  return view;
}

function liveCardRefs(state) {
  const refs = new Set();
  const lists = [
    state?.hand,
    state?.jokers,
    state?.consumables,
    state?.shop?.cards,
    state?.shop?.packs,
    state?.shop?.vouchers,
    state?.pack?.cards,
  ];
  for (const list of lists) {
    for (const card of Array.isArray(list) ? list : []) {
      if (card?.ref != null) refs.add(card.ref);
    }
  }
  return refs;
}

function historyCard(card, context, prices = false) {
  if (card == null) return card;

  const view = context.refs.has(card.ref) ? { ref: card.ref } : { historical: true };
  if (card.hidden) return { ...view, hidden: true };

  const name =
    context.discoveryLabels && card.discoveryLabel !== undefined ? card.discoveryLabel : card.name;
  if (name !== undefined) view.name = name;
  for (const key of ['type', 'rank', 'suit', 'enhancement', 'edition', 'seal']) {
    if (card[key] !== undefined) view[key] = card[key];
  }
  if (prices && card.cost !== undefined) view.cost = card.cost;
  compactPlayingIdentity(view);
  return view;
}

function blockerView(blocker, context) {
  if (blocker == null) return blocker;

  const view = { ...blocker };
  if (blocker.offer !== undefined) view.offer = cardView(blocker.offer, context, true);
  if (blocker.card !== undefined) view.card = cardView(blocker.card, context);
  return view;
}

function actionView(view, result, context) {
  if (result.status !== undefined) view.status = result.status;
  if (result.error != null) view.error = result.error;
  if (result.blocker !== undefined) view.blocker = blockerView(result.blocker, context);
  if (result.selectedCard !== undefined) {
    view.cardAction = { card: historyCard(result.selectedCard, context) };
    if (result.kind !== undefined) view.cardAction.kind = result.kind;
  }
  if (result.attemptedPurchase) {
    view.attemptedPurchase = {
      ...result.attemptedPurchase,
      offer: cardView(result.attemptedPurchase.offer, context, true),
    };
  }
  if (result.notifications !== undefined && !isEmptyList(result.notifications)) {
    view.notifications = Array.isArray(result.notifications)
      ? result.notifications.map((notice) => noticeView(notice, context))
      : result.notifications;
  }
  if (result.remaining !== undefined && !isEmptyList(result.remaining)) {
    view.remaining = Array.isArray(result.remaining)
      ? result.remaining.map((item) => item?.ref ?? item)
      : result.remaining;
  }
  if (result.results?.length) {
    view.steps = result.results.map((step) => ({
      status: step.status,
      offer: historyCard(step.offer, context, true),
      money: step.state?.money,
      kind: step.state?.kind,
    }));
  }
}

function sharedCardFacts(view, context) {
  if (context.chipsScope) view.chipsScope = context.chipsScope;
  if (context.definitions.length) {
    view.definitions = context.definitions.map(({ key, ...definition }, index) => ({
      id: index + 1,
      ...definition,
    }));
  }
}

export function present(
  result,
  { diagnostics = false, inventory = false, discoveryLabels = false } = {},
) {
  if (diagnostics) return result;

  const outcome = Object.hasOwn(result, 'state') || Object.hasOwn(result, 'status');
  const state = outcome ? result.state : result;
  const context = { definitions: [], discoveryLabels, refs: liveCardRefs(state) };
  const detailed = !outcome || inventory || state?.result !== undefined;
  const view = positionView(state, context, { inventory, detailed });
  if (outcome) actionView(view, result, context);
  sharedCardFacts(view, context);

  return view;
}
