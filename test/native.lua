package.path = 'mod/vendor/?.lua;' .. package.path
package.preload['balatro_stagehand.transport'] = function()
    return {}
end

package.loaded['balatro_stagehand.bridge'] = assert(loadfile('mod/bridge.lua'))()
package.preload['balatro_stagehand.text'] = assert(loadfile('mod/text.lua'))
package.preload['balatro_stagehand.controls'] = assert(loadfile('mod/controls.lua'))
package.preload['balatro_stagehand.layout'] = assert(loadfile('mod/layout.lua'))
package.preload['balatro_stagehand.run'] = assert(loadfile('mod/run.lua'))
package.preload['balatro_stagehand.card_action'] = assert(loadfile('mod/card_action.lua'))
package.preload['balatro_stagehand.commerce'] = assert(loadfile('mod/commerce.lua'))
package.preload['balatro_stagehand.server_config'] = assert(loadfile('mod/server_config.lua'))
package.preload['balatro_stagehand.status'] = assert(loadfile('mod/status.lua'))
package.preload['balatro_stagehand.panel'] = assert(loadfile('mod/panel.lua'))
local Actions = assert(loadfile('mod/actions.lua'))()
local State = assert(loadfile('mod/state.lua'))()
local Errors = assert(loadfile('mod/errors.lua'))()
local Options = assert(loadfile('mod/options.lua'))()
local Commerce = assert(loadfile('mod/commerce.lua'))()
local CardAction = assert(loadfile('mod/card_action.lua'))()
local assertions = 0

local function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))

    assertions = assertions + 1
end

-- Playback choices come from the selected native build; fastest is not hard-coded.
do
    local changed, saved = nil, 0
    G = { SETTINGS = { GAMESPEED = 1 }, FUNCS = {} }
    G.FUNCS.change_gamespeed = function(args)
        changed = args.to_val
        G.SETTINGS.GAMESPEED = args.to_val
    end

    function G:save_settings()
        saved = saved + 1
    end

    local options = Options.new({ 1, 2, 8 })

    equal(options:read().gameSpeed, 1)
    equal(options:set({ gameSpeed = 'fastest' }).gameSpeed, 8)
    equal(changed, 8)
    equal(saved, 1)

    local accepted = pcall(options.set, options, { gameSpeed = 7 })

    equal(accepted, false)
    equal(saved, 1)
end

