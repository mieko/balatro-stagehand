for _, name in ipairs({ 'bridge', 'transport', 'errors' }) do
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
Errors.install()
local bridge, root, runtime, crash

function love.load()
    bridge = Bridge.new({ token = 'fixture-only', instance = 'fixture', port = 0 })
    runtime = bridge:register('LoveRuntime', 'LoveRuntime', {
        info = function()
            return { fixture = true }
        end,
    }, nil, { fatal = true })
    Errors.notify = function(fatal)
        bridge:emit(runtime, 'fatal', fatal)
        bridge.transport:flush()
    end

    root = bridge:register('Balatro', 'Balatro', {
        state = function()
            return { kind = 'FIXTURE', ready = true }
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
    }, nil, { completed = true })
    local _, port = bridge.transport.listener:getsockname()
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
