local config = require('balatro_stagehand.server_config').load()
local version = require('balatro_stagehand.version')
local Status = require('balatro_stagehand.status')
local Resources = require('balatro_stagehand.resources')
local Token = require('balatro_stagehand.access_token')

local Bridge = require('balatro_stagehand.bridge')
local State = require('balatro_stagehand.state')
local Actions = require('balatro_stagehand.actions')
local Errors = require('balatro_stagehand.errors')
local Options = require('balatro_stagehand.options')
local Run = require('balatro_stagehand.run')
local Runtime = require('balatro_stagehand.love_runtime')
local Script = require('balatro_stagehand.love_script')
local Screen = require('balatro_stagehand.love_screen')
local SceneTree = require('balatro_stagehand.scene_tree')
local game_options = require('balatro_stagehand.native_data').read()
local json = require('dkjson')
local M = {}
local bridge, state, actions, screen
local incarnation = 0
local launch_instance = os.getenv('STAGEHAND_INSTANCE')
    or string.format('%.6f-%s', require('socket').gettime(), tostring({}))

local function settings(peer)
    return {
        autoskip = peer.autoskip or false,
        discoveryLabels = peer.discovery_labels or false,
    }
end

local startup = Game.start_up
function Game:start_up()
    if os.getenv('STAGEHAND_ISOLATED') then
        self.SETTINGS.WINDOW.screenmode = 'Windowed'
        self.SETTINGS.WINDOW.DISPLAYS[1].screen_res = { w = 1000, h = 650 }
        self.SETTINGS.SOUND.volume = 0
    end

    return startup(self)
end

local function register_developer_roots()
    Errors.install()
    local scene_tree = SceneTree.new(state)
    local tree_operations = {}

    for _, name in ipairs({ 'roots', 'inspect', 'children', 'query' }) do
        local method = name
        tree_operations[method] = function(params)
            return scene_tree[method](scene_tree, params)
        end
    end

    tree_operations.click = function(params)
        if actions.pending then
            Bridge.fail(Bridge.INPUT_CONFLICT, 'Another game action is active')
        end

        return scene_tree:click(params)
    end

    bridge:register('BalatroSceneTree', 'BalatroSceneTree', tree_operations, function()
        return scene_tree:roots()
    end)
    local runtime =
        bridge:register('LoveRuntime', 'LoveRuntime', Runtime, Runtime.info, { fatal = true })
    bridge:register('LoveScript', 'LoveScript', Script)
    Errors.notify = function(fatal)
        bridge:emit(
            runtime,
            'fatal',
            { message = fatal.message:sub(1, 16384), traceback = fatal.traceback:sub(1, 32768) }
        )
        bridge.transport:flush()
    end

    local held = {}
    bridge.on_close = function(peer)
        for key, owner in pairs(held) do
            if owner == peer then
                held[key] = nil
                love.keyreleased(key)
            end
        end
    end

    bridge:register('LoveInput', 'LoveInput', {
        press = function(params, peer)
            assert(type(params.key) == 'string', 'Expected key')

            if held[params.key] and held[params.key] ~= peer then
                Bridge.fail(Bridge.INPUT_CONFLICT, 'Key is held by another connection')
            end

            held[params.key] = peer
            love.keypressed(params.key)

            return true
        end,
        release = function(params, peer)
            assert(type(params.key) == 'string', 'Expected key')

            if held[params.key] ~= peer then
                Bridge.fail(Bridge.INPUT_CONFLICT, 'Key is not held by this connection')
            end

            held[params.key] = nil
            love.keyreleased(params.key)

            return true
        end,
    })
    screen = Screen.new(bridge)
    screen.root = bridge:register('LoveScreen', 'LoveScreen', {
        dimensions = function(params)
            return screen:dimensions(params)
        end,
        capture = function(params)
            return screen:capture(params)
        end,
    }, function()
        return screen.image
    end, { captured = true })
end

