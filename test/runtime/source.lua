local function load_native(name)
    assert(love.filesystem.load('native/' .. name .. '.lua'))()
end

load_native('engine/object')
Moveable = Object:extend()
load_native('game')
load_native('card')
load_native('cardarea')
load_native('engine/ui')
load_native('functions/misc_functions')
local native_localize = localize

local function check_scripted_joker()
    local Script = require('balatro_stagehand.love_script')
    local center = G.P_CENTERS.j_card_sharp
    local joker = setmetatable({
        T = { x = 0, y = 0, w = 1, h = 1 },
        config = { card = {} },
        params = {},
        set_sprites = function() end,
    }, Card)
    G.GAME.used_jokers = {}
    joker:set_ability(center, true)
    G.jokers.cards = { joker }
    G.GAME.hands = { Pair = { played_this_round = 2 } }
    local context = { joker_main = true, cardarea = G.jokers, scoring_name = 'Pair' }
    assert(joker:calculate_joker(context).Xmult_mod == 3)

    local result = Script.evaluate({
        source = [[
function evaluate(bindings)
    local joker = G.jokers.cards[1]
    joker.ability.extra.Xmult = bindings.multiplier
    return joker.ability.extra.Xmult
end
]],
        bindings = { multiplier = 5 },
    })
    assert(result == 5)
    assert(joker:calculate_joker(context).Xmult_mod == 5)
    print('NATIVE_SCRIPTED_JOKER_OK')
end

local function check_tooltip_lifetimes()
    local state = require('balatro_stagehand.state').new()
    local created, active = 0, {}
    local original_text = DynaText
    DynaText = function(config)
        local object = { config = config, string = config.string[1] }
        created = created + 1
        active[object] = true

        function object:remove()
            assert(active[self], 'Temporary tooltip objects must be released exactly once')
            active[self] = nil
        end

        return object
    end

    G.LANG = { font = { DESCSCALE = 1 } }
    G.UIT = { O = 1 }
    G.C.UI.TEXT_LIGHT = {}
    G.localization = {
        descriptions = {
            Joker = {
                j_joker = {
                    name_parsed = { loc_parse_string(G.P_CENTERS.j_joker.name) },
                },
            },
        },
    }

    for _ = 1, 1000 do
        local title = native_localize({ type = 'name', set = 'Joker', key = 'j_joker' })
        local tooltip = state:tooltip({ name = title, main = 'Native description' })
        assert(tooltip.name == G.P_CENTERS.j_joker.name)
    end

    local retained = 0
    for _ in pairs(active) do
        retained = retained + 1
    end
    assert(created == 1000)
    assert(retained == 0, 'Tooltip name objects retained after 1000 reads: ' .. retained)
    DynaText = original_text
    print('NATIVE_TOOLTIP_LIFETIME_OK ' .. created)
end

local function fixture_filesystem()
    love.filesystem.getInfo = function()
        return true
    end

    love.filesystem.createDirectory = function()
        error('Fixture must not write saves')
    end

    love.filesystem.append = function()
        error('Fixture must not write saves')
    end

    love.filesystem.write = function()
        error('Fixture must not write saves')
    end

    love.filesystem.remove = function()
        error('Fixture must not remove saves')
    end

    convert_save_to_meta = function() end
    get_compressed = function()
        return nil
    end

    STR_UNPACK = function()
        return {}
    end
end

local function fixture_game()
    G = setmetatable({
        SETTINGS = { profile = 1, tutorial_complete = true },
        FUNCS = {},
        save_progress = function() end,
    }, Game)
    localize = function(key)
        return key
    end

    G:init_item_prototypes()
    load_native('functions/button_callbacks')
    G.STATES = {
        SELECTING_HAND = 1,
        HAND_PLAYED = 2,
        DRAW_TO_HAND = 3,
        PLAY_TAROT = 4,
        TAROT_PACK = 5,
        SPECTRAL_PACK = 6,
        PLANET_PACK = 7,
        STANDARD_PACK = 8,
        BUFFOON_PACK = 9,
    }

    G.STATE = G.STATES.SELECTING_HAND
    G.STAGES, G.STAGE = { RUN = 2 }, 2
    G.CONTROLLER = { locked = false }
    G.C = { UI = { BACKGROUND_INACTIVE = {} }, RED = {}, GREEN = {} }
    G.GAME = { STOP_USE = 0, pseudorandom = { seed = 'FIXTURE' }, current_round = {} }
    G.hand = { cards = { {}, {}, {} }, highlighted = {}, config = { highlighted_limit = 5 } }
    G.play = { cards = {} }
    G.jokers = { cards = {}, config = { card_limit = 5 } }
    G.consumeables = { cards = {}, config = { card_limit = 2 } }
