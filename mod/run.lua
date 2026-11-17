local Bridge = require('balatro_stagehand.bridge')
local Text = require('balatro_stagehand.text')
local Controls = require('balatro_stagehand.controls')
local Run = {}

function Run.is_win()
    return Controls.find(G.OVERLAY_MENU, 'id', 'from_game_won') ~= nil
end

function Run.stakes(deck)
    local profile = G.PROFILES[G.SETTINGS.profile]
    local maximum = profile.all_unlocked and #G.P_CENTER_POOLS.Stake
        or math.min((get_deck_win_stake(deck.key) or 0) + 1, #G.P_CENTER_POOLS.Stake)
    local stakes = Bridge.array()

    for index, stake in ipairs(G.P_CENTER_POOLS.Stake) do
        stakes[#stakes + 1] = {
            id = index,
            key = stake.key,
            name = localize({ type = 'name_text', set = 'Stake', key = stake.key }),
            description = Text.read(G.UIDEF.stake_description(index)),
            unlocked = deck.unlocked and index <= maximum or false,
        }
    end

    return stakes
end

function Run.options()
    local decks, challenges = Bridge.array(), Bridge.array()
    local profile = G.PROFILES[G.SETTINGS.profile]

    for _, center in ipairs(G.P_CENTER_POOLS.Back) do
        local back = Back(center)
        decks[#decks + 1] = {
            id = center.key,
            name = back:get_name(),
            description = Text.read(back:generate_UI()),
            unlocked = center.unlocked or false,
            stakes = Run.stakes(center),
        }
    end

    for index, challenge in ipairs(G.CHALLENGES) do
        local unlocked = profile.all_unlocked or index <= (profile.challenges_unlocked or 0)
        challenges[#challenges + 1] = {
            id = unlocked and challenge.id or nil,
            name = unlocked and localize(challenge.id, 'challenge_names') or localize('k_locked'),
            unlocked = unlocked or false,
            completed = profile.challenge_progress.completed[challenge.id] or false,
            rules = unlocked
                    and Text.read(
                        G.UIDEF.challenge_description_tab({ _id = index, _tab = 'Rules' })
                    )
                or nil,
        }
    end

    return {
        decks = decks,
        challenges = challenges,
        canContinue = love.filesystem.getInfo(G.SETTINGS.profile .. '/save.jkr') ~= nil,
    }
end

function Run.validate(params)
    if params.challenge then
        if params.deck or params.stake or params.seed then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Challenges use their native deck and White Stake')
        end

        local profile = G.PROFILES[G.SETTINGS.profile]

        for index, challenge in ipairs(G.CHALLENGES) do
            if
                challenge.id == params.challenge
                and (profile.all_unlocked or index <= (profile.challenges_unlocked or 0))
            then
                return { stake = 1, challenge = challenge }
            end
        end

        Bridge.fail(Bridge.INVALID_PARAMS, 'Choose an unlocked challenge')
    end

    local center = G.P_CENTERS[params.deck or 'b_red']
    local playable = false

    for _, back in ipairs(G.P_CENTER_POOLS.Back) do
        if back == center then
            playable = true
        end
    end

    if not center or not playable or not center.unlocked then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Choose an unlocked deck')
    end

    local stake = params.stake or 1
    local option = Run.stakes(center)[stake]

    if not option or not option.unlocked then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Choose a stake unlocked for this deck')
    end

    local seed = params.seed

    if seed then
        if
            type(seed) ~= 'string'
            or #seed < 1
            or #seed > 8
            or not seed:upper():match('^[A-Z0-9]+$')
        then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Seed must contain 1–8 letters/digits')
        end

        seed = seed:upper():gsub('0', 'O')
    end

    return { stake = stake, seed = seed }, center
end

function Run.start(params)
    if params.replace ~= nil and type(params.replace) ~= 'boolean' then
        Bridge.fail(Bridge.INVALID_PARAMS, 'replace must be a boolean')
    end

    local args, center = Run.validate(params)

    if
        love.filesystem.getInfo(G.SETTINGS.profile .. '/save.jkr')
        and not params.replace
        and G.STATE ~= G.STATES.GAME_OVER
        and not Run.is_win()
    then
        Bridge.fail(
            Bridge.INVALID_PARAMS,
            'A saved run exists; Continue or explicitly set replace:true'
        )
    end

    G.FUNCS.setup_run({ config = {} })

    if center then
        G.GAME.selected_back:change_to(center)
        G.GAME.viewed_back:change_to(center)
    end

    G.FUNCS.exit_overlay_menu()
    G.FUNCS.start_run(nil, args)
end

function Run.continue_endless()
    if not Run.is_win() then
        Bridge.fail(Bridge.INVALID_PARAMS, 'No victory decision is open')
    end

    local node = Controls.find(G.OVERLAY_MENU, 'button', 'exit_overlay_menu')
    Controls.click(node, 'exit_overlay_menu')
end

local function most_played_hand()
    if not G.GAME.hand_usage then
        return nil
    end

    local hand, count = nil, 0

    for _, usage in pairs(G.GAME.hand_usage) do
        if usage.count > count then
            hand, count = usage.order, usage.count
        end
    end

    return {
        hand = hand,
        name = hand and localize(hand, 'poker_hands') or localize('k_none'),
        count = count,
    }
end

local function visible_seed(text)
    local seed = G.GAME.pseudorandom and G.GAME.pseudorandom.seed

    if
        type(seed) == 'string'
        and Controls.find(G.OVERLAY_MENU, 'id', 'seed')
        and text:find(seed, 1, true)
    then
        return seed
    end
end

function Run.results()
    local ending = G.STATE == G.STATES.GAME_OVER or Run.is_win()

    if not ending then
        return nil
    end

    local scores = {}

    for name, value in pairs(G.GAME.round_scores or {}) do
        if name ~= 'poker_hand' and type(value.amt) == 'number' then
            scores[name] = value.amt
        end
    end

    scores.poker_hand = most_played_hand()
    local text = Text.read(G.OVERLAY_MENU)

    return {
        outcome = Run.is_win() and 'won' or 'lost',
        scores = scores,
        ante = G.GAME.round_resets.ante,
        round = G.GAME.round,
        text = text,
        seed = visible_seed(text),
        canContinueEndless = Run.is_win(),
    }
end

function Run.context()
    local game = G.GAME
    local back = game.selected_back
    local stake = G.P_CENTER_POOLS.Stake[game.stake or 1]

    return {
        deck = back and {
            name = back:get_name(),
            description = Text.read(back:generate_UI(nil, nil, nil, game.challenge)),
            id = back.effect.center.key,
        },
        stake = stake and {
            id = game.stake or 1,
            name = localize({ type = 'name_text', set = 'Stake', key = stake.key }),
            description = Text.read(G.UIDEF.stake_description(game.stake or 1)),
        },
        challenge = game.challenge,
        seeded = game.seeded or false,
        endless = game.win_notified and not Run.is_win() or false,
    }
end

return Run
