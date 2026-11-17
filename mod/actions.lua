local Bridge = require('balatro_stagehand.bridge')
local Commerce = require('balatro_stagehand.commerce')
local CardAction = require('balatro_stagehand.card_action')
local Controls = require('balatro_stagehand.controls')
local Layout = require('balatro_stagehand.layout')
local Run = require('balatro_stagehand.run')
local Actions = {}
Actions.__index = Actions

function Actions.new(bridge, state)
    return setmetatable({
        bridge = bridge,
        state = state,
        next_id = 0,
        commerce = Commerce.new(state),
        card_action = CardAction.new(state),
    }, Actions)
end

function Actions:require_state(expected, button)
    local tutorial_blocks = G.OVERLAY_TUTORIAL and G.OVERLAY_TUTORIAL.button_listen ~= button

    if
        G.STATE ~= G.STATES[expected]
        or not self.state:ready()
        or G.OVERLAY_MENU
        or tutorial_blocks
    then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Expected an available ' .. expected .. ' decision')
    end
end

function Actions:click(node, expected)
    Controls.click(node, expected)
end

function Actions:resolve(area, requested)
    return Layout.resolve(self.state, area, requested)
end

function Actions:reorder(area, cards)
    Layout.reorder(area, cards)
end

function Actions:select_cards(params, discard)
    self:require_state(
        'SELECTING_HAND',
        discard and 'discard_cards_from_highlighted' or 'play_cards_from_highlighted'
    )
    local cards = Layout.validate_selection(self.state, params.cards)

    if #cards < 1 or #cards > G.hand.config.highlighted_limit then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Invalid selected card count')
    end

    local order

    if params.endOfRoundJokerOrder then
        if discard then
            Bridge.fail(Bridge.INVALID_PARAMS, 'End-of-round ordering requires playHand')
        end

        order = self:resolve(G.jokers, params.endOfRoundJokerOrder)
        Layout.validate_order(G.jokers, order)
    end

    if discard and G.GAME.current_round.discards_left <= 0 then
        Bridge.fail(Bridge.INVALID_PARAMS, 'No discards remain')
    end

    if params.handOrder then
        self:reorder(G.hand, self:resolve(G.hand, params.handOrder))
    end

    Layout.select(self.state, params.cards)

    if discard then
        local button = G.buttons:get_UIE_by_ID('discard_button')
        G.FUNCS.can_discard(button)
        self:click(button, 'discard_cards_from_highlighted')
    else
        local button = G.buttons:get_UIE_by_ID('play_button')
        G.FUNCS.can_play(button)

        if not button.config.button then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Native play is unavailable')
        end

        self.pending.joker_order = order
        self:click(button, 'play_cards_from_highlighted')
    end
end

function Actions:execute(name, params)
    if name == 'decision' then
        return
    elseif name == 'playHand' or name == 'discard' then
        self:select_cards(params, name == 'discard')
    elseif name == 'startRun' then
        local terminal = self.state:kind() == 'GAME_OVER' or Run.is_win()

        if terminal and not self.state:ready() then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Wait for the results decision')
        end

        if not terminal then
            self:require_state('MENU')
        end

        Run.start(params)
    elseif name == 'continueRun' then
        self:require_state('MENU')

        if not G.FUNCS.can_continue({ config = { func = true } }) or not G.SAVED_GAME then
            Bridge.fail(Bridge.INVALID_PARAMS, 'No resumable native save')
        end

        G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
    elseif name == 'selectBlind' then
        self:require_state('BLIND_SELECT', 'select_blind')
        local pane = G.blind_select_opts[G.GAME.blind_on_deck:lower()]
        self:click(pane:get_UIE_by_ID('select_blind_button'), 'select_blind')
    elseif name == 'cashOut' then
        self:require_state('ROUND_EVAL')
        self:click(self.state:cash_out_button(), 'cash_out')
    elseif name == 'leaveShop' then
        self:require_state('SHOP', 'toggle_shop')
        self:click(G.shop:get_UIE_by_ID('next_round_button'), 'toggle_shop')
    elseif name == 'buy' then
        self:require_state('SHOP', 'buy_from_shop')
        self.pending.shopping = self.commerce:begin(params.items, self.pending.humanDelayMs)
    elseif
        name == 'sell'
        or name == 'useConsumable'
        or name == 'pickPackCard'
        or name == 'buyAndUse'
    then
        if not self.state:ready() then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Wait for a decision')
        end

        self.pending.card_action = self.card_action:begin(name, params)
    elseif name == 'rerollShop' then
        self:require_state('SHOP')
        local node = Controls.find(G.shop, 'func', 'can_reroll')
        Controls.refresh(node)
        self.pending.rerolls = G.GAME.round_scores.times_rerolled.amt
        self:click(node, 'reroll_shop')
    elseif name == 'skipPack' then
        if not self.state:is_pack() then
            Bridge.fail(Bridge.INVALID_PARAMS, 'No open pack')
        end

        local node = Controls.find(G.booster_pack, 'func', 'can_skip_booster')
        Controls.refresh(node)
        self:click(node, 'skip_booster')
    elseif name == 'skipBlind' then
        self:require_state('BLIND_SELECT', 'skip_blind')
        local pane = G.blind_select_opts[G.GAME.blind_on_deck:lower()]
        self.pending.before_blind = G.GAME.blind_on_deck
        self:click(Controls.find(pane, 'button', 'skip_blind'), 'skip_blind')
    elseif name == 'rerollBoss' then
        self:require_state('BLIND_SELECT', 'reroll_boss')
        local pane = G.blind_select_opts.boss
        local button = Controls.find(G.blind_prompt_box, 'func', 'reroll_boss_button')
        Controls.refresh(button)
        self.pending.boss_pane = pane
        self:click(button, 'reroll_boss')
    elseif name == 'continueEndless' then
        Run.continue_endless()
    elseif name == 'returnToMenu' then
        if not self.state:ready() then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Wait for a decision')
        end

        G.FUNCS.go_to_menu()
    elseif name == 'selectCards' then
        self:require_state('SELECTING_HAND')
        Layout.select(self.state, params.cards)
    elseif name == 'sortHand' then
        local callback = params.by == 'rank' and 'sort_hand_value'
            or params.by == 'suit' and 'sort_hand_suit'

        if not callback then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Expected sort by rank or suit')
        end

        self:require_state('SELECTING_HAND', callback)
        self:click(Controls.find(G.buttons, 'button', callback), callback)
    elseif name == 'reorderJokers' or name == 'reorderHand' or name == 'reorderConsumables' then
        if not self.state:ready() then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Wait for a decision')
        end

        local area = name == 'reorderHand' and G.hand
            or name == 'reorderConsumables' and G.consumeables
            or G.jokers
        self:reorder(area, self:resolve(area, params.cards))
    elseif name == 'choose' then
        self.state:choices()
        local node = self.state.buttons[params.ref]

        if not node or not node.config.button then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Choice is stale or unavailable')
        end

        self:click(node, node.config.button)
    else
        Bridge.fail(Bridge.METHOD_NOT_FOUND, 'Unknown game action')
    end