end

local function check_discovery_projection()
    local State = require('balatro_stagehand.state')
    local state = State.new()
    local calls = 0

    -- The installed Card owns discovery gating and dynamic tooltip arguments.
    generate_card_ui = function(center, _, vars, card_type, _, hide_desc)
        calls = calls + 1

        return {
            card_type = card_type,
            name = card_type == 'Undiscovered' and 'Non découvert'
                or card_type == 'Locked' and 'Locked'
                or center.name,
            main = hide_desc and 'Discovery instructions'
                or vars and vars[1] and '+' .. vars[1] .. ' Mult'
                or center.set .. ' native description',
        }
    end

    for _, key in ipairs({
        'j_joker',
        'v_blank',
        'p_buffoon_normal_1',
        'p_arcana_normal_1',
        'p_celestial_normal_1',
        'p_spectral_normal_1',
        'p_standard_normal_1',
        'c_tower',
        'c_pluto',
        'c_immolate',
        'e_foil',
    }) do
        local center = assert(G.P_CENTERS[key], key)
        center.unlocked, center.discovered = true, false
        local ability = copy_table(center.config)
        ability.name, ability.set = center.name, center.set
        ability.consumeable = center.consumeable and copy_table(center.config) or nil

        if ability.consumeable and ability.consumeable.max_highlighted then
            ability.consumeable.mod_num = math.min(5, ability.consumeable.max_highlighted)
        end

        local card = setmetatable({
            config = { center = center },
            base = {},
            ability = ability,
            facing = 'front',
        }, Card)
        local detail = state:card(card)

        assert(detail.name == center.name, key .. ': expected normal native name')
        assert(detail.description ~= 'Discovery instructions')
        assert(detail.discoveryLabel == 'Non découvert', key)
        assert(center.discovered == false and rawget(card, 'bypass_lock') == nil)
        assert(rawget(card, 'bypass_discovery_ui') == nil)

        if key == 'j_joker' then
            assert(detail.description == '+4 Mult')
        end

        card.facing = 'back'
        local before = calls
        local hidden = state:card(card)

        assert(hidden.hidden and hidden.name == nil and hidden.discoveryLabel == nil)
        assert(calls == before, 'Face-down items must not generate an identifying tooltip')

        card.facing = 'front'
        center.unlocked = false
        local locked = state:card(card)

        assert(locked.name == 'Locked' and locked.discoveryLabel == nil)
    end

    print('NATIVE_DISCOVERY_OK')
end

local function check_chip_scope()
    local state = require('balatro_stagehand.state').new()
    local cases = {
        { nominal = 7, bonus = 30, expected = 37 },
        { nominal = 9, bonus = 0, edition = { foil = true, chips = 50 }, expected = 9 },
        { nominal = 7, bonus = 50, permanent = 10, effect = 'Stone Card', expected = 60 },
        { nominal = 7, bonus = 30, debuffed = true, expected = 0 },
    }
    for _, case in ipairs(cases) do
        local card = setmetatable({
            config = { center = G.P_CENTERS.c_base },
            base = { value = tostring(case.nominal), nominal = case.nominal },
            ability = {
                set = 'Enhanced',
                bonus = case.bonus,
                perma_bonus = case.permanent,
                effect = case.effect,
            },
            edition = case.edition,
            debuff = case.debuffed,
            generate_UIBox_ability_table = function()
                return { name = 'Native playing card', main = 'Native description' }
            end,
        }, Card)
        local detail = state:card(card)

        assert(detail.chips == case.expected)
        assert(detail.chipsScope == 'card_bonus_before_edition')
        assert((not case.edition) or detail.edition.chips == 50)
    end
    print('NATIVE_CHIP_SCOPE_OK')
end

