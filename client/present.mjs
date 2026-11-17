function cardView(card, position, definitions, prices, discoveryLabels) {
  if (card.hidden) {
    return {
      ref: card.ref,
      position,
      hidden: true,
      ...(card.highlighted ? { selected: true } : {}),
    };
  }

  const {
    description,
    effects,
    traits,
    highlighted,
    debuffed,
    pinned,
    forcedSelection,
    eternal,
    rental,
    perishable,
    discoveryLabel,
    ...view
  } = card;
  if (discoveryLabels && discoveryLabel !== undefined) {
    view.name = discoveryLabel;
  }

  const plain = card.type === 'Default' && !effects?.length && !traits?.length && !debuffed;
  let index;
  if (!plain) {
    const definition = { description, effects, traits };
    const key = JSON.stringify(definition);
    index = definitions.findIndex((item) => item.key === key);
    if (index < 0) {
      index = definitions.length;
      definitions.push({ key, ...definition });
    }
  }

  if (prices) {
    delete view.sellValue;
  } else {
    delete view.cost;
  }

  if (['Default', 'Enhanced'].includes(card.type)) {
    delete view.sellValue;
  }

  return {
    ...view,
    ...(position !== undefined ? { position } : {}),
    ...(index !== undefined ? { definition: index + 1 } : {}),
    ...(highlighted ? { selected: true } : {}),
    ...(debuffed ? { debuffed: true } : {}),
    ...(pinned ? { pinned: true } : {}),
    ...(forcedSelection ? { forcedSelection: true } : {}),
    ...(eternal ? { eternal: true } : {}),
    ...(rental ? { rental: true } : {}),
    ...(perishable ? { perishable: true } : {}),
  };
}

export function present(
  result,
  { diagnostics = false, inventory = false, discoveryLabels = false } = {},
) {
  if (diagnostics) {
    return result;
  }

  const state = result.state ?? result;
  const {
    ui,
    hand,
    jokers,
    consumables,
    shop,
    pack,
    vouchers,
    preview,
    run,
    notice,
    handTypes,
    ...view
  } = state;
  const definitions = [];
  const cards = (list, prices = false) =>
    list?.map((card, index) => cardView(card, index + 1, definitions, prices, discoveryLabels));

  const compactShop = shop && {
    ...shop,
    cards: cards(shop.cards, true),
    packs: cards(shop.packs, true),
    vouchers: cards(shop.vouchers, true),
  };
  const compactBlinds = view.blinds?.map(({ display, ...blind }) => blind);

  const noticeView = (notice) => ({
    ...notice,
    ...(notice.card
      ? { card: cardView(notice.card, undefined, definitions, false, discoveryLabels) }
      : {}),
  });

  const output = {
    ...(result.status ? { status: result.status } : {}),
    ...view,
    ...(notice ? { notice: noticeView(notice) } : {}),
    ...(result.notifications?.length
      ? { notifications: result.notifications.map(noticeView) }
      : {}),
    ...(run
      ? {
          run: inventory
            ? run
            : {
                ...run,
                deck: run.deck && { id: run.deck.id, name: run.deck.name },
                stake: run.stake && { id: run.stake.id, name: run.stake.name },
              },
        }
      : {}),
    ...(hand ? { hand: cards(hand) } : {}),
    ...(jokers ? { jokers: cards(jokers) } : {}),
    ...(consumables ? { consumables: cards(consumables) } : {}),
    ...(compactBlinds ? { blinds: compactBlinds } : {}),
    ...(compactShop ? { shop: compactShop } : {}),
    ...(pack ? { pack: { ...pack, cards: cards(pack.cards) } } : {}),
    ...(preview?.name ? { preview } : {}),
    ...(handTypes
      ? { handTypes: handTypes.map(({ name, level, played }) => ({ name, level, played })) }
      : {}),
    ...(inventory ? { vouchers } : {}),
    ...(result.error != null ? { error: result.error } : {}),
    ...(result.blocker
      ? {
          blocker: {
            ...result.blocker,
            ...(result.blocker.offer
              ? {
                  offer: cardView(
                    result.blocker.offer,
                    undefined,
                    definitions,
                    true,
                    discoveryLabels,
                  ),
                }
              : {}),
            ...(result.blocker.card
              ? {
                  card: cardView(
                    result.blocker.card,
                    undefined,
                    definitions,
                    false,
                    discoveryLabels,
                  ),
                }
              : {}),
          },
        }
      : {}),
    ...(result.selectedCard
      ? {
          selectedCard: cardView(
            result.selectedCard,
            undefined,
            definitions,
            false,
            discoveryLabels,
          ),
        }
      : {}),
    ...(result.attemptedPurchase
      ? {
          attemptedPurchase: {
            status: result.attemptedPurchase.status,
            offer: cardView(
              result.attemptedPurchase.offer,
              undefined,
              definitions,
              true,
              discoveryLabels,
            ),
          },
        }
      : {}),
    ...(result.remaining?.length
      ? { remaining: result.remaining.map((item) => item.ref ?? item) }
      : {}),
    ...(Array.isArray(result.results)
      ? {
          steps: result.results.map((step) => ({
            status: step.status,
            offer: cardView(step.offer, undefined, definitions, true, discoveryLabels),
            money: step.state?.money,
            kind: step.state?.kind,
          })),
        }
      : {}),
  };
  output.definitions = definitions.map(({ key, effects, traits, ...definition }, index) => ({
    id: index + 1,
    ...definition,
    ...(effects?.length ? { effects } : {}),
    ...(traits?.length ? { traits } : {}),
  }));

  return output;
}
