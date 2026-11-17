local Bridge = require('balatro_stagehand.bridge')
local Controls = {}

function Controls.find(box, field, value)
    if not box then
        return nil
    end

    local node = box.UIRoot or box

    if node.config and node.config[field] == value then
        return node
    end

    for _, child in ipairs(node.children or {}) do
        local found = Controls.find(child, field, value)

        if found then
            return found
        end
    end
end

function Controls.refresh(node)
    local callback = node and node.config.func

    if callback then
        local update = G.FUNCS[callback]

        if not update then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Native validator is unavailable')
        end

        update(node)
    end
end

function Controls.wait_delay(step, milliseconds, since)
    if not milliseconds or milliseconds == 0 then
        return false
    end

    if since then
        step.activate_at = since + milliseconds / 1000
    else
        step.activate_at = step.activate_at or love.timer.getTime() + milliseconds / 1000
    end

    return love.timer.getTime() < step.activate_at
end

function Controls.validate_click(node, expected)
    if
        not node
        or node.config.button ~= expected
        or node.disable_button
        or node.under_overlay
        or not node.states.visible
    then
        Bridge.fail(Bridge.INVALID_PARAMS, 'Native control is not available')
    end

    if node.last_clicked and node.last_clicked + 0.1 >= G.TIMERS.REAL then
        Bridge.fail(Bridge.INPUT_CONFLICT, 'Native control is still handling its previous click')
    end
end

function Controls.click(node, expected)
    Controls.validate_click(node, expected)
    node:click()
end

return Controls
