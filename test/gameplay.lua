package.path = 'mod/vendor/?.lua;' .. package.path
package.preload['balatro_stagehand.transport'] = function()
    return {}
end

for _, name in ipairs({
    'bridge',
    'text',
    'controls',
    'layout',
    'run',
    'card_action',
    'commerce',
    'state',
    'actions',
}) do
    package.preload['balatro_stagehand.' .. name] = assert(loadfile('mod/' .. name .. '.lua'))
end

local State = require('balatro_stagehand.state')
local Layout = require('balatro_stagehand.layout')
local Run = require('balatro_stagehand.run')
local CardAction = require('balatro_stagehand.card_action')
local Actions = require('balatro_stagehand.actions')

local function fixture()
    G = {
        STATE = 1,
        STAGE = 1,
        STATES = {
            SELECTING_HAND = 1,
            GAME_OVER = 4,
            SHOP = 5,
            BLIND_SELECT = 7,
            ROUND_EVAL = 8,
            MENU = 11,
        },
        STAGES = { MAIN_MENU = 1, RUN = 2 },
        CONTROLLER = { locked = false },
        TIMERS = { REAL = 1 },
        GAME = {
            current_round = {},
            round_resets = { ante = 8 },
            round_scores = { hand = { amt = 123 } },
            round = 24,
        },
        SETTINGS = { profile = 1 },
        PROFILES = { { challenge_progress = { completed = {} } } },
        P_CENTER_POOLS = { Back = {}, Stake = {} },
        P_CENTERS = {},
        CHALLENGES = {},
        FUNCS = {},
        UIDEF = {},
    }

    love = {
        filesystem = {
            getInfo = function()
                return nil
            end,
        },
        timer = {
            getTime = function()
                return 0
            end,
        },
    }

    localize = function(value)
        return type(value) == 'table' and value.key or value
    end

    get_deck_win_stake = function()
        return 0
    end

    return State.new()
end

-- A final-boss loss may carry won=true. Only the native victory surface means won.
do
    fixture()
    G.STATE, G.GAME.won = G.STATES.GAME_OVER, true

    assert(Run.results().outcome == 'lost')

    G.STATE = G.STATES.ROUND_EVAL
    local continued = 0
    local button = { config = { button = 'exit_overlay_menu' }, states = { visible = true } }
    function button:click()
        continued = continued + 1
        G.OVERLAY_MENU = nil
    end

    G.OVERLAY_MENU = {
        children = {
            { config = { id = 'from_game_won' } },
            button,
            {
                states = { visible = false },
                config = { id = 'seed' },
                children = { { config = { text = 'PRIVATESEED' } } },
            },
            { config = { text = 'Victory' } },
        },
    }

    assert(Run.results().outcome == 'won')
    assert(Run.results().text == 'Victory')
    assert(Run.results().scores.hand == 123)

    Run.continue_endless()

    assert(continued == 1 and G.STATE == G.STATES.ROUND_EVAL)
    assert(Run.results() == nil)
    assert(not pcall(Run.continue_endless))
end

