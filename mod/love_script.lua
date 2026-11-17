local Bridge = require('balatro_stagehand.bridge')
local json = require('dkjson')
local Script = {}

local function check_result(value, ancestors, depth)
    if value == nil or value == json.null then
        return
    end

    local kind = type(value)

    if kind == 'string' or kind == 'boolean' then
        return
    end

    if kind == 'number' and value == value and math.abs(value) < math.huge then
        return
    end

    if kind ~= 'table' or ancestors[value] or depth > 64 then
        Bridge.fail(Bridge.RESOURCE_LIMIT, 'Unsupported or too deeply nested Lua result')
    end

    local metadata = getmetatable(value)

    if
        metadata
        and (
            type(metadata) ~= 'table'
            or metadata.__tojson
            or (metadata.__jsontype ~= 'array' and metadata.__jsontype ~= 'object')
        )
    then
        Bridge.fail(Bridge.RESOURCE_LIMIT, 'Lua results must contain plain JSON tables')
    end

    ancestors[value] = true

    for key, item in pairs(value) do
        if
            type(key) ~= 'string'
            and (type(key) ~= 'number' or key ~= key or math.abs(key) == math.huge)
        then
            Bridge.fail(Bridge.RESOURCE_LIMIT, 'Lua result keys must be strings or numbers')
        end

        check_result(item, ancestors, depth + 1)
    end

    ancestors[value] = nil
end

local function compile(source, environment)
    local chunk, problem

    if loadstring then
        chunk, problem = loadstring(source, '@Stagehand.evaluate')

        if chunk then
            setfenv(chunk, environment)
        end
    else
        chunk, problem = load(source, '@Stagehand.evaluate', 't', environment)
    end

    if not chunk then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Cannot compile evaluator: ' .. problem)
    end

    return chunk
end

local function prepare(params)
    local source, bindings = params.source, params.bindings

    if type(source) ~= 'string' or not source:find('%S') then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Expected Lua source defining evaluate(bindings)')
    end

    if source:byte(1) == 27 then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Expected Lua source, not bytecode')
    end

    if bindings == nil then
        bindings = {}
    elseif
        type(bindings) ~= 'table'
        or bindings == json.null
        or (getmetatable(bindings) or {}).__jsontype == 'array'
    then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Expected a bindings object')
    end

    -- A fresh definition scope, not a sandbox: native globals and libraries remain available.
    local environment = setmetatable({}, { __index = _G })
    local chunk = compile(source, environment)

    return chunk, environment, bindings
end

local function run(chunk, environment, bindings)
    local evaluation = coroutine.create(function()
        chunk()
        local entry = rawget(environment, 'evaluate')

        if type(entry) ~= 'function' then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Source must define evaluate(bindings)')
        end

        return entry(bindings)
    end)
    local ok, result = coroutine.resume(evaluation)

    if not ok then
        if type(result) == 'table' and result.code == Bridge.INVALID_PARAMS then
            Bridge.fail(result.code, result.message)
        end

        Bridge.fail(
            Bridge.INTERNAL_ERROR,
            debug.traceback(evaluation, tostring(result)):sub(1, 16384)
        )
    end

    if coroutine.status(evaluation) ~= 'dead' then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Evaluator must return synchronously, without yielding')
    end

    return result
end

function Script.evaluate(params)
    local chunk, environment, bindings = prepare(params)
    local result = run(chunk, environment, bindings)
    check_result(result, {}, 0)

    return result
end

return Script
