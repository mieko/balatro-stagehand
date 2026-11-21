package.path = 'mod/vendor/?.lua;' .. package.path

for _, name in ipairs({ 'bridge', 'controls', 'text', 'scene_tree', 'love_runtime', 'love_screen' }) do
    package.preload['balatro_stagehand.' .. name] = assert(loadfile('mod/' .. name .. '.lua'))
end

package.preload['balatro_stagehand.transport'] = function()
    return {}
end

local Tree = require('balatro_stagehand.scene_tree')
local Runtime = require('balatro_stagehand.love_runtime')
local json = require('dkjson')
local refs, next_id = setmetatable({}, { __mode = 'k' }), 0
local state = {}

function state:ref(node)
    if not refs[node] then
        next_id = next_id + 1
        refs[node] = 'n' .. next_id
    end

    return refs[node]
end

function state:visible_areas()
    return { G.hand }
end

local function node(config, children)
    return { config = config or {}, children = children or {}, states = { visible = true } }
end

local clicks = 0
local label = node({ text = 'A new game feature' })
local button = node({ id = 'future-button', button = 'future_action' }, { label })
local hidden = node({ text = 'Hidden offer' })
hidden.states.visible = false
local box = node({}, { button, hidden })
local secret = { seed = 'SECRET', rank = 'Ace', suit = 'Spades' }
button.config.ref_table = secret
label.parent, button.parent, hidden.parent = button, box, box

function button:click()
    clicks = clicks + 1
end

local back = node()
back.facing = 'back'
back.base = secret
back.children = { node({ text = 'Hidden card identity' }) }
local hand = node()
hand.cards = { back }
G = {
    I = { UIBOX = { box, box }, POPUP = {}, ALERT = {} },
    hand = hand,
    UIT = { T = 1 },
    TIMERS = { REAL = 2 },
    CONTROLLER = { locked = false },
    FUNCS = {},
}
local tree = Tree.new(state)

-- Unknown native widgets are discoverable without a semantic binding or captions.
assert(#tree:roots() == 2)

local found = tree:query({ id = 'future-button' })

assert(#found.nodes == 1 and found.nodes[1].button == 'future_action')
assert(found.nodes[1].enabled and found.nodes[1].node == state:ref(button))
assert(tree:query({ text = 'new game feature' }).nodes[1].parent == state:ref(button))
assert(#tree:query({ root = state:ref(label), id = 'future-button' }).nodes == 0)

local breadth = tree:query({ root = state:ref(box) }).nodes

assert(breadth[1].node == state:ref(box) and breadth[2].node == state:ref(button))
assert(breadth[3].node == state:ref(label))
assert(#tree:query({ text = 'Hidden offer' }).nodes == 0)
assert(not json.encode(tree:query({})):find('SECRET', 1, true))

local children = tree:children({ node = state:ref(box), limit = 1 })

assert(#children.nodes == 1 and not children.more)
assert(tree:inspect({ node = state:ref(back) }).hidden)
assert(#tree:children({ node = state:ref(back) }).nodes == 0)
assert(#tree:query({ text = 'Hidden card identity' }).nodes == 0)

-- Pagination is explicit, and traversal follows only native scene relationships.
local first = tree:query({ limit = 1 })
local second = tree:query({ offset = 1, limit = 1 })

assert(first.more and first.nodes[1].node ~= second.nodes[1].node)

box.children[#box.children + 1] = box

assert(#tree:query({ id = 'future-button' }).nodes == 1)

local clicked = tree:click({ node = state:ref(button) })

assert(clicked.clicked and clicks == 1)

button.disable_button = true

assert(not pcall(tree.click, tree, { node = state:ref(button) }) and clicks == 1)

button.disable_button = nil
G.CONTROLLER.locked = true

assert(not pcall(tree.click, tree, { node = state:ref(button) }) and clicks == 1)

G.CONTROLLER.locked = false
box.states.visible = false

assert(not pcall(tree.inspect, tree, { node = state:ref(button) }))

box.states.visible = true
G.I.UIBOX = {}

assert(not pcall(tree.click, tree, { node = state:ref(button) }) and clicks == 1)
assert(not pcall(tree.query, tree, { limit = 0 }))

G.I.UIBOX = { box }
box.children = {
    [2] = node({ id = 'two' }),
    [10] = node({ id = 'ten' }),
    ['11'] = node({ id = 'label' }),
}
local ordered = tree:children({ node = state:ref(box) }).nodes

assert(ordered[1].id == 'two' and ordered[2].id == 'ten' and ordered[3].id == 'label')

local text = node({ text = string.rep('x', 2047) .. '界' })
box.children = { text }
local detail = tree:inspect({ node = state:ref(text) })

assert(detail.text == string.rep('x', 2047) and detail.text_truncated)
assert(not pcall(tree.click, tree, { node = state:ref(text) }))

local descendant = text

for _ = 1, 65 do
    local child = node()
    descendant.children = { child }
    descendant = child
end

assert(not pcall(tree.query, tree, {}))

-- Engine metadata must work without Balatro globals.
G = nil
local quit = false
love = {
    getVersion = function()
        return 11, 5, 0, 'fixture'
    end,
    filesystem = {
        getSaveDirectory = function()
            return '/fixture'
        end,
    },
    event = {
        quit = function()
            quit = true
        end,
    },
}
local info = Runtime.info()

assert(
    info.engine.major == 11 and info.engine.name == 'LÖVE' and info.save_directory == '/fixture'
)
assert(info.game == nil and info.steamEnabled == nil)
assert(Runtime.quit() and quit)

-- Native capture is asynchronous; IDs correlate its callback without mixing frames.
local Screen = require('balatro_stagehand.love_screen')
local callbacks, emitted = {}, {}
love.graphics = {
    isActive = function()
        return true
    end,

    getDimensions = function()
        return 320, 240
    end,

    getPixelDimensions = function()
        return 640, 480
    end,

    captureScreenshot = function(callback)
        callbacks[#callbacks + 1] = callback
    end,
}
love.data = {
    encode = function(_, _, bytes)
        return 'encoded-' .. bytes
    end,
}
local screen = Screen.new({
    instance = 'screen',
    clock = function()
        return { process_frame = 5 }
    end,

    emit = function(_, _, _, image)
        emitted[#emitted + 1] = image
    end,
})
local dimensions = screen:dimensions({})

assert(dimensions.logical_size.x == 320 and dimensions.texture_size.x == 640)

local accepted = screen:capture({})

assert(accepted.capture == screen:capture({}).capture)
assert(#callbacks == 0 and screen.image == nil)

screen:after_draw()
local next_capture = screen:capture({})

assert(next_capture.capture ~= accepted.capture)

callbacks[1]({
    getWidth = function()
        return 640
    end,

    getHeight = function()
        return 480
    end,

    encode = function()
        return {
            getString = function()
                return 'png'
            end,
        }
    end,
})
assert(emitted[1].capture == accepted.capture and emitted[1].base64 == 'encoded-png')
assert(emitted[1].phase == 'next_rendered_image' and emitted[1].clock.process_frame == 5)
assert(screen.pending == next_capture.capture)
assert(not pcall(screen.capture, screen, { viewport = 'not-a-love-viewport' }))

love.graphics.isActive = function()
    return false
end

assert(not pcall(screen.capture, screen, {}))

print('Scene tree checks passed')
