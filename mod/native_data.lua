local NativeData = {}

function NativeData.parse(definitions)
    local speeds = assert(
        definitions:match("options%s*=%s*{([^}]+)},%s*opt_callback%s*=%s*'change_gamespeed'"),
        'Cannot locate the native playback-speed choices'
    )
    local values = {}

    for field in speeds:gmatch('[^,]+') do
        local value = tonumber(field)
        assert(
            value and value > 0 and value < math.huge,
            'Native playback speeds must be finite positive numbers'
        )
        values[#values + 1] = value
    end

    assert(#values > 0, 'Native playback speeds must not be empty')
    local rarities = assert(
        definitions:match(
            "card_type = %({(localize%('k_common'%).-)}%)%[card.config.center.rarity%]"
        ),
        'Cannot locate the native Joker rarity labels'
    )
    local keys = {}

    for key in rarities:gmatch("localize%('([a-z_]+)'%)") do
        keys[#keys + 1] = key
    end

    return { gameSpeeds = values, rarityKeys = keys }
end

function NativeData.read()
    return NativeData.parse(assert(love.filesystem.read('functions/UI_definitions.lua')))
end

return NativeData