local function check_aura_targeting()
    local center = G.P_CENTERS.c_aura
    local card = setmetatable({
        config = { center = center },
        ability = { name = center.name, consumeable = center.config },
    }, Card)
    local state = require('balatro_stagehand.state').new()
    G.hand.highlighted = {}

    assert(not card:can_use_consumeable())
    assert(state:targeting(card).countSatisfied == false)

    G.hand.highlighted = { {} }

    assert(card:can_use_consumeable())
    assert(state:targeting(card).countSatisfied)

    G.hand.highlighted = { { edition = { foil = true } } }

    assert(not card:can_use_consumeable())
    assert(state:targeting(card).countSatisfied and state:targeting(card).requiresEditionless)
    print('NATIVE_TARGETING_OK')
end

local function check_native_results()
    load_native('functions/UI_definitions')
    local original_text, original_localize = DynaText, localize
    DynaText = function(config)
        return { config = config, string = config.string[1] }
    end
    localize = function(key, group)
        return group == 'poker_hands' and 'localized:' .. key or key
    end
    G.UIT = { R = 1, C = 2, O = 3, T = 4 }
    G.C.JOKER_GREY, G.C.WHITE = { 0.5, 0.5, 0.5, 1 }, { 1, 1, 1, 1 }
    G.GAME.pseudorandom.seed = 'PUBLIC42'
    G.GAME.round, G.GAME.round_resets = 23, { ante = 9 }
    G.GAME.round_scores = { hand = { amt = 485652 }, poker_hand = { amt = 0 } }
    G.GAME.hand_usage = {
        trips = { order = 'Three of a Kind', count = 19 },
        pair = { order = 'Pair', count = 4 },
    }
    local function attach_children(node)
        node.children = node.nodes
        for _, child in ipairs(node.children or {}) do
            attach_children(child)
        end
        return node
    end
    local seed = attach_children(create_UIBox_round_scores_row('seed'))
    local poker = attach_children(create_UIBox_round_scores_row('poker_hand'))
    G.OVERLAY_MENU = { children = { { config = { id = 'from_game_won' } }, seed, poker } }
    local Run = require('balatro_stagehand.run')
    local Text = require('balatro_stagehand.text')
    local result = Run.results()

    assert(result.seed == 'PUBLIC42' and result.text:find(Text.read(seed), 1, true))
    assert(result.scores.poker_hand.hand == 'Three of a Kind')
    assert(result.scores.poker_hand.name == 'localized:Three of a Kind')
    assert(result.scores.poker_hand.count == 19)
    assert(Text.read(poker):find(result.scores.poker_hand.name, 1, true))
    assert(Text.read(poker):find('(19)', 1, true))
    assert(result.scores.hand == 485652)

    -- Native ties retain the same pair iteration choice as the actual UI builder.
    G.GAME.hand_usage.pair.count = 19
    poker = attach_children(create_UIBox_round_scores_row('poker_hand'))
    G.OVERLAY_MENU.children[3] = poker
    result = Run.results()

    assert(Text.read(poker):find(result.scores.poker_hand.name, 1, true))
    DynaText, localize = original_text, original_localize
    print('NATIVE_RESULTS_OK')
end

local function face_down_card(key, unique_val)
    local card = setmetatable({
        config = {},
        ability = {},
        unique_val = unique_val,
        facing = 'back',
        set_sprites = function() end,
    }, Card)
    card:set_base(G.P_CARDS[key], true)

    return card
end