-- Stakes are unlocked per deck; locked challenges and conflicting setup cannot start.
do
    fixture()
    local deck = { key = 'b_native', set = 'Back', unlocked = true }
    G.P_CENTERS.b_native = deck
    G.P_CENTER_POOLS.Back = { deck }
    G.P_CENTERS.b_challenge = { key = 'b_challenge', set = 'Back', unlocked = true, omit = true }
    G.P_CENTER_POOLS.Stake = { { key = 'one' }, { key = 'two' }, { key = 'three' } }
    G.UIDEF.stake_description = function(index)
        return 'Native stake ' .. index
    end

    get_deck_win_stake = function(key)
        assert(key == 'b_native')

        return 1
    end

    assert(Run.validate({ deck = 'b_native', stake = 2 }).stake == 2)
    assert(not pcall(Run.validate, { deck = 'b_native', stake = 3 }))

    G.PROFILES[1].all_unlocked = true

    assert(Run.validate({ deck = 'b_native', stake = 3, seed = 'abc123' }).seed == 'ABC123')
    assert(not pcall(Run.validate, { deck = 'b_native', seed = 'bad seed' }))
    assert(Run.validate({ deck = 'b_native', seed = '0' }).seed == 'O')
    assert(not pcall(Run.validate, { deck = 'b_challenge' }))

    G.CHALLENGES = { { id = 'native_challenge' } }
    G.PROFILES[1].all_unlocked = false

    assert(not pcall(Run.validate, { challenge = 'native_challenge' }))

    G.PROFILES[1].challenges_unlocked = 1
    local args = Run.validate({ challenge = 'native_challenge' })

    assert(args.challenge == G.CHALLENGES[1] and args.stake == 1)
    assert(not pcall(Run.validate, { challenge = 'native_challenge', seed = 'ABC' }))
end

-- Challenge context passes the native challenge id into its Back description.
do
    local state = fixture()
    G.STAGE, G.STATE = G.STAGES.RUN, G.STATES.SELECTING_HAND
    G.GAME.challenge = 'native_challenge'
    G.GAME.selected_back = {
        effect = { center = { key = 'b_challenge' } },
        get_name = function()
            return 'Challenge Deck'
        end,
        generate_UI = function(_, _, _, _, challenge)
            assert(challenge == 'native_challenge')

            return 'Native challenge description'
        end,
    }

    state.ready = function()
        return true
    end

    state.choices = function()
        return {}
    end

    local observed = state:read()

    assert(observed.run.deck.description == 'Native challenge description')
    assert(observed.run.challenge == 'native_challenge')
end

-- Pinned Jokers stay at their native positions; all other cards can be permuted.
do
    fixture()
    local pinned, first, second = { pinned = true }, {}, {}
    local area = { cards = { pinned, first, second }, align_cards = function() end }
    Layout.reorder(area, { pinned, second, first })

    assert(area.cards[2] == second)
    assert(not pcall(Layout.reorder, area, { first, second, pinned }))
    assert(not pcall(Layout.reorder, area, { pinned, second, second }))
    assert(area.cards[1] == pinned and area.cards[2] == second)
end

