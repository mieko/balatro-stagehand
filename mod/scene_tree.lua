local Bridge = require('balatro_stagehand.bridge')
local Controls = require('balatro_stagehand.controls')
local Text = require('balatro_stagehand.text')
local Tree = {}
Tree.__index = Tree

local MAX_NODES = 4096
local MAX_PAGE = 256

local function visible(node)
    local seen = {}

    while type(node) == 'table' and not seen[node] do
        if node.states and node.states.visible == false then
            return false
        end

        seen[node] = true
        node = node.parent
    end

    return true
end

local function hidden(node)
    return node.facing == 'back' or node.sprite_facing == 'back'
end

local function node_type(node)
    for _, name in ipairs({ 'UIElement', 'UIBox', 'CardArea', 'Card', 'Sprite', 'Moveable', 'Node' }) do
        local class = rawget(_G, name)
        local current = getmetatable(node)

        while class and current do
            if current == class then
                return name
            end

            current = getmetatable(current)
        end
    end

    return 'Node'
end

local function is_class(node, name)
    local class = rawget(_G, name)
    local current = getmetatable(node)

    while class and current do
        if current == class then
            return true
        end
        current = getmetatable(current)
    end

    return false
end

local function transform(value)
    if type(value) ~= 'table' then
        return nil
    end

    local result = {}

    for _, key in ipairs({ 'x', 'y', 'w', 'h', 'r', 'scale' }) do
        if type(value[key]) == 'number' then
            result[key] = value[key]
        end
    end

    return result
end

local function page_params(params)
    local offset, limit = params.offset or 0, params.limit or 100

    if
        type(offset) ~= 'number'
        or offset < 0
        or offset % 1 ~= 0
        or type(limit) ~= 'number'
        or limit < 1
        or limit > MAX_PAGE
        or limit % 1 ~= 0
    then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Expected offset >= 0 and limit 1–256, both integers')
    end

    return offset, limit
end

function Tree.new(state)
    return setmetatable({ state = state }, Tree)
end

