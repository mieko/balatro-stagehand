local Text = {}

function Text.clean(value)
    return value:gsub('%s+', ' '):match('^%s*(.-)%s*$')
end

local function token(value)
    if type(value) == 'string' or type(value) == 'number' then
        return tostring(value)
    end

    if type(value) ~= 'table' then
        return nil
    end

    if value.ref_table and value.ref_value then
        local current = value.ref_table[value.ref_value]

        if type(current) == 'string' or type(current) == 'number' then
            return (value.prefix or '') .. tostring(current) .. (value.suffix or '')
        end
    end

    if type(value.string) == 'string' then
        return value.string
    end
end

local function dynamic(object)
    local candidates = object.config and object.config.string
    local minimum, maximum

    if type(candidates) == 'table' then
        for _, value in ipairs(candidates) do
            local number = type(value) == 'string' and tonumber(value)

            if not number then
                minimum = nil
                break
            end

            minimum = minimum and math.min(minimum, number) or number
            maximum = maximum and math.max(maximum, number) or number
        end
    end

    if minimum then
        return minimum == maximum and tostring(minimum)
            or tostring(minimum) .. '–' .. tostring(maximum)
    end

    local function safe(value)
        return value and not value:match('^#@') and value ~= 'rand()'
    end

    local current = token(object.string)

    if safe(current) then
        return current
    end

    -- Retain native units, excluding decorative hidden-card/random strings.
    local values, seen = {}, {}

    for _, entry in ipairs(candidates or type(object.string) == 'table' and object.string or {}) do
        local value = token(entry)

        if safe(value) and not seen[value] then
            values[#values + 1], seen[value] = value, true
        end
    end

    return table.concat(values, ' ')
end

local function collect(node, result, seen, excluded)
    if type(node) ~= 'table' or seen[node] then
        return
    end

    seen[node] = true
    local config = node.config

    if config and excluded and excluded[config.id] then
        return
    end

    if config then
        local value = token(config.text)

        if not value and config.ref_table then
            value = token(config)
        end

        if value then
            result[#result + 1] = value
        end

        local object = config.object
        local content = object and object.string

        if type(content) == 'string' or type(content) == 'table' then
            local value = dynamic(object)

            if value then
                result[#result + 1] = value
            end
        end
    end

    if node.UIRoot then
        collect(node.UIRoot, result, seen, excluded)
    end

    for _, child in ipairs(node.children or node.nodes or node) do
        collect(child, result, seen, excluded)
    end
end

function Text.release(nodes, seen)
    if type(nodes) ~= 'table' then
        return
    end

    seen = seen or {}

    if seen[nodes] then
        return
    end

    seen[nodes] = true
    local object = nodes.config and nodes.config.object

    if object and not seen[object] and object.remove then
        seen[object] = true
        object:remove()
    end
    -- Only authored tooltip children, never referenced game objects.

    for _, child in ipairs(nodes.children or nodes.nodes or nodes) do
        Text.release(child, seen)
    end
end

function Text.read(nodes, excluded)
    if type(nodes) == 'string' then
        return Text.clean(nodes)
    end

    local result = {}
    collect(nodes, result, {}, excluded)

    return Text.clean(table.concat(result, ' '))
end

return Text