-- A native preview is requested by highlighting, not by invoking a scoring simulator.
do
    local state = fixture()
    local first, second = { ability = {} }, { ability = { forced_selection = true } }
    G.hand =
        { cards = { first, second }, highlighted = { second }, config = { highlighted_limit = 5 } }
    function G.hand:unhighlight_all()
        self.highlighted = { second }
    end

    function G.hand:add_to_highlighted(card)
        card.highlighted = true
        self.highlighted[#self.highlighted + 1] = card
    end

    second.highlighted = true

    assert(not pcall(Layout.select, state, { state:ref(first) }))

    Layout.select(state, { state:ref(first), state:ref(second) })

    assert(#G.hand.highlighted == 2)
end

-- Tooltip inspection removes its own temporary objects, never their referenced game data.
do
    local state = fixture()
    local removed, touched = 0, 0
    local dynamic = {
        string = '0',
        config = { string = { '0', '1', '2', '3' } },
        remove = function()
            removed = removed + 1
        end,
    }

    local decoration = {
        string = { string = 'rand()' },
        config = { string = { { string = 'rand()' }, { string = '#@14S' }, ' Mult ', ' Mult ' } },
        remove = function()
            removed = removed + 1
        end,
    }

    local referenced = {
        remove = function()
            touched = touched + 1
        end,
    }

    local title = {
        string = 'Native title',
        remove = function()
            removed = removed + 1
        end,
    }

    local tooltip = state:tooltip({
        name = { { config = { object = title } } },
        main = {
            { config = { text = '+' } },
            { config = { object = dynamic, ref_table = referenced } },
            { config = { object = decoration } },
        },
    })

    assert(tooltip.description == '+ 0–3 Mult')
    assert(tooltip.name == 'Native title')
    assert(removed == 3 and touched == 0)
end

-- Public deck inspection has no action handles or true facedown-hand membership.
do
    local state = fixture()
    G.STAGE = G.STAGES.RUN
    G.deck = {}
    local function card(name, area, wheel)
        local value = {
            area = area,
            facing = 'back',
            config = { center = { key = 'c_base' } },
            base = { value = name },
            ability = {
                wheel_flipped = wheel,
                set = 'Default',
                forced_selection = wheel,
            },
        }

        function value:generate_UIBox_ability_table()
            return { name = name, main = name }
        end

        function value:get_chip_bonus()
            return 2
        end

        return value
    end

    local unseen = card('2', G.deck)
    local facedown_drawn = card('3', {}, true)
    G.playing_cards = { facedown_drawn, unseen }
    local remaining = state:deck(true)

    assert(remaining.count == 2 and remaining.cards[1].name == '2')
    assert(remaining.cards[1].ref == nil and remaining.cards[1].hidden == nil)
    assert(remaining.cards[2].forcedSelection == nil)
    assert(G.playing_cards[1] == facedown_drawn)
    assert(state:card(facedown_drawn).hidden)
end

-- All native pack states use the same membership/choice boundary.
do
    local state = fixture()

    for index, name in ipairs({
        'TAROT_PACK',
        'SPECTRAL_PACK',
        'PLANET_PACK',
        'STANDARD_PACK',
        'BUFFOON_PACK',
    }) do
        G.STATES[name], G.STATE = 20 + index, 20 + index
        G.pack_cards = { cards = { {} } }
        G.STATE_COMPLETE = true

        assert(state:is_pack() and state:ready())

        G.pack_cards.cards = nil

        assert(not state:ready())
    end
end

-- Wait for a transient flip, while an intentionally face-down card remains a decision.
do
    local state = fixture()
    G.STATES.TAROT_PACK, G.STATE = 9, 9
    G.STATE_COMPLETE = true
    G.pack_cards = { cards = { { facing = 'front', sprite_facing = 'back' } } }

    assert(not state:ready())

    G.pack_cards.cards[1].sprite_facing = 'front'

    assert(state:ready())

    G.pack_cards.cards[1].facing = 'back'
    G.pack_cards.cards[1].sprite_facing = 'back'

    assert(state:ready())

    G.GAME.STOP_USE = 1

    assert(not state:ready())

    G.GAME.STOP_USE = 0

    assert(state:ready())
end

-- Buy-and-use invokes the native control rather than first consuming an inventory slot.
do
    local state = fixture()
    G.STATE = G.STATES.SHOP
    G.shop = { stagehand_offers_ready = true }
    G.shop_jokers = { cards = {} }
    local applied = 0
    local card =
        { area = G.shop_jokers, highlighted = true, ability = { consumeable = {} }, children = {} }
    local button =
        { config = { id = 'buy_and_use', func = 'can_buy_and_use' }, states = { visible = true } }
    function button:click()
        applied = applied + 1
        card.area = nil
    end

    G.FUNCS.can_buy_and_use = function(node)
        node.config.button = 'buy_from_shop'
    end

    card.children.buy_and_use_button = { UIRoot = button }
    G.shop_jokers.cards = { card }
    state.card = function()
        return { ref = 'offer' }
    end

    local family = CardAction.new(state)
    local job = family:begin('buyAndUse', { ref = state:ref(card) })

    assert(family:update(job) == nil and applied == 1)
    assert(family:update(job) == 'completed')
end

-- A boss reroll may choose the same definition; replacement of its native pane proves completion.
do
    local state = fixture()
    G.STATE, G.STAGE = G.STATES.BLIND_SELECT, G.STAGES.RUN
    G.blind_select_opts = { boss = {} }
    local bridge = { tick = 5, instance = 'fixture', emit = function() end }
    local output
    state.ready = function()
        return true
    end

    state.read = function()
        return {}
    end

    local actions = Actions.new(bridge, state)
    local clicked = 0
    local button = { config = { func = 'reroll_boss_button' }, states = { visible = true } }
    function button:click()
        clicked = clicked + 1
    end

    G.blind_prompt_box = { children = { button } }
    G.FUNCS.reroll_boss_button = function(node)
        node.config.button = 'reroll_boss'
    end

    actions:start('rerollBoss', {}, {})

    assert(clicked == 1 and actions.pending.boss_pane == G.blind_select_opts.boss)

    actions.finish = function(_, status)
        output = status
    end

    actions.pending =
        { kind = 'rerollBoss', tick = 1, started = 0, boss_pane = G.blind_select_opts.boss }
    actions:update()

    assert(output == nil)

    G.blind_select_opts.boss = {}
    actions:update()

    assert(output == 'completed')
end

-- Native errors after submission retain the action and observed partial progress.
do
    local state = fixture()
    local applied, events = false, {}
    local bridge = { tick = 1, instance = 'fixture' }
    function bridge:emit(_, _, result)
        events[#events + 1] = result
    end

    state.choices = function()
        return {}
    end

    state.read = function()
        return { applied = applied }
    end

    local actions = Actions.new(bridge, state)
    actions.execute = function()
        applied = true
        error('native action fault')
    end

    local accepted = actions:start('fixture', {}, {})

    assert(events[1].action == accepted.action and events[1].status == 'failed')
    assert(actions.latest.state.applied == true and actions.pending == nil)
end

-- An unlock notice exposes only the card that native animation has revealed.
do
    local state = fixture()
    local card = { ID = 7, states = { visible = false }, no_ui = true, config = { center = {} } }
    local placeholder = { ID = 7, states = { visible = true }, config = { center = {} } }
    G.j_locked = placeholder.config.center
    G.your_collection = { cards = { placeholder, card } }
    G.OVERLAY_MENU = { joker_unlock_table = 7, config = { text = 'Localized unlock criteria' } }
    state.card = function(_, observed)
        assert(observed == card)

        return { name = 'Native Joker', description = 'Native effect' }
    end
    local choices = { { action = 'continue_unlock', enabled = true, ref = 'advance' } }
    state.choices = function()
        return choices
    end

    assert(state:read().notice.revealing == true)
    assert(state:read().notice.card == nil)

    card.states.visible, card.no_ui = true, nil
    local notice = state:read().notice

    assert(notice.card.name == 'Native Joker' and not notice.revealing)
    assert(notice.text == 'Localized unlock criteria' and notice.advance == 'advance')

    choices = {}

    assert(state:read().notice == nil)
end

-- Normal decisions reuse visible native hand statistics, including zero counts.
do
    local state = fixture()
    G.STAGE = G.STAGES.RUN
    G.handlist = { 'Pair', 'High Card', 'Undisplayed' }
    G.GAME.hands = {
        Pair = { visible = true, level = 3, played = 4, chips = 35, mult = 4 },
        ['High Card'] = { visible = true, level = 1, played = 0, chips = 5, mult = 1 },
        Undisplayed = { visible = false, level = 1, played = 0 },
    }
    local observed = state:read()

    assert(#observed.handTypes == 2)
    assert(observed.handTypes[1].name == 'Pair' and observed.handTypes[1].played == 4)
    assert(observed.handTypes[2].level == 1 and observed.handTypes[2].played == 0)
    assert(observed.handTypes[1].chips == 35 and observed.handTypes[1].mult == 4)

    G.GAME.hands.Pair.played = 5

    assert(observed.handTypes[1].played == 4)
    assert(state:read().handTypes[1].played == 5)
end

-- Selection requirements and native eligibility are separate facts, independent of caption.
do
    local state = fixture()
    local allowed = false
    G.hand = { highlighted = {} }
    local card = {
        config = { center = { key = 'c_aura' } },
        base = {},
        ability = { set = 'Spectral', consumeable = {} },
        generate_UIBox_ability_table = function()
            return { name = 'Localized caption', main = 'Native description' }
        end,
        can_use_consumeable = function()
            return allowed
        end,
    }
    local detail = state:card(card)

    assert(detail.targeting.min == 1 and detail.targeting.max == 1)
    assert(detail.targeting.requiresEditionless and detail.targeting.countSatisfied == false)
    assert(detail.useStatus == 'selection_required' and not detail.canUseWithCurrentSelection)

    G.hand.highlighted = { { edition = { foil = true } } }
    detail = state:card(card)

    assert(detail.targeting.countSatisfied and detail.useStatus == 'native_unavailable')

    G.hand.highlighted = { {} }
    allowed = true
    detail = state:card(card)

    assert(detail.useStatus == 'available' and detail.canUseWithCurrentSelection)

    card.config.center.key = 'c_pluto'
    card.ability.consumeable = { hand_type = 'High Card' }
    detail = state:card(card)

    assert(detail.targeting.kind == 'none' and detail.targeting.min == nil)
    assert(detail.useStatus == 'available')

    card.config.center.key = 'c_heirophant'
    card.ability.consumeable = { max_highlighted = 2, mod_num = 2 }
    detail = state:card(card)

    assert(detail.targeting.min == 1 and detail.targeting.max == 2)

    G.hand = nil
    local unknown = state:targeting(card)

    assert(unknown.selectedCount == nil and unknown.countSatisfied == nil)
end

-- Results disclose only a seed already displayed by the native ending panel.
do
    local state = fixture()
    G.STAGE, G.STATE = G.STAGES.RUN, G.STATES.ROUND_EVAL
    G.GAME.pseudorandom = { seed = 'PUBLIC42' }
    G.GAME.hand_usage = {
        trips = { order = 'Three of a Kind', count = 19 },
        pair = { order = 'Pair', count = 4 },
    }
    G.GAME.round_scores.poker_hand = { amt = 0 }
    local seed_row = {
        config = { id = 'seed' },
        children = {
            { config = { text = 'Graine' } },
            { children = { { config = { text = 'PUBLIC42' } } } },
        },
    }
    G.OVERLAY_MENU = { children = { { config = { id = 'from_game_won' } }, seed_row } }
    local result = state:read()

    assert(result.result.seed == 'PUBLIC42' and result.run.seed == 'PUBLIC42')
    assert(result.result.text:find('PUBLIC42', 1, true))
    assert(result.result.scores.poker_hand.hand == 'Three of a Kind')
    assert(result.result.scores.poker_hand.name == 'Three of a Kind')
    assert(result.result.scores.poker_hand.count == 19)
    assert(result.result.scores.hand == 123)

    seed_row.states = { visible = false }
    result = state:read()

    assert(result.result.seed == nil and result.run.seed == nil)
    assert(not result.result.text:find('PUBLIC42', 1, true))

    seed_row.states.visible = true
    G.OVERLAY_MENU.states = { visible = false }
    result = state:read()

    assert(result.result.seed == nil and not result.result.text:find('PUBLIC42', 1, true))

    G.STATE = G.STATES.SELECTING_HAND
    G.OVERLAY_MENU = nil
    result = state:read()

    assert(result.result == nil and result.run.seed == nil)
end

-- No played hand is an actual zero count, while missing native usage data is unknown.
do
    fixture()
    G.STATE = G.STATES.GAME_OVER
    G.GAME.hand_usage = {}
    local empty = Run.results().scores.poker_hand

    assert(empty.count == 0 and empty.hand == nil and empty.name == 'k_none')

    G.GAME.hand_usage = nil

    assert(Run.results().scores.poker_hand == nil)
end

print('Gameplay checks passed')