function Tree:entry_points()
    local roots, seen = {}, {}
    local function add(node)
        if type(node) == 'table' and not seen[node] and visible(node) then
            seen[node] = true
            roots[#roots + 1] = node
        end
    end

    for _, kind in ipairs({ 'UIBOX', 'POPUP', 'ALERT' }) do
        for _, node in ipairs(G.I and G.I[kind] or {}) do
            add(node)
        end
    end

    add(G.ROOM)

    for _, node in pairs(self.state:visible_areas()) do
        add(node)
    end

    return roots
end

function Tree:links(node)
    local result, seen = {}, {}
    local function add(child)
        if type(child) == 'table' and child.states and not seen[child] and visible(child) then
            seen[child] = true
            result[#result + 1] = child
        end
    end

    if hidden(node) then
        return result
    end

    add(node.UIRoot)
    local keys = {}

    for key in pairs(node.children or {}) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then
            return type(a) < type(b)
        end

        if type(a) == 'number' then
            return a < b
        end

        return tostring(a) < tostring(b)
    end)

    for _, key in ipairs(keys) do
        add(node.children[key])
    end

    add(node.config and node.config.object)

    -- Only public, currently rendered card areas: never follow the deck or arbitrary model tables.
    for _, area in pairs(self.state:visible_areas()) do
        if node == area then
            for _, card in ipairs(area.cards or {}) do
                add(card)
            end

            break
        end
    end

    return result
end

function Tree:walk(roots, visit)
    local queue, seen, visited = {}, {}, 0

    for _, node in ipairs(roots) do
        if not seen[node] then
            seen[node] = true
            queue[#queue + 1] = { node = node, depth = 0 }
        end
    end

    local cursor = 1

    while cursor <= #queue do
        local entry = queue[cursor]
        local node = entry.node
        cursor = cursor + 1

        if visible(node) then
            visited = visited + 1

            if visited > MAX_NODES or entry.depth > 64 then
                Bridge.fail(
                    Bridge.RESOURCE_LIMIT,
                    'Scene traversal exceeds 4096 nodes or 64 levels'
                )
            end

            if visit(node, entry.parent) then
                return
            end

            for _, child in ipairs(self:links(node)) do
                if not seen[child] then
                    seen[child] = true
                    queue[#queue + 1] = { node = child, parent = node, depth = entry.depth + 1 }
                end
            end
        end
    end
end

function Tree:resolve(ref)
    if type(ref) ~= 'string' then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Expected a scene node ref')
    end

    local found, parent
    self:walk(self:entry_points(), function(node, owner)
        if self.state:ref(node) == ref then
            found, parent = node, owner

            return true
        end
    end)

    if not found then
        Bridge.fail(Bridge.UNKNOWN_HANDLE, 'Scene node is stale or not visible')
    end

    return found, parent
end

function Tree:describe(node, parent)
    local result = {
        node = self.state:ref(node),
        class = node_type(node),
        visible = true,
        parent = parent and self.state:ref(parent) or nil,
        transform = transform(node.T),
        visual_transform = transform(node.VT),
        under_overlay = node.under_overlay or false,
    }

    if hidden(node) then
        result.hidden = true

        return result
    end

    local config = node.config or {}
    local own = { config = config }

    if config.object and not visible(config.object) then
        own.config =
            { text = config.text, ref_table = config.ref_table, ref_value = config.ref_value }
    end

    local text = Text.read(own)
    local boundary = 2048

    while
        text:byte(boundary + 1)
        and text:byte(boundary + 1) >= 128
        and text:byte(boundary + 1) < 192
    do
        boundary = boundary - 1
    end

    result.text, result.text_truncated = text:sub(1, boundary), #text > 2048
    result.id = type(config.id) == 'string' and config.id or nil
    result.button = type(config.button) == 'string' and config.button or nil
    result.validator = type(config.func) == 'string' and config.func or nil

    if result.button then
        result.enabled = not node.disable_button
            and not node.under_overlay
            and not (G.CONTROLLER and G.CONTROLLER.locked)
    end

    for name, value in pairs(G) do
        if value == node and type(name) == 'string' then
            result.name = name
            break
        end
    end

    return result
end

function Tree:roots()
    local result = Bridge.array()

    for _, node in ipairs(self:entry_points()) do
        if #result >= MAX_PAGE then
            Bridge.fail(Bridge.RESOURCE_LIMIT, 'Too many scene roots')
        end

        result[#result + 1] = self:describe(node)
    end

    return result
end

function Tree:inspect(params)
    return self:describe(self:resolve(params.node))
end

function Tree:children(params)
    local node = self:resolve(params.node)
    local offset, limit = page_params(params)
    local children, result = self:links(node), Bridge.array()

    for index = offset + 1, math.min(#children, offset + limit) do
        result[#result + 1] = self:describe(children[index], node)
    end

    return { nodes = result, more = #children > offset + limit }
end

function Tree:query(params)
    local offset, limit = page_params(params)

    for key, value in pairs(params) do
        if key ~= 'offset' and key ~= 'limit' then
            if
                not ({ root = true, id = true, class = true, button = true, text = true })[key]
                or type(value) ~= 'string'
            then
                Bridge.fail(
                    Bridge.INVALID_PARAMS,
                    'Expected root, id, class, button or text strings'
                )
            end
        end
    end

    local roots = self:entry_points()

    if params.root then
        local root = self:resolve(params.root)
        roots = { root }
    end

    local result, matches = Bridge.array(), 0
    self:walk(roots, function(node, parent)
        local detail = self:describe(node, parent)

        for _, key in ipairs({ 'id', 'class', 'button', 'text' }) do
            if
                params[key]
                and (
                    key == 'text' and not (detail.text or ''):find(params.text, 1, true)
                    or key == 'class' and not is_class(node, params.class)
                    or key ~= 'text' and key ~= 'class' and detail[key] ~= params[key]
                )
            then
                return false
            end
        end

        matches = matches + 1

        if matches > offset + limit then
            return true
        end

        if matches > offset then
            result[#result + 1] = detail
        end
    end)

    return { nodes = result, more = matches > offset + limit }
end

function Tree:click(params)
    if G.screenwipe or G.CONTROLLER and G.CONTROLLER.locked then
        Bridge.fail(Bridge.INPUT_CONFLICT, 'Wait for native controls to become available')
    end

    local node = self:resolve(params.node)
    Controls.refresh(node)
    if self:resolve(params.node) ~= node then
        Bridge.fail(Bridge.UNKNOWN_HANDLE, 'Control changed')
    end

    if
        not node.config
        or type(node.config.button) ~= 'string'
        or type(node.click) ~= 'function'
    then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Scene node is not an available button')
    end

    Controls.click(node, node.config and node.config.button)

    return { clicked = true, node = params.node }
end

return Tree
