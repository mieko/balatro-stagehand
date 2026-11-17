local Bridge = require('balatro_stagehand.bridge')
local Text = require('balatro_stagehand.text')
local Run = require('balatro_stagehand.run')
local Controls = require('balatro_stagehand.controls')
local json = require('dkjson')
local State = {}
State.__index = State

function State.new(native_data)
    return setmetatable(
        { ids = setmetatable({}, { __mode = 'k' }), next_id = 0, native_data = native_data or {} },
        State
    )
end

function State:ref(value)
    if not self.ids[value] then
        self.next_id = self.next_id + 1
        self.ids[value] = 'c' .. self.next_id
    end

    return self.ids[value]
end

function State:forget(card)
    self.ids[card] = nil
end

function State:tooltip(native)
    local effects, traits = Bridge.array(), Bridge.array()

    for _, info in ipairs(native.info or {}) do
        effects[#effects + 1] = { name = Text.read(info.name), description = Text.read(info) }
    end

    for _, badge in ipairs(native.badges or {}) do
        traits[#traits + 1] = badge
    end

    local result = {
        name = Text.read(native.name),
        description = Text.read(native.main),
        effects = effects,
        traits = traits,
    }

    local released = {}
    Text.release(native.name, released)
    Text.release(native.main, released)
    Text.release(native.info, released)

    return result
end

function State:tag(tag)
    local data = tag:get_uibox_table({}).ability_UIBox_table
    local result = self:tooltip(data)
    result.ref = self:ref(tag)

    return result
end

function State:targeting(card)
    local data = card.ability.consumeable
    local minimum, maximum = data.min_highlighted or 1, data.mod_num or data.max_highlighted
    local editionless

    -- Aura's native use guard defines this rule outside the center's config data.
    if card.config.center.key == 'c_aura' then
        minimum, maximum, editionless = 1, 1, true
    end

    if not maximum then
        return { kind = 'none' }
    end

    local count = G.hand and G.hand.highlighted and #G.hand.highlighted
    local count_satisfied

    if count ~= nil then
        count_satisfied = count >= minimum and count <= maximum
    end

    return {
        kind = 'hand_selection',
        min = minimum,
        max = maximum,
        requiresEditionless = editionless,
        selectedCount = count,
        countSatisfied = count_satisfied,
    }
end

function State:card(card, deck_view)
    if not deck_view and (card.facing == 'back' or card.sprite_facing == 'back') then
        return { ref = self:ref(card), hidden = true, highlighted = card.highlighted or false }
    end

    local base, ability, center = card.base or {}, card.ability or {}, card.config.center
    local native = card:generate_UIBox_ability_table()
    local tooltip = self:tooltip(native)
    local discovery_label

    if native.card_type == 'Undiscovered' then
        discovery_label = tooltip.name
        -- A read-only view bypasses onboarding labels without discovering the real card.
        local known = setmetatable({ bypass_lock = true }, { __index = card })
        native = known:generate_UIBox_ability_table()
        tooltip = self:tooltip(native)
    end

    local name = tooltip.name

    if name == '' and native.name == true then
        name = localize({ type = 'name_text', set = ability.set, key = center.key })
    end

    name = Text.clean(name)
    local edition

    if card.edition then
        edition = {}

        for key, value in pairs(card.edition) do
            edition[key] = value
        end
    end

    local result = {
        ref = not deck_view and self:ref(card) or nil,
        name = name,
        discoveryLabel = discovery_label,
        description = tooltip.description,
        type = ability.set,
        effects = tooltip.effects,
        traits = tooltip.traits,
        rank = native.name ~= true and base.value or nil,
        suit = native.name ~= true and base.suit or nil,
        chips = base.value and card:get_chip_bonus() or nil,
        chipsScope = base.value and 'card_bonus_before_edition' or nil,
        enhancement = base.value and center.key ~= 'c_base' and center.key or nil,
        edition = edition,
        seal = card.seal,
        debuffed = card.debuff or false,
        highlighted = card.highlighted or false,
        cost = card.cost,
        sellValue = card.sell_cost,
        pinned = card.pinned or false,
        forcedSelection = ability.forced_selection or false,
        eternal = ability.eternal or false,
        rental = ability.rental or false,
        perishable = ability.perishable or false,
        perishTally = ability.perish_tally,
        rarity = center.rarity,
        canBeCopied = center.blueprint_compat,
        copyCompatibility = ability.blueprint_compat,
        rarityName = self.native_data.rarityKeys
                and self.native_data.rarityKeys[center.rarity]
                and localize(self.native_data.rarityKeys[center.rarity])
            or nil,
    }

    if not deck_view then
        if card.can_sell_card and (card.area == G.jokers or card.area == G.consumeables) then
            result.canSell = not not card:can_sell_card()
        end

        if ability.consumeable and card.can_use_consumeable then
            result.canUseWithCurrentSelection = not not card:can_use_consumeable()
            result.targeting = self:targeting(card)
            result.useStatus = result.canUseWithCurrentSelection and 'available'
                or result.targeting.countSatisfied == false and 'selection_required'
                or 'native_unavailable'
        end
    end

    return result
end

function State:deck(remaining)
    local cards = Bridge.array()

    if G.STAGE ~= G.STAGES.RUN then
        return { cards = cards }
    end

    for _, card in ipairs(G.playing_cards or {}) do
        if not remaining or card.area == G.deck or card.ability.wheel_flipped then
            local detail = self:card(card, true)
            detail.highlighted, detail.cost, detail.sellValue = nil, nil, nil
            detail.forcedSelection, detail.debuffed = nil, nil
            cards[#cards + 1] = detail
        end
    end
    -- Public attributes only: neither draw order nor hidden copy identity survives.
    table.sort(cards, function(a, b)
        return json.encode(a, { keyorder = { 'suit', 'rank', 'name', 'description' } })
            < json.encode(b, { keyorder = { 'suit', 'rank', 'name', 'description' } })
    end)

    return {
        cards = cards,
        count = #cards,
        remaining = remaining or false,
        scope = remaining and 'native_unplayed_with_facedown_ambiguity' or 'full_deck_unordered',
    }
end

function State:cards(area)
    local cards = Bridge.array()

    for _, card in ipairs(area and area.cards or {}) do
        cards[#cards + 1] = self:card(card)
    end

    return cards
end

function State:visible_areas()
    local areas = { G.hand, G.jokers, G.consumeables }

    if G.STATE == G.STATES.SHOP and G.shop and G.shop.stagehand_offers_ready then
        areas[#areas + 1] = G.shop_jokers
        areas[#areas + 1] = G.shop_vouchers
        areas[#areas + 1] = G.shop_booster
    end

    if self:is_pack() then
        areas[#areas + 1] = G.pack_cards
    end

    return areas
end

function State:find_card(reference)
    for _, area in pairs(self:visible_areas()) do
        for _, card in ipairs(area.cards or {}) do
            if self:ref(card) == reference then
                return card
            end
        end
    end

    Bridge.fail(Bridge.INVALID_PARAMS, 'Card reference is stale or not currently inspectable')
end

function State:inspect_card(reference)
    local card = self:find_card(reference)

    if card.facing == 'back' or card.sprite_facing == 'back' then
        Bridge.fail(Bridge.INVALID_PARAMS, 'This card is face down')
    end

    return self:card(card)
end

function State:is_pack()
    for _, name in ipairs({
        'TAROT_PACK',
        'SPECTRAL_PACK',
        'PLANET_PACK',
        'STANDARD_PACK',
        'BUFFOON_PACK',
    }) do
        if G.STATE == G.STATES[name] then
            return true
        end
    end

    return false
end

function State:blinds()
    local blinds = Bridge.array()

    if G.STAGE ~= G.STAGES.RUN then
        return blinds
    end

    local resets = G.GAME.round_resets

    if not resets then
        return blinds
    end

    for slot, key in pairs(resets.blind_choices or {}) do
        local definition = G.P_BLINDS[key]
        local pane

        if G.STATE == G.STATES.BLIND_SELECT and G.blind_select_opts then
            pane = G.blind_select_opts[slot:lower()]
        end

        local vars = { localize(G.GAME.current_round.most_played_poker_hand, 'poker_hands') }
        local lines = localize({ type = 'raw_descriptions', key = key, set = 'Blind', vars = vars })
        local button = pane and pane:get_UIE_by_ID('select_blind_button')
        local reward = pane and pane:get_UIE_by_ID('tag_container')
        local skip = Controls.find(pane, 'button', 'skip_blind')
        local reroll = slot == 'Boss'
                and Controls.find(G.blind_prompt_box, 'func', 'reroll_boss_button')
            or nil
        blinds[#blinds + 1] = {
            slot = slot,
            name = localize({ type = 'name_text', key = key, set = 'Blind' }),
            description = pane and Text.read(pane:get_UIE_by_ID('blind_desc'))
                or table.concat(lines or {}, ' '),
            display = pane and Text.read(pane),
            state = resets.blind_states[slot],
            baseReward = definition.dollars,
            selectable = not not (
                    button
                    and button.config.button
                    and not button.under_overlay
                    and not button.disable_button
                    and button.states.visible
                ),
            scope = pane and 'visible_ui' or 'current_ante_definition',
            skipReward = reward and self:tag(reward.config.ref_table),
            canSkip = not not (
                    skip
                    and skip.states.visible
                    and not skip.under_overlay
                    and not skip.disable_button
                ),
            canReroll = not not (
                    reroll
                    and reroll.config.button == 'reroll_boss'
                    and reroll.states.visible
                    and not reroll.under_overlay
                    and not reroll.disable_button
                ),
        }
    end

    table.sort(blinds, function(a, b)
        return a.slot < b.slot
    end)

    return blinds
end

function State:hand_types()
    local hands = Bridge.array()

    for _, key in ipairs(G.handlist) do
        local hand = G.GAME.hands[key]

        if hand.visible then
            hands[#hands + 1] = {
                name = localize(key, 'poker_hands'),
                description = localize(key, 'poker_hand_descriptions'),
                level = hand.level,
                chips = hand.chips,
                mult = hand.mult,
                played = hand.played,
            }
        end
    end

    return hands
end

function State:choices()
    local choices, seen = Bridge.array(), {}
    self.buttons = {}
    local function visit(node)
        if type(node) ~= 'table' or seen[node] then
            return
        end

        seen[node] = true

        if node.states and node.states.visible == false then
            return
        end

        if node.config and node.config.button and node.click then
            local ref = self:ref(node)
            self.buttons[ref] = node
            choices[#choices + 1] = {
                ref = ref,
                label = Text.read(node),
                action = node.config.button,
                enabled = not node.disable_button and not node.under_overlay,
            }
        end

        for _, child in pairs(node.children or {}) do
            visit(child)
        end

        visit(node.UIRoot)
    end

    visit(G.OVERLAY_MENU or G.OVERLAY_TUTORIAL or G.MAIN_MENU_UI)

    if G.OVERLAY_TUTORIAL and not G.OVERLAY_MENU then
        visit(G.OVERLAY_TUTORIAL.Jimbo)
        visit(G.OVERLAY_TUTORIAL.content)
    end

    table.sort(choices, function(a, b)
        return a.ref < b.ref
    end)

    return choices
end

function State:notice(choices)
    if not G.OVERLAY_MENU then
        return nil
    end

    for _, choice in ipairs(choices or self:choices()) do
        if choice.action == 'continue_unlock' then
            local notice =
                { kind = 'unlock', text = Text.read(G.OVERLAY_MENU), advance = choice.ref }
            local identity = G.OVERLAY_MENU.joker_unlock_table

            if identity then
                notice.revealing = true

                for _, card in ipairs(G.your_collection and G.your_collection.cards or {}) do
                    local center = card.config and card.config.center

                    if
                        card.ID == identity
                        and card.states.visible
                        and not card.no_ui
                        and center ~= G.j_locked
                        and center ~= G.v_locked
                    then
                        notice.card = self:card(card)
                        notice.revealing = nil
                        break
                    end
                end
            end

            return notice
        end
    end
end

function State:kind()
    if Run.is_win() then
        return 'WIN'
    end

    for name, value in pairs(G.STATES) do
        if value == G.STATE then
            return name
        end
    end

    return 'UNKNOWN'
end

function State:cash_out_button()
    for _, box in ipairs(G.I.UIBOX) do
        local button = box:get_UIE_by_ID('cash_out_button')

        if
            button
            and button.config.button == 'cash_out'
            and button.states.visible
            and not button.disable_button
            and not button.under_overlay
        then
            return button
        end
    end
end

function State:ready()
    if G.screenwipe then
        return false
    end

    if G.OVERLAY_TUTORIAL and not G.OVERLAY_TUTORIAL.step_complete then
        return false
    end

    if G.OVERLAY_TUTORIAL or G.OVERLAY_MENU then
        for _, choice in ipairs(self:choices()) do
            if choice.enabled then
                return true
            end
        end

        return false
    end

    if G.CONTROLLER.locked then
        return false
    end

    if G.GAME.STOP_USE and G.GAME.STOP_USE > 0 then
        return false
    end

    if G.TAROT_INTERRUPT then
        return false
    end

    for _, event in ipairs(G.E_MANAGER and G.E_MANAGER.queues.base or {}) do
        if event.blocking and not event.complete then
            return false
        end
    end

    for _, area in pairs(self:visible_areas()) do
        for _, card in ipairs(area.cards or {}) do
            if card.facing and card.sprite_facing and card.facing ~= card.sprite_facing then
                return false
            end
        end
    end

    if G.STATE == G.STATES.MENU then
        return G.MAIN_MENU_UI and G.MAIN_MENU_UI.states.visible
    end

    if G.STATE == G.STATES.SELECTING_HAND then
        return G.buttons ~= nil
    end

    if G.STATE == G.STATES.BLIND_SELECT then
        local key = G.GAME.blind_on_deck
        local pane = key and G.blind_select_opts and G.blind_select_opts[key:lower()]

        return pane and pane:get_UIE_by_ID('select_blind_button') ~= nil or false
    end

    if G.STATE == G.STATES.SHOP then
        if not G.shop or not G.shop.stagehand_offers_ready then
            return false
        end

        for _, area in ipairs({ G.shop_jokers, G.shop_vouchers, G.shop_booster }) do
            for _, card in ipairs(area.cards) do
                if not card.children.buy_button and not card.opening then
                    return false
                end
            end
        end

        return true
    end

    if self:is_pack() then
        return G.pack_cards and G.pack_cards.cards and #G.pack_cards.cards > 0 and G.STATE_COMPLETE
            or false
    end

    if G.STATE == G.STATES.ROUND_EVAL then
        return self:cash_out_button() ~= nil
    end

    return false
end

function State:read()
    local game, round = G.GAME, G.GAME.current_round or {}
    local in_run = G.STAGE == G.STAGES.RUN
    local result = { kind = self:kind(), ready = not not self:ready(), choices = self:choices() }
    result.notice = self:notice(result.choices)
    result.ui = {
        inputLocked = G.CONTROLLER.locked or false,
        overlay = not not G.OVERLAY_MENU,
        tutorial = not not G.OVERLAY_TUTORIAL,
        menu = not not G.MAIN_MENU_UI,
    }

    if G.OVERLAY_TUTORIAL and G.OVERLAY_TUTORIAL.Jimbo then
        local bubble = G.OVERLAY_TUTORIAL.Jimbo.children.speech_bubble

        if bubble and bubble.states.visible then
            result.dialogue = Text.read(bubble)
        end

        if G.OVERLAY_TUTORIAL.button_listen then
            result.tutorial = { waitingFor = G.OVERLAY_TUTORIAL.button_listen }
        end
    end

    if not in_run then
        return result
    end

    result.ante = game.round_resets.ante

    if G.P_CENTER_POOLS then
        result.run = Run.context()
    end

    result.round = game.round
    result.money = game.dollars
    result.bankruptAt = game.bankrupt_at
    result.handSize = G.hand and G.hand.config.card_limit

    if G.handlist and game.hands then
        result.handTypes = self:hand_types()
    end

    result.score = game.chips
    result.handsLeft = round.hands_left
    result.discardsLeft = round.discards_left
    result.preview = round.current_hand
        and {
            name = round.current_hand.handname,
            chips = round.current_hand.chips,
            mult = round.current_hand.mult,
            level = round.current_hand.hand_level,
            rejectedByBlind = G.boss_throw_hand or false,
            scope = 'native_hand_type_preview',
        }
    result.result = Run.results()
    result.hand = self:cards(G.hand)
    result.jokers = self:cards(G.jokers)
    result.consumables = self:cards(G.consumeables)
    result.tags = Bridge.array()

    for _, tag in ipairs(game.tags or {}) do
        result.tags[#result.tags + 1] = self:tag(tag)
    end

    result.deckCount = G.deck and #G.deck.cards or 0
    result.discardCount = G.discard and #G.discard.cards or 0

    if game.blind and game.blind.config.blind and next(game.blind.config.blind) then
        local description = game.blind.loc_debuff_text

        if type(description) == 'table' then
            description = table.concat(description, ' ')
        end

        result.blind = {
            name = game.blind.loc_name or game.blind.name,
            target = game.blind.chips,
            description = description,
            disabled = game.blind.disabled or false,
        }
    end

    if G.STATE == G.STATES.SHOP then
        result.shop = {
            cards = self:cards(G.shop_jokers),
            packs = self:cards(G.shop_booster),
            vouchers = self:cards(G.shop_vouchers),
            rerollCost = round.reroll_cost,
        }
    end

    if G.STATE == G.STATES.BLIND_SELECT then
        result.blinds = self:blinds()
    end

    if self:is_pack() then
        result.pack = { choicesLeft = game.pack_choices, cards = self:cards(G.pack_cards) }
    end

    result.slots = {
        jokers = G.jokers and G.jokers.config.card_limit,
        consumables = G.consumeables and G.consumeables.config.card_limit,
    }

    result.vouchers = Bridge.array()

    for key in pairs(game.used_vouchers or {}) do
        local definition = G.P_CENTERS[key]

        if definition then
            local tooltip = self:tooltip(generate_card_ui(definition))
            tooltip.id = key
            result.vouchers[#result.vouchers + 1] = tooltip
        end
    end

    table.sort(result.vouchers, function(a, b)
        return a.id < b.id
    end)
    result.counters = {
        handsPlayed = game.hands_played,
        cardsDiscarded = game.round_scores
            and game.round_scores.cards_discarded
            and game.round_scores.cards_discarded.amt,
        roundHandsPlayed = round.hands_played,
        roundDiscardsUsed = round.discards_used,
        skips = game.skips,
        unusedDiscards = game.unused_discards,
    }

    return result
end

return State
