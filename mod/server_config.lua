local json = require('dkjson')
local Config = {}
local current

function Config.is_loopback(host)
    if host == 'localhost' or host == '::1' then
        return true
    end

    local first, second, third = host:match('^127%.(%d+)%.(%d+)%.(%d+)$')
    if not first then
        return false
    end

    for _, octet in ipairs({ first, second, third }) do
        local decimal = tonumber(octet)
        if decimal > 255 or tostring(decimal) ~= octet then
            return false
        end
    end

    return true
end

local function validate(config)
    assert(type(config.enabled) == 'boolean', 'enabled must be a boolean')
    assert(type(config.developerMode) == 'boolean', 'developerMode must be a boolean')
    assert(type(config.requireToken) == 'boolean', 'requireToken must be a boolean')
    assert(type(config.host) == 'string' and config.host ~= '', 'host must be a nonempty string')
    assert(
        type(config.port) == 'number'
            and config.port == math.floor(config.port)
            and config.port >= 0
            and config.port <= 65535,
        'port must be an integer from 0 to 65535'
    )

    return config
end

local function read_values()
    if not love.filesystem.getInfo('stagehand.json') then
        return {}
    end

    local contents = assert(love.filesystem.read('stagehand.json'))
    local values, next_byte, problem = json.decode(contents, 1, json.null)
    assert(
        type(values) == 'table'
            and getmetatable(values)
            and getmetatable(values).__jsontype == 'object',
        'Invalid stagehand.json: ' .. tostring(problem or 'expected an object')
    )
    assert(not contents:sub(next_byte):find('%S'), 'Invalid stagehand.json: trailing content')

    return values
end

local function with_defaults(values)
    local supplied = os.getenv('STAGEHAND_TOKEN')
    local config = {
        enabled = true,
        developerMode = false,
        requireToken = supplied ~= nil and supplied ~= '',
        host = 'localhost',
        port = 27121,
    }

    for key, value in pairs(values) do
        assert(config[key] ~= nil, 'Unknown Stagehand setting: ' .. tostring(key))
        config[key] = value
    end

    return config
end

function Config.read_saved()
    return validate(with_defaults(read_values()))
end

function Config.save(settings)
    local values = read_values()
    validate(with_defaults(values))
    for key, value in pairs(settings) do
        values[key] = value
    end

    local config = validate(with_defaults(values))
    assert(love.filesystem.write('stagehand.json', json.encode(values, { indent = true }) .. '\n'))

    return config
end

function Config.read()
    local config = with_defaults(read_values())
    config.host = os.getenv('STAGEHAND_HOST') or config.host
    local port = os.getenv('STAGEHAND_PORT')

    if port then
        config.port = assert(tonumber(port), 'STAGEHAND_PORT must be a number')
    end

    return validate(config)
end

function Config.load()
    if not current then
        current = Config.read()
    end

    return current
end

return Config
