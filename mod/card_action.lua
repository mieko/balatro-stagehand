local Bridge = require('balatro_stagehand.bridge')
local Controls = require('balatro_stagehand.controls')
local Layout = require('balatro_stagehand.layout')
local CardAction = {}
CardAction.__index = CardAction

function CardAction.new(state)
    return setmetatable({ state = state }, CardAction)
end

function CardAction:begin(kind, params)
    local card = self.state:find_card(params.ref)
    local allowed = kind == 'useConsumable' and card.area == G.consumeables
        or kind == 'pickPackCard' and self.state:is_pack() and card.area == G.pack_cards
        or kind == 'sell' and (card.area == G.jokers or card.area == G.consumeables)
        or kind == 'buyAndUse'
            and G.STATE == G.STATES.SHOP
            and card.area == G.shop_jokers
            and card.ability.consumeable
    if not allowed then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Card is not in the required area')
    end

    if params.targets then
        Layout.select(self.state, params.targets)
    end

    if not card.highlighted then
        card:click()
    end

    local validator = kind == 'sell' and 'can_sell_card'
        or kind == 'buyAndUse' and 'can_buy_and_use'
        or card.ability.consumeable and 'can_use_consumeable'
        or 'can_select_card'
    return {
        card = card,
        area = card.area,
        validator = validator,
        phase = 'selected',
        button = kind == 'buyAndUse' and 'buy_and_use_button' or 'use_button',
        selectedCard = self.state:card(card),
    }
end

function CardAction:update(job)
    if job.phase == 'selected' then
        local node = Controls.find(job.card.children[job.button], 'func', job.validator)

        if not node then
            return
        end

        Controls.refresh(node)

        if not node.config.button then
            job.blocker = { kind = 'native_card_action_unavailable', card = job.selectedCard }

            return 'choice_required'
        end

        if job.validator ~= 'can_sell_card' and job.card.check_use and job.card:check_use() then
            job.blocker = { kind = 'native_card_action_unavailable', card = job.selectedCard }

            return 'choice_required'
        end

        local callback = job.validator == 'can_sell_card' and 'sell_card'
            or job.validator == 'can_buy_and_use' and 'buy_from_shop'
            or 'use_card'
        Controls.click(node, callback)
        job.phase = 'applying'
        return
    end

    if job.card.area == job.area then
        return
    end

    if self.state:is_pack() or G.OVERLAY_MENU or G.OVERLAY_TUTORIAL then
        return 'choice_required'
    end

    return 'completed'
end

return CardAction