end

function Actions:start(name, params, peer)
    if self.pending then
        Bridge.fail(Bridge.INPUT_CONFLICT, 'Another game action is active')
    end

    local delay = params.humanDelayMs

    if delay == nil then
        delay = 0
    end

    if
        type(delay) ~= 'number'
        or delay ~= delay
        or delay < 0
        or delay > 5000
        or delay ~= math.floor(delay)
    then
        Bridge.fail(Bridge.INVALID_PARAMS, 'humanDelayMs must be an integer in 0..5000')
    end

    local steps = name == 'buy' and type(params.items) == 'table' and math.min(#params.items, 32)
        or 1
    self.next_id = self.next_id + 1
    local action = {
        action = self.bridge.instance .. ':a' .. self.next_id,
        kind = name,
        status = 'accepted',
        humanDelayMs = delay,
        params = params,
        timeout_seconds = 120 + steps * delay / 1000,
        started = love.timer.getTime(),
        tick = self.bridge.tick,
        round = G.GAME.current_round,
        hands_played = G.GAME.current_round and G.GAME.current_round.hands_played or 0,
        discards_used = G.GAME.current_round and G.GAME.current_round.discards_used or 0,
        choices = self.state:choices(),
        peer = peer,
    }

    self.pending = action
    if delay == 0 or name == 'decision' or name == 'buy' then
        local ok, problem = pcall(self.dispatch, self, action)

        if not ok then
            self:finish('failed', type(problem) == 'table' and problem.message or tostring(problem))
        end
    end

    return {
        action = action.action,
        status = 'accepted',
        completionTimeoutMs = action.timeout_seconds * 1000 + 10000,
    }
end

function Actions:dispatch(action)
    action.tick = self.bridge.tick
    self:execute(action.kind, action.params)
    action.params = nil
end

function Actions:after_draw()
    local button = G.STATE == G.STATES.ROUND_EVAL
            and not G.OVERLAY_MENU
            and self.state:cash_out_button()
        or nil

    if button ~= self.cash_out_button then
        self.cash_out_button = button
        self.cash_out_visible_at = button and love.timer.getTime() or nil
    end
end

function Actions:waiting_to_activate(action)
    local since = action.started

    if action.kind == 'cashOut' and G.STATE == G.STATES.ROUND_EVAL then
        if not self.cash_out_button or self.cash_out_button ~= self.state:cash_out_button() then
            return true
        end

        since = self.cash_out_visible_at
    end

    return Controls.wait_delay(action, action.humanDelayMs, since)
end

function Actions:advance_autoskip(action)
    if not action.peer or not action.peer.autoskip then
        return false
    end

    for _, choice in ipairs(self.state:choices()) do
        local unlock = G.OVERLAY_MENU and choice.action == 'continue_unlock'
        local tutorial = G.OVERLAY_TUTORIAL and choice.action == 'tut_next'

        if choice.enabled and (unlock or tutorial) then
            local notice = unlock and self.state:notice()

            if notice and notice.revealing then
                return true
            end

            action.automatic_wait = action.automatic_wait or {}

            if Controls.wait_delay(action.automatic_wait, action.humanDelayMs) then
                return true
            end

            self:click(self.state.buttons[choice.ref], choice.action)
            action.automatic_wait = nil

            if notice then
                action.notifications = action.notifications or Bridge.array()
                action.notifications[#action.notifications + 1] = notice
            end

            return true
        end
    end

    return false
end

function Actions:before_end_round()
    local action = self.pending

    if action and action.joker_order then
        local ok, problem = pcall(self.reorder, self, G.jokers, action.joker_order)
        action.order_applied = ok
        action.order_error = not ok
                and (type(problem) == 'table' and problem.message or tostring(problem))
            or nil
        action.joker_order = nil
    end
end

function Actions:advance()
    local action = self.pending

    if not action then
        return
    end

    if love.timer.getTime() - action.started > (action.timeout_seconds or 120) then
        self:finish('unconfirmed', 'Game did not settle; do not replay automatically')
        return
    end

    if action.params then
        if self:waiting_to_activate(action) then
            return
        end

        self:dispatch(action)
        return
    end

    if self.bridge.tick <= action.tick + 1 or not self.state:ready() then
        return
    end

    if self:advance_autoskip(action) then
        return
    end

    if action.shopping then
        local status, problem = self.commerce:update(action.shopping)

        if status then
            self:finish(status, problem)
        end

        return
    end

    if action.card_action then
        local ok, status = pcall(self.card_action.update, self.card_action, action.card_action)

        if not ok then
            self:finish('failed', type(status) == 'table' and status.message or tostring(status))
        elseif status then
            self:finish(status)
        end

        return
    end

    if action.kind == 'rerollShop' and G.GAME.round_scores.times_rerolled.amt <= action.rerolls then
        return
    end

    if action.kind == 'skipPack' and self.state:is_pack() then
        return
    end

    if action.kind == 'skipBlind' and G.GAME.blind_on_deck == action.before_blind then
        return
    end

    if action.kind == 'rerollBoss' and G.blind_select_opts.boss == action.boss_pane then
        return
    end

    if action.kind == 'continueEndless' and G.OVERLAY_MENU then
        return
    end

    if action.kind == 'returnToMenu' and G.STAGE ~= G.STAGES.MAIN_MENU then
        return
    end

    if (action.kind == 'startRun' or action.kind == 'continueRun') and G.STAGE ~= G.STAGES.RUN then
        return
    end

    if action.kind == 'selectBlind' and G.STATE == G.STATES.BLIND_SELECT then
        return
    end

    if action.kind == 'cashOut' and G.STATE == G.STATES.ROUND_EVAL then
        return
    end

    if action.kind == 'leaveShop' and G.STATE == G.STATES.SHOP then
        return
    end

    if action.kind == 'playHand' then
        if action.round.hands_played <= action.hands_played then
            return
        end
    elseif action.kind == 'discard' then
        if action.round.discards_used <= action.discards_used then
            return
        end
    elseif action.kind == 'choose' then
        local after = self.state:choices()
        local same = #after == #action.choices

        for i, choice in ipairs(after) do
            local before = action.choices[i]

            if
                not before
                or before.ref ~= choice.ref
                or before.action ~= choice.action
                or before.enabled ~= choice.enabled
                or before.label ~= choice.label
            then
                same = false
            end
        end

        if same then
            return
        end
    end

    local status = (G.OVERLAY_MENU or G.OVERLAY_TUTORIAL or self.state:is_pack())
            and 'choice_required'
        or 'completed'
    self:finish(action.order_error and 'failed' or status, action.order_error)
end

function Actions:update()
    local action = self.pending

    if not action then
        return
    end

    local ok, problem = pcall(self.advance, self)

    if not ok and self.pending == action then
        self:finish('failed', type(problem) == 'table' and problem.message or tostring(problem))
    end
end

function Actions:finish(status, problem)
    local action = self.pending
    local attempted = action.shopping and self.commerce:attempted(action.shopping)

    if attempted then
        status = 'unconfirmed'
    end

    local observed, state = pcall(self.state.read, self.state)

    if not observed then
        status = status == 'unconfirmed' and status or 'failed'
        problem, state = 'Final observation failed: ' .. tostring(state), nil
    end

    local result = {
        action = action.action,
        kind = action.kind,
        status = status,
        error = problem,
        state = state,
        notifications = action.notifications,
        endOfRoundReorderApplied = action.order_applied or false,
    }

    if action.shopping then
        result.results = action.shopping.results
        result.remaining = self.commerce:remaining(action.shopping)
        result.attemptedPurchase = attempted
        result.blocker = action.shopping.blocker
    end

    if action.card_action then
        result.selectedCard = action.card_action.selectedCard
        result.blocker = action.card_action.blocker
    end

    self.pending = nil
    self.latest = result
    self.bridge:emit(self.root, 'completed', result)
end

return Actions
