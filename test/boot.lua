package.path = 'mod/vendor/?.lua;' .. package.path
package.preload['balatro_stagehand.status'] = assert(loadfile('mod/status.lua'))
local Status = require('balatro_stagehand.status')
local config = {
    enabled = true,
    developerMode = false,
    requireToken = false,
    host = 'localhost',
    port = 0,
}
local resources =
    { agentApi = { path = '/installed/api' }, client = { path = '/installed/client' } }
local failure, closed, native_loads, operations, roots, instances
local peer = {}
local pressed, released = {}, {}
local assertions = 0
local original_getenv = os.getenv
os.getenv = function(name)
    if name == 'STAGEHAND_INSTANCE' then
        return 'fixture-launch'
    end

    return original_getenv(name)
end

local function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))

    assertions = assertions + 1
end

local function module(name, value)
    package.preload['balatro_stagehand.' .. name] = function()
        return value
    end
end

module('server_config', {
    load = function()
        return config
    end,
})
module('version', '1.2.3')
module('access_token', {
    get = function()
        assert(config.requireToken, 'Tokenless startup must not need randomness')
        return 'launch-token'
    end,
})
module('resources', {
    public_assets = function()
        return {}
    end,
    resolve = function()
        return resources
    end,
})
module('native_data', {
    read = function()
        return { gameSpeeds = { 1, 2 } }
    end,
})
module('bridge', {
    new = function(options)
        equal(options.host, config.host)
        equal(options.port, config.port)
        equal(options.token, config.requireToken and 'launch-token' or nil)
        equal(instances[options.instance], nil)

        instances[options.instance] = true

        if failure == 'bind' then
            error('address already in use')
        end

        roots = {}
        local server = { transport = { peers = { [peer] = true } } }

        function server.transport:endpoints()
            return { { host = '127.0.0.1', port = 45812 }, { host = '::1', port = 45812 } }
        end

        function server.transport:shutdown()
            closed = true

            if server.on_close then
                server.on_close(peer)
            end
        end

        function server:register(_, kind, methods)
            roots[kind] = methods
            if kind == 'Balatro' then
                operations = methods
            end

            return kind
        end

        return server
    end,
})
module('state', {
    new = function()
        if failure == 'state' then
            error('native state unavailable')
        end

        return {}
    end,
})

for _, name in ipairs({ 'actions', 'options', 'love_screen', 'scene_tree' }) do
    module(name, {
        new = function()
            return {}
        end,
    })
end

for _, name in ipairs({ 'run', 'love_script' }) do
    module(name, {})
end

module('errors', { install = function() end })
module('love_runtime', {
    info = function()
        return { fixture = true }
    end,
})
package.preload.socket = function()
    return {
        gettime = function()
            return 123
        end,
    }
end

for _, example in ipairs({ 'bind', 'state', 'success', 'disabled' }) do
    failure, closed, native_loads, operations = example, false, 0, nil
    instances = {}
    config.enabled, config.developerMode = example ~= 'disabled', false
    config.requireToken = false
    G = { VERSION = 'native-version' }
    Game = { start_up = function() end }
    CardArea = { emplace = function() end }
    Card = { flip = function() end }
    end_round = function() end
    love = {
        load = function(value)
            equal(value, 'native-argument')

            native_loads = native_loads + 1
        end,

        update = function() end,
        draw = function() end,
        keypressed = function(key)
            pressed[#pressed + 1] = key
        end,

        keyreleased = function(key)
            released[#released + 1] = key
        end,
    }
    Status.configure(config)
    local service = assert(loadfile('mod/boot.lua'))()
    love.load('native-argument')

    equal(native_loads, 1)

    if example == 'success' then
        equal(Status.phase, 'running')
        equal(Status.endpoint, 'http://127.0.0.1:45812, http://[::1]:45812')
        equal(Status.address, 'http://localhost:45812')
        equal(Status.error, nil)
        equal(closed, false)

        local info = operations.info()

        equal(info.mod.resources, resources)
        equal(info.mod.version, '1.2.3')
        equal(info.game, 'native-version')
        equal(roots.Balatro ~= nil, true)
        equal(roots.BalatroSceneTree, nil)

        equal(
            service.configure({
                enabled = true,
                developerMode = false,
                requireToken = true,
                host = '*',
            }),
            true
        )
        equal(Status.host, '*')
        equal(Status.requireToken, true)
        equal(Status.token, 'launch-token')
        equal(
            service.configure({
                enabled = true,
                developerMode = false,
                requireToken = false,
                host = 'localhost',
            }),
            true
        )
        equal(Status.host, 'localhost')
        equal(Status.requireToken, false)
        equal(Status.token, nil)

        equal(service.configure({ enabled = false, developerMode = false }), true)
        equal(Status.enabled, false)
        equal(closed, true)

        love.update(0.01)
    elseif example == 'disabled' then
        equal(Status.phase, 'disabled')
        equal(operations, nil)
        equal(service.configure({ enabled = true, developerMode = false }), true)
        equal(Status.enabled, true)
        equal(service.configure({ enabled = true, developerMode = true }), true)

        for _, kind in ipairs({
            'LoveRuntime',
            'LoveScript',
            'LoveInput',
            'LoveScreen',
            'BalatroSceneTree',
        }) do
            equal(roots[kind] ~= nil, true)
        end

        roots.LoveInput.press({ key = 'w' }, peer)

        equal(pressed[#pressed], 'w')
        equal(service.configure({ enabled = true, developerMode = false }), true)
        equal(released[#released], 'w')
        equal(roots.LoveScript, nil)
        equal(roots.LoveInput, nil)
        equal(roots.LoveRuntime, nil)
        equal(roots.LoveScreen, nil)
        equal(roots.BalatroSceneTree, nil)

        failure = 'bind'

        equal(service.configure({ enabled = true, developerMode = true }), false)
        equal(Status.enabled, true)
        equal(Status.phase, 'failed')

        failure = 'success'

        equal(service.configure({ enabled = true, developerMode = true }), true)
        equal(Status.phase, 'running')
    else
        equal(Status.phase, 'failed')
        equal(Status.endpoint, nil)

        local message = example == 'bind' and 'address already in use' or 'native state unavailable'

        equal(Status.error:find(message, 1, true) ~= nil, true)
        equal(closed, example == 'state')
    end
end

os.getenv = original_getenv
print('Boot assertions passed: ' .. assertions)