local function start()
    incarnation = incarnation + 1
    local token = config.requireToken and Token.get() or nil
    bridge = Bridge.new({
        token = token,
        instance = launch_instance .. ':' .. incarnation,
        host = config.host,
        port = config.port,
        assets = Resources.public_assets(),
    })

    state = State.new(game_options)
    actions = Actions.new(bridge, state)
    local options = Options.new(game_options.gameSpeeds)
    local operations = {
        state = function()
            return state:read()
        end,
        inspectCard = function(params)
            return state:inspect_card(params.ref)
        end,
        blinds = function()
            return state:blinds()
        end,
        handTypes = function()
            return state:hand_types()
        end,
        deck = function(params)
            return state:deck(params.remaining)
        end,
        runOptions = function()
            return Run.options()
        end,
        options = function()
            return options:read()
        end,
        setOptions = function(params)
            return options:set(params)
        end,
        settings = function(_, peer)
            return settings(peer)
        end,
        setAutoskip = function(params, peer)
            if type(params.enabled) ~= 'boolean' then
                Bridge.fail(Bridge.INVALID_PARAMS, 'Expected enabled boolean')
            end

            peer.autoskip = params.enabled

            return settings(peer)
        end,
        setDiscoveryLabels = function(params, peer)
            if type(params.enabled) ~= 'boolean' then
                Bridge.fail(Bridge.INVALID_PARAMS, 'Expected enabled boolean')
            end

            peer.discovery_labels = params.enabled

            return settings(peer)
        end,
        info = function()
            local info = Runtime.info()
            info.game, info.steamEnabled = G.VERSION, G.STEAM ~= nil
            info.mod = {
                name = 'Balatro Stagehand',
                version = version,
                resources = Resources.resolve(),
            }

            return info
        end,
        operation = function()
            if actions.pending then
                return {
                    action = actions.pending.action,
                    kind = actions.pending.kind,
                    status = 'running',
                }
            end

            return actions.latest
        end,
    }

    for _, operation in ipairs({
        'decision',
        'startRun',
        'continueRun',
        'selectBlind',
        'playHand',
        'discard',
        'cashOut',
        'leaveShop',
        'buy',
        'sell',
        'useConsumable',
        'pickPackCard',
        'skipPack',
        'rerollShop',
        'skipBlind',
        'rerollBoss',
        'choose',
        'reorderJokers',
        'reorderHand',
        'reorderConsumables',
        'selectCards',
        'sortHand',
        'buyAndUse',
        'continueEndless',
        'returnToMenu',
    }) do
        local name = operation
        operations[name] = function(params, peer)
            return actions:start(name, params, peer)
        end
    end

    actions.root = bridge:register('Balatro', 'Balatro', operations, function()
        return state:read()
    end, { changed = true, completed = true })
    if config.developerMode then
        register_developer_roots()
    end

    Status.running(bridge.transport:endpoints(), config.host, token)
    print('Stagehand ready: ' .. Status.endpoint)
    io.stdout:flush()
end

local function stop()
    local previous = bridge
    bridge, state, actions, screen, Errors.notify = nil, nil, nil, nil, nil
    M.last_observation = nil

    if previous then
        previous.transport:shutdown()
    end
end

function M.configure(settings)
    local host = settings.host or config.host
    local require_token = config.requireToken

    if settings.requireToken ~= nil then
        require_token = settings.requireToken
    end

    if
        bridge
        and settings.enabled
        and config.developerMode == settings.developerMode
        and config.host == host
        and config.requireToken == require_token
    then
        return true
    end

    stop()
    config.enabled, config.developerMode = settings.enabled, settings.developerMode
    config.host = host
    config.requireToken = require_token
    Status.configure(config)

    if not config.enabled then
        return true
    end

    local ok, problem = pcall(start)

    if not ok then
        stop()
        Status.fail(problem)
    end

    return ok, problem
end

local load = love.load
function love.load(...)
    load(...)

    if config.enabled then
        local ok, problem = M.configure(config)

        if not ok then
            print('Stagehand disabled: ' .. tostring(problem))
        end
    end
end

local update = love.update
function love.update(dt)
    update(dt)

    if not bridge then
        return
    end

    local current = bridge
    actions:update()

    if bridge ~= current then
        return
    end

    current:update()

    if bridge ~= current then
        return
    end
    -- Observe only for listeners; ordinary play does not build per-frame snapshots.

    if bridge.tick % 15 ~= 0 then
        return
    end

    local listening = false

    for peer in pairs(bridge.transport.peers) do
        for _, sub in pairs(peer.subscriptions) do
            if sub.object == actions.root and sub.event == 'changed' then
                listening = true
            end
        end
    end

    if listening then
        local ok, value = pcall(state.read, state)

        if not ok then
            value =
                { kind = 'ERROR', ready = false, error = 'Observation failed: ' .. tostring(value) }
        end

        local encoded = json.encode(value)

        if encoded ~= M.last_observation then
            M.last_observation = encoded
            bridge:emit(actions.root, 'changed', value)
        end
    end
end

local draw = love.draw
function love.draw()
    draw()

    if actions then
        actions:after_draw()
    end

    if screen then
        screen:after_draw()
    end
end

local end_round_native = end_round
function end_round(...)
    if actions then
        actions:before_end_round()
    end

    return end_round_native(...)
end

local emplace = CardArea.emplace
function CardArea:emplace(card, ...)
    if state and self == G.hand then
        state:forget(card)
    end

    return emplace(self, card, ...)
end

local flip = Card.flip
function Card:flip(...)
    if state and self.facing == 'front' then
        state:forget(self)
    end

    return flip(self, ...)
end

return M
