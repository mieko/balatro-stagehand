local Bridge = require('balatro_stagehand.bridge')
local Layout = {}

function Layout.resolve(state, area, requested)
    if not area or type(requested) ~= 'table' then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Expected a list of current cards')
    end

    local cards, seen = {}, {}

    for _, value in ipairs(requested) do
        local ref = type(value) == 'table' and value.ref or value
        local found

        for _, card in ipairs(area.cards) do
            if state:ref(card) == ref then
                found = card
            end
        end

        if not found or seen[found] then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Stale or repeated card reference')
        end

        seen[found] = true
        cards[#cards + 1] = found
    end

    return cards, seen
end

function Layout.validate_order(area, cards)
    if #area.cards ~= #cards then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Supply every card exactly once')
    end

    local members, seen = {}, {}

    for _, card in ipairs(area.cards) do
        members[card] = true
    end

    for index, card in ipairs(cards) do
        if not members[card] or seen[card] then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Card order is stale')
        end

        if card.pinned and area.cards[index] ~= card then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Pinned cards must stay in their native positions')
        end

        seen[card] = true
    end
end

function Layout.reorder(area, cards)
    Layout.validate_order(area, cards)

    for index, card in ipairs(cards) do
        area.cards[index] = card
    end

    area:align_cards()
end

function Layout.validate_selection(state, requested)
    local cards, selected = Layout.resolve(state, G.hand, requested)

    if #cards > G.hand.config.highlighted_limit then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Too many selected cards')
    end

    for _, card in ipairs(G.hand.highlighted) do
        if card.ability.forced_selection and not selected[card] then
            Bridge.fail(Bridge.INVALID_PARAMS, 'A forced selected card must be included')
        end
    end

    return cards
end

function Layout.select(state, requested)
    local cards = Layout.validate_selection(state, requested)

    G.hand:unhighlight_all()

    for _, card in ipairs(cards) do
        if not card.highlighted then
            G.hand:add_to_highlighted(card)
        end
    end

    if #G.hand.highlighted ~= #cards then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Native selection refused')
    end

    return cards
end

return Layout
