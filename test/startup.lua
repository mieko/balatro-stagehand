package.path = 'mod/vendor/?.lua;' .. package.path
local NativeData = assert(loadfile('mod/native_data.lua'))()
local original_getenv = os.getenv
local environment, contents, unreadable, unwritable
local assertions = 0
local Config = assert(loadfile('mod/server_config.lua'))()

os.getenv = function(key)
    return environment[key]
end

love = {
    filesystem = {
        getInfo = function()
            return contents and { type = 'file' } or nil
        end,

        read = function()
            if unreadable then
                return nil, 'cannot read configuration'
            end

            return contents
        end,

        write = function(filename, value)
            assert(filename == 'stagehand.json')

            if unwritable then
                return nil, 'cannot write configuration'
            end

            contents = value

            return true
        end,
    },
}

local function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))

    assertions = assertions + 1
end

local function read(json, env)
    contents, environment, unreadable = json, env or {}, false
    return Config.read()
end

local config = read()

equal(config.enabled, true)
equal(config.developerMode, false)
equal(config.requireToken, false)
equal(read('{"developerMode":true}').developerMode, true)
equal(config.host, 'localhost')
equal(config.port, 27121)
equal(config.token, nil)
equal(read('{"enabled":false}').enabled, false)
equal(read('{"host":"*"}').host, '*')
equal(read('{"host":"0.0.0.0"}').host, '0.0.0.0')
equal(read('{"host":"::"}').host, '::')

config = read('{"host":"*","port":4000,"requireToken":true}')

equal(config.host, '*')
equal(config.port, 4000)
equal(config.requireToken, true)

config = read('{"port":4000,"requireToken":true}', {
    STAGEHAND_HOST = '::',
    STAGEHAND_PORT = '0',
    STAGEHAND_TOKEN = 'development',
})
equal(config.host, '::')
equal(config.port, 0)
equal(config.requireToken, true)

read(nil, { STAGEHAND_TOKEN = 'development' })
equal(Config.save({ developerMode = true }).requireToken, true)
equal(contents:find('requireToken', 1, true), nil)
environment = {}
equal(Config.read().requireToken, false)
equal(Config.read().developerMode, true)

for _, json in ipairs({
    'not json',
    '{} trailing',
    '[]',
    '{"token":false}',
    '{"port":1.5}',
    '{"port":65536}',
    '{"enabled":null}',
    '{"developerMode":"true"}',
    '{"port":"4000"}',
    '{"other":true}',
}) do
    equal(pcall(read, json), false)
end

environment, contents, unreadable = {}, '{}', true

equal(pcall(Config.read), false)
equal(read(nil, { STAGEHAND_TOKEN = '' }).requireToken, false)

config = read('{"host":"::1","port":4000,"requireToken":true}', {
    STAGEHAND_HOST = '::',
    STAGEHAND_PORT = '0',
    STAGEHAND_TOKEN = 'development',
})
local loaded = Config.load()
local saved =
    Config.save({ enabled = false, developerMode = true, requireToken = false, port = 4100 })
equal(saved.enabled, false)
equal(saved.requireToken, false)
equal(saved.developerMode, true)
equal(saved.host, '::1')
equal(saved.port, 4100)
equal(saved.token, nil)
equal(Config.load(), loaded)
equal(Config.read().port, 0)
equal(Config.read().requireToken, false)
equal(Config.read_saved().port, 4100)
equal(contents:find('development', 1, true), nil)

saved = Config.save({ enabled = true })

equal(saved.developerMode, true)
equal(saved.port, 4100)
equal(saved.host, '::1')
equal(saved.token, nil)

for _, invalid in ipairs({ 'not json', '{"host":false}', '{"token":false}' }) do
    contents, unreadable = invalid, false

    equal(pcall(Config.save, { enabled = true, port = 4000 }), false)
    equal(contents, invalid)
end

contents, unreadable = '{}', true

equal(pcall(Config.save, { enabled = true, port = 4000 }), false)
equal(contents, '{}')

unreadable, unwritable = false, true

equal(pcall(Config.save, { enabled = true, port = 4000 }), false)
equal(contents, '{}')

unwritable = false

package.preload['balatro_stagehand.status'] = assert(loadfile('mod/status.lua'))
local panels = 0
package.preload['balatro_stagehand.panel'] = function()
    return {
        install = function()
            panels = panels + 1
        end,

        definition = function()
            return 'shared-panel'
        end,

        before_close = function(callback)
            return callback
        end,
    }
end

-- Missing launcher variables must not suppress the installed entry point.
local installed, booted = 0, 0
package.preload['balatro_stagehand.server_config'] = function()
    return {
        load = function()
            return { enabled = true }
        end,
    }
end

package.preload['balatro_stagehand.errors'] = function()
    return {
        install = function()
            installed = installed + 1
        end,
    }
end

package.preload['balatro_stagehand.boot'] = function()
    booted = booted + 1
    return {}
end

local metadata_file = assert(io.open('mod/BalatroStagehand.json', 'r'))
local metadata = assert(require('dkjson').decode(metadata_file:read('*a')))
metadata_file:close()
SMODS = { current_mod = metadata }
G = { FUNCS = { exit_mods = function() end } }

assert(loadfile('mod/' .. metadata.main_file))()
equal(SMODS.current_mod.config_tab(), 'shared-panel')
equal(installed, 0)
equal(booted, 0)

assert(loadfile('mod/entry.lua'))()
equal(installed, 0)
equal(booted, 1)
equal(panels, 1)

assert(loadfile('mod/' .. metadata.main_file))()
equal(installed, 0)
equal(booted, 1)

package.loaded['balatro_stagehand.server_config'] = {
    load = function()
        return { enabled = false }
    end,
}
package.loaded['balatro_stagehand.boot'] = nil

assert(loadfile('mod/entry.lua'))()
equal(installed, 0)
equal(booted, 2)
equal(require('balatro_stagehand.status').phase, 'disabled')

package.loaded['balatro_stagehand.server_config'] = {
    load = function()
        error('cannot read configuration')
    end,
}
assert(loadfile('mod/entry.lua'))()
equal(require('balatro_stagehand.status').phase, 'failed')
equal(require('balatro_stagehand.status').error:match('cannot read configuration$') ~= nil, true)
equal(booted, 2)
equal(panels, 3)

local definitions = [[options = {0.5, 1, 2, 4}, opt_callback = 'change_gamespeed'
card_type = ({localize('k_common'),localize('k_uncommon'),localize('k_rare')})[card.config.center.rarity]
]]
local native = NativeData.parse(definitions)

equal(native.gameSpeeds[1], 0.5)
equal(native.gameSpeeds[4], 4)
equal(native.rarityKeys[3], 'k_rare')
equal(pcall(NativeData.parse, definitions:gsub('0.5', '0', 1)), false)
equal(pcall(NativeData.parse, ''), false)

os.getenv = original_getenv
print('Startup assertions passed: ' .. assertions)