local function check_native_sort()
    local State = require('balatro_stagehand.state')
    local Actions = require('balatro_stagehand.actions')
    local state = State.new()
    local bridge = { instance = 'sort-fixture', tick = 0, results = {} }

    function bridge:emit(_, _, value)
        self.results[#self.results + 1] = value
    end

    state.choices = function()
        return {}
    end
    state.ready = function()
        return not G.CONTROLLER.locked
    end
    state.read = function()
        return { hand = state:cards(G.hand) }
    end
    G.TIMERS = { REAL = 1 }
    G.C.SUITS = {}
    local first, second = face_down_card('S_2', 1), face_down_card('H_A', 2)
    first.highlighted = true
    G.hand =
        setmetatable({ cards = { first, second }, config = {}, highlighted = { first } }, CardArea)
    local nodes, clicks = {}, 0

    for _, callback in ipairs({ 'sort_hand_value', 'sort_hand_suit' }) do
        local node = { config = { button = callback }, states = { visible = true } }

        function node:click()
            clicks = clicks + 1
            G.FUNCS[self.config.button](self)
        end

        nodes[#nodes + 1] = node
    end

    G.buttons = { UIRoot = { children = nodes } }
    play_sound = function() end
    local actions = Actions.new(bridge, state)
    local first_ref, second_ref = state:ref(first), state:ref(second)

    for _, example in ipairs({
        { by = 'rank', first = second_ref, second = first_ref },
        { by = 'suit', first = first_ref, second = second_ref },
        { by = 'suit', first = first_ref, second = second_ref },
    }) do
        local accepted = actions:start('sortHand', { by = example.by }, {})
        assert(actions.pending, actions.latest and actions.latest.error)
        bridge.tick = bridge.tick + 2
        actions:update()
        local result = actions.latest

        assert(result.action == accepted.action and result.status == 'completed', result.error)
        assert(result.state.hand[1].ref == example.first)
        assert(result.state.hand[2].ref == example.second)

        for _, card in ipairs(result.state.hand) do
            assert(card.hidden and card.rank == nil and card.suit == nil and card.name == nil)
        end

        assert(G.hand.highlighted[1] == first and first.highlighted)
    end

    assert(clicks == 3)
    actions:start('sortHand', { by = 'hidden-rank' }, {})
    assert(actions.latest.status == 'failed' and clicks == 3)
    nodes[1].states.visible = false
    actions:start('sortHand', { by = 'rank' }, {})
    assert(actions.latest.status == 'failed' and clicks == 3)
    G.CONTROLLER.locked = true
    actions:start('sortHand', { by = 'suit' }, {})
    assert(actions.latest.status == 'failed' and clicks == 3)

    print('NATIVE_SORT_OK')
end

local function check_native_tree()
    local Tree = require('balatro_stagehand.scene_tree')
    local state = require('balatro_stagehand.state').new()
    local label = setmetatable({
        config = { text = 'Native UI control' },
        children = {},
        states = { visible = true },
    }, UIElement)
    local button = setmetatable({
        config = { id = 'native-tree', button = 'tree_fixture' },
        children = { label },
        states = { visible = true },
    }, UIElement)
    local box = setmetatable({ UIRoot = button, states = { visible = true } }, UIBox)
    label.parent, button.parent = button, box
    G.I = { UIBOX = { box } }
    G.ROOM, G.TIMERS = { jiggle = 0 }, { REAL = 2 }
    local clicked = 0
    G.FUNCS.tree_fixture = function(control)
        assert(control == button)
        clicked = clicked + 1
    end
    play_sound = function() end
    local tree = Tree.new(state)
    local found = tree:query({ id = 'native-tree' }).nodes

    assert(#found == 1 and found[1].class == 'UIElement' and found[1].enabled)
    assert(#tree:query({ class = 'Moveable', id = 'native-tree' }).nodes == 1)
    assert(tree:query({ text = 'Native UI control' }).nodes[1].parent == found[1].node)
    assert(tree:click({ node = found[1].node }).clicked)
    assert(clicked == 1 and button.last_clicked == 2)
    assert(not pcall(tree.click, tree, { node = found[1].node }) and clicked == 1)
    G.I.UIBOX = {}
    assert(not pcall(tree.inspect, tree, { node = found[1].node }))

    print('NATIVE_TREE_OK')
end

function love.load()
    fixture_filesystem()
    fixture_game()

    for _, name in ipairs({
        'bridge',
        'controls',
        'layout',
        'card_action',
        'commerce',
        'actions',
        'text',
        'run',
        'state',
        'scene_tree',
        'love_script',
    }) do
        package.preload['balatro_stagehand.' .. name] =
            assert(love.filesystem.load('mod/' .. name .. '.lua'))
    end

    package.preload['balatro_stagehand.transport'] = function()
        return {}
    end

    package.preload.dkjson = assert(love.filesystem.load('mod/vendor/dkjson.lua'))
    check_tooltip_lifetimes()
    fixture_game()
    check_native_sort()
    fixture_game()
    check_native_tree()
    fixture_game()
    check_discovery_projection()
    check_chip_scope()
    check_aura_targeting()
    check_native_results()
    fixture_game()
    check_scripted_joker()
    fixture_game()
    local CardAction = require('balatro_stagehand.card_action')
    local checks = 0
    local original_random = math.random
    math.random = function()
        error('Eligibility must not consume RNG')
    end

    for _, center in ipairs(G.P_CENTER_POOLS.Consumeables) do
        for _, phase in ipairs({ 'SELECTING_HAND', 'TAROT_PACK', 'SPECTRAL_PACK', 'PLANET_PACK' }) do
            G.STATE = G.STATES[phase]

            for selected = 0, 5 do
                G.hand.highlighted = {}

                for index = 1, selected do
                    G.hand.highlighted[index] = {}
                end

                local card = setmetatable({
                    area = G.consumeables,
                    config = { center = center },
                    highlighted = true,
                    ability = {
                        name = center.name,
                        set = center.set,
                        consumeable = center.config,
                        extra = copy_table(center.config.extra),
                    },
                    states = { focus = { is = false } },
                    update_alert = function() end,
                    eligible_strength_jokers = {},
                    eligible_editionless_jokers = {},
                    children = {},
                }, Card)
                card:update(0)
                local allowed = not not card:can_use_consumeable()
                local targeting = require('balatro_stagehand.state').new():targeting(card)
                local configured = card.ability.consumeable

                if configured.max_highlighted then
                    assert(targeting.kind == 'hand_selection', center.key)
                    assert(targeting.min == (configured.min_highlighted or 1), center.key)
                    assert(targeting.max == configured.mod_num, center.key)
                    assert(
                        targeting.countSatisfied
                            == (selected >= targeting.min and selected <= targeting.max),
                        center.key
                    )
                elseif center.key == 'c_aura' then
                    assert(
                        targeting.kind == 'hand_selection'
                            and targeting.min == 1
                            and targeting.max == 1
                    )
                    assert(
                        targeting.requiresEditionless
                            and targeting.countSatisfied == (selected == 1)
                    )
                else
                    assert(targeting.kind == 'none', center.key)
                end

                local used = 0
                local button = {
                    config = { ref_table = card, func = 'can_use_consumeable' },
                    states = { visible = true },
                }

                function button:click()
                    used = used + 1
                    card.area = nil
                end

                card.children.use_button = { UIRoot = button }
                local state = {
                    find_card = function()
                        return card
                    end,
                    card = function()
                        return {}
                    end,
                    is_pack = function()
                        return false
                    end,
                }

                local family = CardAction.new(state)
                local job = family:begin('useConsumable', { ref = 'fixture' })
                local status = family:update(job)

                assert(used == (allowed and 1 or 0), center.key)
                assert(status == (not allowed and 'choice_required' or nil), center.key)

                if allowed then
                    assert(family:update(job) == 'completed', center.key)
                end

                checks = checks + 1
            end
        end
    end

    -- The native final guard can refuse a use that its ordinary validator admits.
    G.STATE = G.STATES.SELECTING_HAND
    G.jokers.cards = { { ability = { set = 'Joker' } }, { ability = { set = 'Joker' } } }
    G.jokers.config.card_limit = 2
    local alerts, used = 0, 0
    alert_no_space = function()
        alerts = alerts + 1
    end

    local center = G.P_CENTERS.c_ankh
    local card = setmetatable({
        area = G.consumeables,
        highlighted = true,
        ability = { name = center.name, set = center.set, consumeable = center.config },
        children = {},
    }, Card)

    assert(card:can_use_consumeable())

    local button = {
        config = { ref_table = card, func = 'can_use_consumeable' },
        states = { visible = true },
    }

    function button:click()
        used = used + 1
    end

    card.children.use_button = { UIRoot = button }
    local family = CardAction.new({
        find_card = function()
            return card
        end,
        card = function()
            return {}
        end,
        is_pack = function()
            return false
        end,
    })
    local job = family:begin('useConsumable', { ref = 'fixture' })

    assert(family:update(job) == 'choice_required')
    assert(used == 0 and alerts == 1 and card.area == G.consumeables)

    math.random = original_random
    print('NATIVE_MODELS_OK ' .. #G.P_CENTER_POOLS.Consumeables .. ' ' .. checks)
    io.stdout:flush()
    love.event.quit()
end
