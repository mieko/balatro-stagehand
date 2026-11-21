for _, name in ipairs({
    'bridge',
    'transport',
    'http',
    'errors',
    'love_script',
    'server_config',
    'access_token',
}) do
    package.preload['balatro_stagehand.' .. name] =
        assert(love.filesystem.load('mod/' .. name .. '.lua'))
end

for _, name in ipairs({ 'frame', 'handshake', 'tools', 'bit' }) do
    package.preload['websocket.' .. name] =
        assert(love.filesystem.load('mod/vendor/websocket/' .. name .. '.lua'))
end

package.preload.dkjson = assert(love.filesystem.load('mod/vendor/dkjson.lua'))

local Bridge = require('balatro_stagehand.bridge')
local Errors = require('balatro_stagehand.errors')
local Script = require('balatro_stagehand.love_script')

Errors.install()

local bridge, root, runtime, crash
local position = { kind = 'FIXTURE', ready = true }

function love.load()
    local config = require('balatro_stagehand.server_config').read()
    local resources_path = os.getenv('FIXTURE_RESOURCES')
    local assets
    if resources_path then
        local file = assert(io.open(resources_path, 'rb'))
        local source = file:read('*a')
        file:close()
        local resources = assert(
            loadstring(source, '=[lovely balatro_stagehand.resources "' .. resources_path .. '"]')
        )()
        assets = resources.public_assets()
    end

    bridge = Bridge.new({
        token = config.requireToken and require('balatro_stagehand.access_token').get() or nil,
        host = config.host,
        instance = 'fixture',
        port = config.port,
        assets = assets,
    })
    runtime = bridge:register('LoveRuntime', 'LoveRuntime', {
        info = function()
            return { fixture = true }
        end,
    }, nil, { fatal = true })
    bridge:register('LoveScript', 'LoveScript', Script)
    Errors.notify = function(fatal)
        bridge:emit(runtime, 'fatal', fatal)
        bridge.transport:flush()
    end

    root = bridge:register('Balatro', 'Balatro', {
        state = function()
            return position
        end,

        setPosition = function(params)
            position = params

            bridge:emit(root, 'changed', position)

            return true
        end,

        echo = function(params)
            return params
        end,

        playHand = function(params)
            if params.fail then
                crash = true
            else
                bridge:emit(root, 'completed', {
                    action = 'test',
                    status = 'completed',
                    state = { kind = 'FIXTURE', ready = true },
                })
            end

            return { action = 'test', status = 'accepted' }
        end,
    }, nil, { completed = true, changed = true })

    local port = bridge.transport:endpoints()[1].port

    print('FIXTURE_READY ' .. port)
    io.stdout:flush()
end

function love.update()
    if crash then
        error('controlled native fatal')
    end

    bridge:update()
    love.timer.sleep(0.001)
end
