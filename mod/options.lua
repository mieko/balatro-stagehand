local Bridge = require('balatro_stagehand.bridge')
local unpack = unpack or table.unpack
local Options = {}
Options.__index = Options

function Options.new(speeds)
    return setmetatable({ speeds = speeds }, Options)
end

function Options:read()
    local choices = Bridge.array()

    for _, speed in ipairs(self.speeds) do
        choices[#choices + 1] = speed
    end

    return { gameSpeed = G.SETTINGS.GAMESPEED, gameSpeeds = choices }
end

function Options:set(params)
    for name in pairs(params) do
        if name ~= 'gameSpeed' then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Unsupported native option: ' .. tostring(name))
        end
    end

    local speed = params.gameSpeed

    if speed == 'fastest' then
        speed = math.max(unpack(self.speeds))
    end

    local allowed = false

    for _, candidate in ipairs(self.speeds) do
        if candidate == speed then
            allowed = true
        end
    end

    if not allowed then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Choose one of the available playback speeds or fastest')
    end

    G.FUNCS.change_gamespeed({ to_val = speed })
    G:save_settings()

    return self:read()
end

return Options
