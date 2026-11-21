package.path = 'mod/vendor/?.lua;' .. package.path
package.preload['balatro_stagehand.transport'] = function()
    return {}
end

for _, name in ipairs({ 'bridge', 'love_script' }) do
    package.preload['balatro_stagehand.' .. name] = assert(loadfile('mod/' .. name .. '.lua'))
end

local Bridge = require('balatro_stagehand.bridge')
local Script = require('balatro_stagehand.love_script')
local json = require('dkjson')

local function rejected(source, code, message)
    local ok, problem = pcall(Script.evaluate, { source = source })

    assert(not ok, 'Expected evaluation to fail')
    assert(problem.code == code, tostring(problem.code))
    assert(problem.message:find(message, 1, true), problem.message)
end

local function check_bindings_and_scope()
    local params = {
        source = [[
function evaluate(bindings)
    return {answer = bindings.value * 2, flag = false, empty = bindings.empty}
end
]],
        bindings = { value = 21, empty = Bridge.array() },
    }
    local result = Script.evaluate(params)

    assert(result.answer == 42 and result.flag == false)
    assert(json.encode(result.empty) == '[]')
    assert(_G.evaluate == nil, 'Entry point must not leak into shared globals')
    assert(Script.evaluate({ source = 'function evaluate(bindings) end' }) == nil)
end

local function check_live_game_access()
    G = { jokers = { cards = { { ability = { extra = { Xmult = 3 } } } } } }
    local result = Script.evaluate({
        source = [[
function evaluate(bindings)
    local joker = G.jokers.cards[bindings.index]
    local previous = joker.ability.extra.Xmult
    joker.ability.extra.Xmult = bindings.multiplier
    return {previous = previous, current = joker.ability.extra.Xmult}
end
]],
        bindings = { index = 1, multiplier = 5 },
    })
    assert(result.previous == 3 and result.current == 5)
    assert(G.jokers.cards[1].ability.extra.Xmult == 5)

    rejected(
        'function evaluate(b) G.changed = true; error("controlled fault") end',
        Bridge.INTERNAL_ERROR,
        'controlled fault'
    )
    assert(G.changed, 'Runtime errors cannot undo earlier side effects')
end

local function check_invalid_evaluators()
    rejected('', Bridge.INVALID_PARAMS, 'source')
    rejected('function evaluate(', Bridge.INVALID_PARAMS, 'compile')
    rejected('return 42', Bridge.INVALID_PARAMS, 'evaluate(bindings)')
    rejected('evaluate = 42', Bridge.INVALID_PARAMS, 'evaluate(bindings)')
    rejected('coroutine.yield()', Bridge.INVALID_PARAMS, 'synchronously')
    rejected('function evaluate(b) coroutine.yield(42) end', Bridge.INVALID_PARAMS, 'synchronously')

    for _, bindings in ipairs({ false, 42, 'wrong', json.null, Bridge.array() }) do
        local ok, problem = pcall(Script.evaluate, {
            source = 'function evaluate(b) return b end',
            bindings = bindings,
        })
        assert(not ok and problem.code == Bridge.INVALID_PARAMS)
    end

    rejected(string.dump(function() end), Bridge.INVALID_PARAMS, 'bytecode')
end

local function check_result_boundaries()
    for _, expression in ipairs({
        'function() end',
        'coroutine.create(function() end)',
        'math.huge',
        '0/0',
        '{value = math.huge}',
        'setmetatable({}, {__index = {native = true}})',
    }) do
        rejected(
            'function evaluate(b) return ' .. expression .. ' end',
            Bridge.RESOURCE_LIMIT,
            'result'
        )
    end

    rejected(
        'function evaluate(b) local t = {}; t.self = t; return t end',
        Bridge.RESOURCE_LIMIT,
        'result'
    )
    rejected(
        'function evaluate(b) local t = {}; for i=1,70 do t={t} end; return t end',
        Bridge.RESOURCE_LIMIT,
        'result'
    )
end

check_bindings_and_scope()
check_live_game_access()
check_invalid_evaluators()
check_result_boundaries()
print('Script checks passed')