local function fixture()
    G = {
        STATE = 1,
        STAGE = 2,
        STATES = { SELECTING_HAND = 1, MENU = 2 },
        STAGES = { RUN = 2 },
        CONTROLLER = { locked = false },
        GAME = { current_round = { hands_played = 0, discards_used = 0 } },
    }

    love = { timer = {
        getTime = function()
            return 0
        end,
    } }
    local bridge = { tick = 4, instance = 'test', emitted = {} }

    function bridge:emit(_, _, value)
        self.emitted[#self.emitted + 1] = value
    end

    local state = {
        ready = function()
            return true
        end,

        choices = function()
            return {}
        end,

        read = function()
            return { kind = 'SELECTING_HAND' }
        end,

        is_pack = function()
            return false
        end,
    }

    return Actions.new(bridge, state), bridge, state
end

-- A ready hand alone is not evidence that an accepted play ran.
do
    local actions, bridge = fixture()
    actions.pending = {
        action = 'play',
        kind = 'playHand',
        tick = 1,
        started = 0,
        round = G.GAME.current_round,
        hands_played = 0,
    }

    actions:update()

    equal(#bridge.emitted, 0)

    G.GAME.current_round.hands_played = 1
    actions:update()

    equal(bridge.emitted[1].status, 'completed')
    equal(actions.pending, nil)
end

-- A same-screen choice must actually change before it is confirmed.
do
    local actions, bridge, state = fixture()
    state.choices = function()
        return { { ref = 'same' } }
    end

    actions.pending = {
        action = 'choice',
        kind = 'choose',
        tick = 1,
        started = 0,
        choices = { { ref = 'same' } },
    }

    actions:update()

    equal(#bridge.emitted, 0)

    state.choices = function()
        return { { ref = 'next' } }
    end

    actions:update()

    equal(bridge.emitted[1].status, 'completed')
end

-- The submitted order is applied once at the native round boundary, not admission.
do
    local actions = fixture()
    local a, b = {}, {}
    local aligned = 0
    G.jokers = {
        cards = { a, b },
        align_cards = function()
            aligned = aligned + 1
        end,
    }

    actions.pending = { joker_order = { b, a } }

    equal(G.jokers.cards[1], a)

    actions:before_end_round()

    equal(G.jokers.cards[1], b)
    equal(actions.pending.order_applied, true)

    actions:before_end_round()

    equal(aligned, 1)
end

-- A destroyed/replaced Joker cannot be reintroduced by a queued permutation.
do
    local actions = fixture()
    local a, old, replacement = {}, {}, {}
    G.jokers = {
        cards = { a, replacement },
        align_cards = function()
            error('must not align')
        end,
    }

    actions.pending = { joker_order = { old, a } }
    actions:before_end_round()

    equal(actions.pending.order_applied, false)
    equal(G.jokers.cards[2], replacement)
end

-- Projection failure reports failure while retaining the applied action identity.
do
    local actions, bridge, state = fixture()
    state.read = function()
        error('bad projection')
    end

    actions.pending = { action = 'applied', kind = 'playHand' }
    actions:finish('completed')

    equal(bridge.emitted[1].action, 'applied')
    equal(bridge.emitted[1].status, 'failed')
    equal(actions.pending, nil)
end

-- Native blind descriptions can be a string or a list of lines.
do
    fixture()
    G.STAGES = { RUN = 2 }
    G.GAME.round_resets = { ante = 1 }
    G.GAME.blind =
        { config = { blind = { key = 'native' } }, loc_debuff_text = 'Native description' }
    local state = State.new()
    state.ready = function()
        return true
    end

    state.choices = function()
        return {}
    end

    equal(state:read().blind.description, 'Native description')

    G.GAME.blind.loc_debuff_text = { 'First', 'second' }

    equal(state:read().blind.description, 'First second')
end

-- Native hover titles and dynamic text use both strings and node lists.
do
    fixture()
    local state = State.new()
    local card = { config = { center = { key = 'c_base' } }, base = {}, ability = {} }

    function card:generate_UIBox_ability_table()
        return {
            name = { { config = { text = ' King  of Spades ' } } },
            main = { { config = { object = { string = '+10 chips' } } } },
        }
    end

    equal(state:card(card).name, 'King of Spades')
    equal(state:card(card).description, '+10 chips')
end

-- Inspection retains native related-effect definitions, without evaluating effects.
do
    fixture()
    local state = State.new()
    local card = {
        config = { center = { key = 'native_tarot', blueprint_compat = false } },
        ability = { set = 'Tarot', blueprint_compat = 'incompatible' },
    }

    function card:generate_UIBox_ability_table()
        return {
            name = 'Native offer',
            main = { { config = { text = 'Creates a native effect' } } },
            info = { { name = 'Native effect', { config = { text = '+ native amount' } } } },
            badges = { 'native_badge' },
        }
    end

    function card:get_chip_mult()
        error('must not evaluate random effects')
    end

    local detail = state:card(card)

    equal(detail.effects[1].name, 'Native effect')
    equal(detail.effects[1].description, '+ native amount')
    equal(detail.traits[1], 'native_badge')
    equal(detail.canBeCopied, false)
    equal(detail.copyCompatibility, 'incompatible')
end

-- Face-down appearances do not reveal a model or retain its prior public identity.
do
    local state = State.new()
    local card = { facing = 'back' }
    local previous = state:ref(card)
    state:forget(card)
    local hidden = state:card(card)

    equal(hidden.hidden, true)
    equal(hidden.name, nil)
    equal(hidden.ref ~= previous, true)

    card.facing, card.sprite_facing = 'front', 'back'

    equal(state:card(card).hidden, true)
end

-- A shop is ready after native offer construction, including an emptied shop.
do
    fixture()
    G.STATES.SHOP, G.STATE = 5, 5
    G.shop = {}
    local state = State.new()

    equal(not not state:ready(), false)

    G.shop.stagehand_offers_ready = true

    equal(state:ready(), true)
end

-- A visible unlock notice remains actionable while gameplay is locked.
do
    fixture()
    G.CONTROLLER.locked = true
    G.OVERLAY_MENU = {}
    local state = State.new()
    state.choices = function()
        return { { ref = 'notice', enabled = true } }
    end

    equal(state:ready(), true)

    G.screenwipe = {}

    equal(state:ready(), false)

    G.screenwipe, G.OVERLAY_MENU = nil, nil
    G.OVERLAY_TUTORIAL = { step_complete = false }

    equal(state:ready(), false)

    G.OVERLAY_TUTORIAL.step_complete = true

    equal(state:ready(), true)
end

-- Pack setup and teardown are not decisions, even while the state enum is unchanged.
do
    fixture()
    G.STATE, G.STATES.TAROT_PACK = 9, 9
    G.STATE_COMPLETE = true
    G.pack_cards = {}
    local state = State.new()

    equal(not not state:ready(), false)

    G.pack_cards.cards = { {} }
    G.E_MANAGER = { queues = { base = { { blocking = true, complete = false } } } }

    equal(state:ready(), false)

    G.E_MANAGER.queues.base = {}
    G.TAROT_INTERRUPT = G.STATE

    equal(state:ready(), false)

    G.TAROT_INTERRUPT = nil

    equal(state:ready(), true)
end

-- Autoskip belongs to the driving session and advances Next, never Skip or gameplay.
do
    local actions, bridge, state = fixture()
    local advanced = 0
    local button = { config = { button = 'tut_next' }, states = { visible = true } }

    function button:click()
        advanced = advanced + 1
    end

    state.buttons = { next = button }
    state.choices = function()
        return {
            { ref = 'skip', action = 'skip_tutorial_section', enabled = true },
            { ref = 'next', action = 'tut_next', enabled = true },
        }
    end

    G.OVERLAY_TUTORIAL = { step_complete = true }
    actions.pending = { action = 'manual', kind = 'decision', tick = 1, started = 0, peer = {} }
    actions:update()

    equal(advanced, 0)
    equal(bridge.emitted[1].status, 'choice_required')

    actions.pending = {
        action = 'automatic',
        kind = 'decision',
        tick = 1,
        started = 0,
        peer = { autoskip = true },
    }

    actions:update()

    equal(advanced, 1)
    equal(#bridge.emitted, 1)

    state.choices = function()
        return { { ref = 'skip', action = 'skip_tutorial_section', enabled = true } }
    end

    G.OVERLAY_TUTORIAL.button_listen = 'play_cards_from_highlighted'
    actions:update()

    equal(advanced, 1)
    equal(bridge.emitted[2].status, 'choice_required')
end

-- Fatal reporting retains the native error screen and full private traceback.
do
    local previous, notified
    love = {
        errhand = function(message)
            previous = message

            return 'native handler'
        end,
    }

    Errors.notify = function(fatal)
        notified = fatal
    end

    Errors.install()

    equal(love.errhand('controlled fixture fault'), 'native handler')
    equal(previous, 'controlled fixture fault')
    equal(notified.message, 'controlled fixture fault')
    equal(type(notified.traceback), 'string')
end

-- Server-side purchases preserve earlier applied steps if a later offer is refused.
do
    fixture()
    G.STATE, G.STATES.SHOP = 5, 5
    G.shop_jokers, G.jokers = { cards = {} }, { cards = {} }
    G.E_MANAGER = { queues = { base = {} } }
    local purchases = 0
    local available = true
    G.FUNCS = {
        can_buy = function(node)
            node.config.button = available and 'buy_from_shop' or nil
        end,

        check_for_buy_space = function()
            return true
        end,
    }

    local cards = {}

    for _, ref in ipairs({ 'first', 'second' }) do
        local card = { ref = ref, area = G.shop_jokers, children = {} }

        function card:click()
            self.highlighted = true
        end

        local node = { config = { func = 'can_buy' }, states = { visible = true } }

        function node:click()
            purchases = purchases + 1
            card.area = G.jokers
        end

        card.children.buy_button = { UIRoot = node }
        cards[ref] = card
    end

    local state = {
        find_card = function(_, ref)
            return cards[ref]
        end,

        card = function(_, card)
            return { ref = card.ref }
        end,

        is_pack = function()
            return false
        end,

        read = function()
            return { purchases = purchases }
        end,
    }

    local commerce = Commerce.new(state)
    local job = commerce:begin({ 'first', 'second' })
    commerce:update(job)
    commerce:update(job)
    commerce:update(job)

    equal(job.results[1].state.purchases, 1)

    available = false
    commerce:update(job)
    local status = commerce:update(job)

    equal(status, 'failed')
    equal(purchases, 1)
    equal(commerce:remaining(job)[1], 'second')

    -- Both purchases wait independently; a completed first step cannot spend the next delay.
    local now = 0
    love.timer.getTime = function()
        return now
    end

    available = true
    purchases = 0
    for _, card in pairs(cards) do
        card.area = G.shop_jokers
    end

    job = commerce:begin({ 'first', 'second' }, 400)
    commerce:update(job)

    equal(job.step, nil)

    now = 0.4
    commerce:update(job)
    commerce:update(job)
    commerce:update(job)

    equal(purchases, 1)

    commerce:update(job)
    now = 0.799
    commerce:update(job)

    equal(purchases, 1)

    now = 0.8
    commerce:update(job)
    commerce:update(job)

    equal(purchases, 2)
end

-- Full native inventory is an explicit choice boundary; no purchase is submitted.
do
    fixture()
    G.STATE, G.STATES.SHOP = 5, 5
    G.shop_jokers = {}
    local card = { area = G.shop_jokers, children = {} }

    function card:click()
        self.highlighted = true
    end

    local node = { config = { func = 'can_buy' }, states = { visible = true } }

    function node:click()
        error('must not purchase')
    end

    card.children.buy_button = { UIRoot = node }
    G.FUNCS = {
        can_buy = function(button)
            button.config.button = 'buy_from_shop'
        end,

        check_for_buy_space = function()
            return false
        end,
    }

    local state = {
        find_card = function()
            return card
        end,

        card = function()
            return { ref = 'offer' }
        end,
    }

    local commerce = Commerce.new(state)
    local job = commerce:begin({ 'offer' })
    commerce:update(job)

    equal(commerce:update(job), 'choice_required')
    equal(job.blocker.kind, 'inventory_full')
    equal(#job.results, 0)
    equal(commerce:remaining(job)[1], 'offer')
end

-- Card use waits for the native control and removal, without choosing targets itself.
do
    fixture()
    G.consumeables, G.hand = {}, { highlighted = {} }
    local calls = 0
    local card = { area = G.consumeables, ability = { consumeable = {} }, children = {} }
    local button = { config = { func = 'can_use_consumeable' }, states = { visible = true } }

    function button:click()
        calls = calls + 1
        card.area = nil
    end

    function card:click()
        self.highlighted = true
        self.children.use_button = { UIRoot = button }
    end

    G.FUNCS = {
        can_use_consumeable = function(node)
            node.config.button = 'use_card'
        end,
    }

    local state = {
        find_card = function()
            return card
        end,

        card = function()
            return { ref = 'owned' }
        end,

        is_pack = function()
            return false
        end,
    }

    local family = CardAction.new(state)
    local job = family:begin('useConsumable', { ref = 'owned' })

    equal(calls, 0)
    equal(family:update(job), nil)
    equal(calls, 1)
    equal(family:update(job), 'completed')
end

-- Current-ante blind inspection reads native UI text rather than calculating a target.
do
    fixture()
    G.GAME.round_resets =
        { blind_choices = { Boss = 'visible_boss' }, blind_states = { Boss = 'Upcoming' } }
    G.GAME.current_round.most_played_poker_hand = 'Pair'
    G.P_BLINDS = { visible_boss = { dollars = 5 } }
    G.STATES.BLIND_SELECT, G.STATE = 7, 7
    local pane = { UIRoot = { children = { { config = { text = 'Native target 987' } } } } }

    function pane:get_UIE_by_ID(id)
        if id == 'blind_desc' then
            return { config = { text = 'Native boss effect' } }
        end
    end

    G.blind_select_opts = { boss = pane }
    localize = function(value)
        if type(value) == 'string' then
            return value
        end

        return value.type == 'name_text' and 'Native boss' or { 'Definition' }
    end

    local blind = State.new():blinds()[1]

    equal(blind.name, 'Native boss')
    equal(blind.description, 'Native boss effect')
    equal(blind.display, 'Native target 987')
    equal(blind.scope, 'visible_ui')
end

-- Automatic unlock acknowledgement waits for reveal and preserves each earned notice.
do
    local actions, bridge, state = fixture()
    local notices = { { kind = 'unlock', revealing = true }, { kind = 'unlock', text = 'Second' } }
    local current, clicks = 1, 0
    local button = { config = { button = 'continue_unlock' }, states = { visible = true } }

    function button:click()
        clicks = clicks + 1
        current = current + 1
    end

    state.buttons = { advance = button }
    state.choices = function()
        return notices[current]
                and { { ref = 'advance', action = 'continue_unlock', enabled = true } }
            or {}
    end

    state.notice = function()
        return notices[current]
    end

    G.OVERLAY_MENU = {}
    actions.pending = { action = 'manual', kind = 'decision', tick = 1, started = 0, peer = {} }
    actions:update()

    equal(clicks, 0)
    equal(bridge.emitted[1].status, 'choice_required')

    bridge.emitted = {}

    actions.pending = {
        action = 'automatic',
        kind = 'decision',
        tick = 1,
        started = 0,
        peer = { autoskip = true },
    }
    actions:update()

    equal(clicks, 0)
    equal(#bridge.emitted, 0)

    notices[1] = { kind = 'unlock', text = 'First', card = { name = 'Native Joker' } }
    actions:update()
    actions:update()
    actions:update()

    equal(clicks, 2)
    equal(#bridge.emitted, 1)
    equal(bridge.emitted[1].notifications[1].card.name, 'Native Joker')
    equal(bridge.emitted[1].notifications[2].text, 'Second')
end

-- Human delay holds native activation; cash-out counts from its first rendered decision.
do
    local actions, bridge, state = fixture()
    local now, activated = 10, 0
    love.timer.getTime = function()
        return now
    end

    actions.execute = function()
        activated = activated + 1
    end

    actions:start('selectCards', {}, {})

    equal(activated, 1)

    actions.pending = nil
    actions:start('selectCards', { humanDelayMs = 400 }, {})

    equal(activated, 1)

    now = 10.399
    actions:update()

    equal(activated, 1)

    now = 10.4
    actions:update()

    equal(activated, 2)

    actions.pending = nil

    G.STATES.ROUND_EVAL = 3
    G.STATE = 3
    local button = { config = { button = 'cash_out' }, states = { visible = true } }
    state.cash_out_button = function()
        return button
    end

    now = 50
    actions:start('cashOut', { humanDelayMs = 400 }, {})
    actions:update()

    equal(activated, 2)

    actions:after_draw()
    now = 50.2
    actions:update()

    equal(activated, 2)

    now = 50.4
    actions:update()

    equal(activated, 3)

    actions.pending = nil

    -- Time spent deciding already satisfies the same screen's interval.
    now = 52
    actions:start('cashOut', { humanDelayMs = 400 }, {})
    actions:update()

    equal(activated, 4)

    -- Replacing the button creates a new visible boundary, even on the same state.
    actions.pending = nil
    button = { config = { button = 'cash_out' }, states = { visible = true } }
    actions:after_draw()
    actions:start('cashOut', { humanDelayMs = 400 }, {})
    actions:update()

    equal(activated, 4)

    now = 52.2
    button = { config = { button = 'cash_out' }, states = { visible = true } }
    actions:after_draw()
    now = 52.4
    actions:update()

    equal(activated, 4)

    now = 52.6
    actions:update()

    equal(activated, 5)
end

-- Native cash-out itself is not clicked until dwell has elapsed; completion follows the transition.
do
    local actions, bridge, state = fixture()
    local now, clicks = 0, 0
    love.timer.getTime = function()
        return now
    end

    G.STATES.ROUND_EVAL, G.STATES.SHOP = 3, 4
    G.STATE = G.STATES.ROUND_EVAL
    local button = { config = { button = 'cash_out' }, states = { visible = true } }

    function button:click()
        clicks = clicks + 1
        G.STATE = G.STATES.SHOP
    end

    state.cash_out_button = function()
        return button
    end

    state.read = function()
        return { kind = G.STATE == G.STATES.SHOP and 'SHOP' or 'ROUND_EVAL' }
    end

    actions:after_draw()
    now = 0.1
    local accepted = actions:start('cashOut', { humanDelayMs = 400 }, {})
    actions:update()

    equal(clicks, 0)
    equal(#bridge.emitted, 0)
    equal(state:read().kind, 'ROUND_EVAL')

    now = 0.4
    actions:update()

    equal(clicks, 1)
    equal(#bridge.emitted, 0)

    bridge.tick = bridge.tick + 2
    actions:update()

    equal(bridge.emitted[1].action, accepted.action)
    equal(bridge.emitted[1].status, 'completed')
    equal(bridge.emitted[1].state.kind, 'SHOP')
end

-- Bad delay parameters fail before admission; batch wall allowance includes intentional waits.
do
    local actions = fixture()
    for _, invalid in ipairs({ -1, 5001, '400', false, 0.5, math.huge, 0 / 0 }) do
        equal(pcall(actions.start, actions, 'decision', { humanDelayMs = invalid }, {}), false)
        equal(actions.pending, nil)
    end

    actions.execute = function() end
    local items = {}
    for i = 1, 32 do
        items[i] = 'offer' .. i
    end

    local accepted = actions:start('buy', { items = items, humanDelayMs = 5000 }, {})

    equal(accepted.completionTimeoutMs, 290000)
end

-- Only never-submitted purchases remain retryable; an uncertain native click is separate.
for _, mode in ipairs({
    'timeout',
    'native_error',
    'observation_error',
    'readiness_error',
    'validation_error',
}) do
    local actions, bridge, state = fixture()
    local now, clicks = 0, 0
    love.timer.getTime = function()
        return now
    end

    G.STATE, G.STATES.SHOP = 5, 5
    G.TIMERS = { REAL = 1 }
    G.shop_jokers, G.jokers = {}, {}
    G.E_MANAGER = { queues = { base = {} } }
    G.FUNCS = {
        check_for_buy_space = function()
            return true
        end,
    }
    local first = { ref = 'first', area = G.shop_jokers, highlighted = true, children = {} }
    local button = { config = { button = 'buy_from_shop' }, states = { visible = true } }

    function button:click()
        clicks = clicks + 1
        if mode == 'native_error' then
            error('native dispatch fault')
        end

        if mode == 'observation_error' then
            first.area = G.jokers
        end
    end

    if mode == 'validation_error' then
        button.last_clicked = 1
    end

    first.children.buy_button = { UIRoot = button }
    state.ready = function()
        if mode == 'readiness_error' and clicks > 0 then
            error('readiness projection fault')
        end

        return true
    end

    state.find_card = function()
        return first
    end

    state.card = function(_, card)
        return { ref = card.ref }
    end

    state.read = function()
        if mode == 'observation_error' and clicks > 0 then
            error('projection fault')
        end

        return { kind = 'SHOP', purchases = clicks }
    end

    actions:start('buy', { items = { 'first', 'second' } }, {})
    bridge.tick = bridge.tick + 2
    actions:update()
    actions:update()
    actions:update()
    now = 121
    actions:update()
    local result = bridge.emitted[1]

    if mode == 'validation_error' then
        equal(clicks, 0)
        equal(result.status, 'failed')
        equal(result.remaining[1], 'first')
        equal(result.attemptedPurchase, nil)
    else
        equal(clicks, 1)
        assert(result.status == 'unconfirmed', mode .. ': expected uncertainty')
        equal(#result.results, 0)
        equal(#result.remaining, 1)
        equal(result.remaining[1], 'second')
        equal(result.attemptedPurchase.offer.ref, 'first')
        equal(result.attemptedPurchase.status, 'unconfirmed')
    end
end

print('Native behavior assertions passed: ' .. assertions)
