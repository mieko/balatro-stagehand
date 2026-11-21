local Config = require('balatro_stagehand.server_config')
local Status = require('balatro_stagehand.status')
local utf8 = require('utf8')
local Panel = {}
local installed, pending

local function line(value, scale)
    return {
        n = G.UIT.R,
        config = { align = 'cm', padding = 0.05, maxw = 8 },
        nodes = {
            {
                n = G.UIT.T,
                config = { text = value, scale = scale or 0.35, colour = G.C.UI.TEXT_LIGHT },
            },
        },
    }
end

local function button(label, callback)
    return UIBox_button({
        label = { label },
        button = callback,
        colour = G.C.BLUE,
        minw = 4.5,
        minh = 0.7,
        scale = 0.35,
    })
end

local function gap()
    return { n = G.UIT.R, config = { minh = 0.2 }, nodes = {} }
end

local function problem_lines(nodes, problem)
    local value = tostring(problem):gsub('%s+', ' ')

    while #value > 0 do
        local next_line = utf8.offset(value, 65)
        nodes[#nodes + 1] = line(value:sub(1, next_line and next_line - 1 or #value), 0.3)
        value = next_line and value:sub(next_line) or ''
    end
end

local function feedback(draft, key)
    local notice = line(draft[key], 0.3)
    notice.nodes[1].config.ref_table, notice.nodes[1].config.ref_value = draft, key

    return notice
end

local function setting_toggle(label, key, draft, apply)
    return create_toggle({
        label = label,
        ref_table = draft,
        ref_value = key,
        callback = apply,
        w = 4.5,
        scale = 1,
        label_scale = 0.4,
        active_colour = G.C.BLUE,
    })
end

local fields = { 'enabled', 'developerMode', 'requireToken' }

local function changes_from(draft)
    local changes = {}
    for _, field in ipairs(fields) do
        if draft[field] ~= draft.initial[field] then
            changes[field] = draft[field]
        end
    end
    if draft.allowRemote ~= draft.initialRemote then
        changes.host = draft.allowRemote and '*' or 'localhost'
        if draft.allowRemote then
            changes.requireToken = true
        end
    end

    return changes
end

local function connection_summary()
    if not Status.address then
        return ''
    end

    local auth = Status.requireToken and 'Access token required' or 'No access token required'

    return Status.address .. ' (' .. auth .. ')'
end

local function configure(draft, host)
    local ok, problem = pcall(function()
        local applied, failure = require('balatro_stagehand.boot').configure({
            enabled = draft.enabled,
            developerMode = draft.developerMode,
            requireToken = draft.requireToken,
            host = host,
        })
        assert(applied, failure)
    end)
    draft.connection = connection_summary()
    draft.problem = ok and '' or tostring(problem)

    return ok
end

function Panel.apply()
    local draft = pending
    if not draft then
        return true
    end

    local changes = changes_from(draft)
    local ok, problem = pcall(Config.save, changes)
    draft.saveFailed = not ok
    if not ok then
        draft.notice = 'Could not save. Back discards edits.'
        draft.problem = tostring(problem)
        return false
    end

    for _, field in ipairs(fields) do
        draft.initial[field] = draft[field]
    end
    draft.initialRemote = draft.allowRemote
    pending = nil

    ok = configure(draft, changes.host)
    draft.notice = ok and '' or 'Settings saved. Stagehand could not start.'

    return ok
end

function Panel.has_pending()
    return pending ~= nil
end

function Panel.before_close(callback)
    return function(...)
        if pending and pending.saveFailed then
            pending = nil
        end
        if Panel.apply() then
            return callback(...)
        end
    end
end

local function can_retry(draft)
    return draft.valid
        and draft.enabled
        and Status.phase == 'failed'
        and type(package.loaded['balatro_stagehand.boot']) == 'table'
end

function Panel.definition()
    Panel.install()
    local ok, saved = pcall(Config.read_saved)
    local active = (Status.enabled ~= nil and Status) or (ok and saved) or {}
    local draft = pending
        or {
            enabled = active.enabled or false,
            developerMode = active.developerMode or false,
            allowRemote = not Config.is_loopback(active.host or 'localhost'),
            requireToken = active.requireToken or false,
            localToken = active.requireToken or false,
            connection = connection_summary(),
            notice = Status.phase == 'failed' and 'Stagehand could not start.' or '',
            problem = Status.error or '',
            valid = ok,
            copyLabel = 'Copy Connection Details',
        }
    if not draft.initial then
        draft.initial = {}
        for _, field in ipairs(fields) do
            draft.initial[field] = draft[field]
        end
        draft.initialRemote = draft.allowRemote
    end
    local nodes = {}
    local function edit()
        pending = next(changes_from(draft)) and draft or nil
        draft.saveFailed = false
        draft.notice = pending and 'Back or Copy applies changes.'
            or (Status.phase == 'failed' and 'Stagehand could not start.' or '')
        draft.problem = Status.error or ''
    end

    local function edit_auth()
        if draft.allowRemote then
            draft.requireToken = true
        else
            draft.localToken = draft.requireToken
        end
        edit()
    end

    if ok then
        nodes[#nodes + 1] = setting_toggle('Enable Stagehand', 'enabled', draft, edit)
        nodes[#nodes + 1] = setting_toggle(
            'Allow Remote Connections',
            'allowRemote',
            draft,
            function()
                draft.requireToken = draft.allowRemote or draft.localToken
                edit()
            end
        )
        local token = setting_toggle('Require Access Token', 'requireToken', draft, edit_auth)
        local checkbox = token.nodes[2].nodes[1].nodes[1]
        checkbox.config.func = 'stagehand_auth_toggle'
        nodes[#nodes + 1] = token

        nodes[#nodes + 1] = feedback(draft, 'connection')
        nodes[#nodes + 1] = feedback(draft, 'notice')
        nodes[#nodes + 1] = feedback(draft, 'problem')
    else
        nodes[#nodes + 1] = line('Cannot read settings.')
        problem_lines(nodes, saved)
    end

    local copy = button(draft.copyLabel, 'stagehand_copy')
    local copy_button = copy.nodes[1]
    copy_button.config.func, copy_button.config.ref_table = 'stagehand_copy_status', draft
    local label = copy_button.nodes[1].nodes[1].config
    label.ref_table, label.ref_value = draft, 'copyLabel'
    nodes[#nodes + 1] = gap()
    nodes[#nodes + 1] = copy

    if ok then
        nodes[#nodes + 1] = {
            n = G.UIT.R,
            config = { align = 'cm' },
            nodes = {
                { n = G.UIT.O, config = { object = Moveable(), func = 'stagehand_token_status' } },
            },
        }
        nodes[#nodes + 1] = gap()
        local developer = setting_toggle('Developer Mode', 'developerMode', draft, edit)
        local tooltip = {
            text = {
                'Connected clients will be able to',
                'execute arbitrary code',
                'on this computer',
            },
        }
        developer.config.hover = true
        developer.config.on_demand_tooltip = tooltip
        developer.nodes[1].nodes[1].config.colour = G.C.ORANGE
        developer.nodes[2].nodes[1].nodes[1].config.on_demand_tooltip = tooltip
        nodes[#nodes + 1] = developer
    end

    for _, node in ipairs(nodes) do
        node.config.stagehand_local_only = true
    end

    return {
        n = G.UIT.ROOT,
        config = { align = 'cm', padding = 0.08, colour = G.C.CLEAR },
        nodes = nodes,
    }
end

local function options_with_stagehand(definition)
    local container = definition.nodes[1].nodes[1].nodes[1]
    local indices, nodes = {}, {}
    local entry = UIBox_button({
        label = { 'Stagehand' },
        button = 'stagehand_panel',
        colour = G.C.BLUE,
        minw = 5,
    })
    entry.config.stagehand_local_only = true

    -- Native Options contains empty slots for entries unavailable in the current game stage.
    for index in pairs(container.nodes) do
        indices[#indices + 1] = index
    end

    table.sort(indices)

    for _, index in ipairs(indices) do
        local node = container.nodes[index]

        if node.nodes[1].config.button == 'show_credits' then
            nodes[#nodes + 1], entry = entry, nil
        end

        nodes[#nodes + 1] = node
    end

    if entry then
        nodes[#nodes + 1] = entry
    end

    container.nodes = nodes

    return definition
end

function Panel.install()
    if installed then
        return
    end

    installed = true
    G.FUNCS.overlay_menu = Panel.before_close(G.FUNCS.overlay_menu)
    G.FUNCS.exit_overlay_menu = Panel.before_close(G.FUNCS.exit_overlay_menu)
    local options = create_UIBox_options
    function create_UIBox_options(...)
        return options_with_stagehand(options(...))
    end

    G.FUNCS.stagehand_panel = function()
        G.SETTINGS.paused = true
        local definition = create_UIBox_generic_options({
            back_func = 'options',
            contents = Panel.definition().nodes,
        })
        definition.config.stagehand_local_only = true
        G.FUNCS.overlay_menu({ definition = definition })
    end
    G.FUNCS.stagehand_auth_toggle = function(element)
        G.FUNCS.toggle(element)
        local config = element.config
        if config.ref_table.ref_table.allowRemote then
            config.button = nil
            config.colour = G.C.GREY
        else
            config.button = 'toggle_button'
            config.colour = config.toggle_active and config.ref_table.active_colour
                or config.ref_table.inactive_colour
        end
    end
    G.FUNCS.stagehand_copy_status = function(element)
        local draft = element.config.ref_table
        local action
        if draft.saveFailed or can_retry(draft) then
            action = 'stagehand_retry'
            draft.copyLabel = draft.saveFailed and 'Retry Save' or 'Retry Stagehand'
        else
            draft.copyLabel = 'Copy Connection Details'
            if draft.valid and draft.enabled and (pending or Status.phase == 'running') then
                action = 'stagehand_copy'
            end
        end

        element.config.button = action
        element.config.colour = action and G.C.BLUE or G.C.GREY
    end
    G.FUNCS.stagehand_retry = function(element)
        local draft = element.config.ref_table
        if pending then
            Panel.apply()
        elseif can_retry(draft) then
            draft.notice = configure(draft) and '' or 'Stagehand could not start.'
        end
    end
    G.FUNCS.stagehand_copy = function()
        if Panel.apply() and Status.phase == 'running' then
            local details = Status.address
            if Status.requireToken then
                details = 'Stagehand Address: ' .. details .. '\nAccess Token: ' .. Status.token
            end

            love.system.setClipboardText(details)
        end
    end
    G.FUNCS.stagehand_token_status = function(element)
        local visible = Status.phase == 'running' and Status.token ~= nil
        if visible ~= (element.config.token_visible or false) then
            element.config.token_visible = visible
            element.config.object:remove()
            element.config.object = visible
                    and UIBox({
                        definition = {
                            n = G.UIT.ROOT,
                            config = {
                                align = 'cm',
                                colour = G.C.CLEAR,
                                stagehand_local_only = true,
                            },
                            nodes = { button('Copy Access Token', 'stagehand_copy_token') },
                        },
                        config = { align = 'cm', parent = element },
                    })
                or Moveable()
            element.UIBox:recalculate()
        end
    end
    G.FUNCS.stagehand_copy_token = function()
        if Status.token then
            love.system.setClipboardText(Status.token)
        end
    end
end

return Panel
