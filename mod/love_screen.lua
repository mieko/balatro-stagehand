local Bridge = require('balatro_stagehand.bridge')
local Screen = {}
Screen.__index = Screen

local function window_only(params)
    if next(params or {}) then
        Bridge.fail(Bridge.INVALID_PARAMS, 'LÖVE screen operations use the current window')
    end
end

function Screen.new(bridge)
    return setmetatable({ bridge = bridge, next_capture = 0 }, Screen)
end

function Screen:dimensions(params)
    window_only(params)
    local width, height = love.graphics.getDimensions()
    local pixels_x, pixels_y = love.graphics.getPixelDimensions()

    return {
        logical_size = { x = width, y = height },
        texture_size = { x = pixels_x, y = pixels_y },
    }
end

function Screen:capture(params)
    window_only(params)

    if not love.graphics or not love.graphics.isActive() then
        Bridge.fail(Bridge.IMAGE_UNAVAILABLE, 'No active rendered LÖVE window')
    end

    if not self.pending then
        self.next_capture = self.next_capture + 1
        self.pending = self.bridge.instance .. ':capture:' .. self.next_capture
    end

    return { capture = self.pending, status = 'accepted' }
end

function Screen:after_draw()
    if not self.pending then
        return
    end

    local capture = self.pending
    self.pending = nil
    love.graphics.captureScreenshot(function(image)
        local file = image:encode('png')
        self.image = {
            capture = capture,
            width = image:getWidth(),
            height = image:getHeight(),
            mime = 'image/png',
            base64 = love.data.encode('string', 'base64', file:getString()),
            clock = self.bridge:clock(),
            phase = 'next_rendered_image',
        }
        self.bridge:emit(self.root, 'captured', self.image)
    end)
end

return Screen
