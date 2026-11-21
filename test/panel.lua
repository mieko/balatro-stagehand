package.path = 'mod/vendor/?.lua;' .. package.path

for _, name in ipairs({ 'access_token', 'server_config', 'status', 'panel' }) do
    package.preload['balatro_stagehand.' .. name] = assert(loadfile('mod/' .. name .. '.lua'))
end

package.preload['balatro_stagehand.transport'] = function()
    return {}
end

for _, name in ipairs({
    'actions',
    'bridge',
    'card_action',
    'commerce',
    'controls',
    'layout',
    'run',
    'state',
    'text',
}) do
    package.preload['balatro_stagehand.' .. name] = assert(loadfile('mod/' .. name .. '.lua'))
end

local contents, clipboard, overlay, unreadable, unwritable
local time = 0
local environment = {}
os.getenv = function(key)
    return environment[key]
end

love = {
    timer = {
        getTime = function()
            return time
        end,
    },
    filesystem = {
        getInfo = function()
            return contents and { type = 'file' }
        end,

        read = function()
            if unreadable then
                return nil, 'cannot read configuration'
            end

            return contents
        end,

        write = function(_, value)
            if unwritable then
                return nil, 'cannot write configuration'
            end

            contents = value

            return true
        end,

        getSaveDirectory = function()
            return '/configuration folder'
        end,
    },
    system = {
        setClipboardText = function(value)
            clipboard = value
        end,
    },
    graphics = {
        newText = function(_, text)
            return {
                value = text[2],
                set = function(self, value)
                    self.value = value
                end,
            }
        end,
    },
}
G = {
    FUNCS = {},
    SETTINGS = {},
    STAGE = 1,
    STATE = 0,
    STATES = { SPLASH = -1 },
    STAGES = { MAIN_MENU = 1, RUN = 2 },
    GAME = { seeded = false, pseudorandom = { seed = 'visible-seed' } },
    E_MANAGER = { add_event = function() end },
    F_VIDEO_SETTINGS = true,
    ROOM = { T = { w = 20, h = 12 } },
    UIT = { ROOT = 1, R = 2, C = 3, T = 4, O = 5, B = 6 },
    C = { UI = { TEXT_LIGHT = {} } },
    ASSET_ATLAS = { icons = {} },
    LANG = { font = { FONT = {} } },
}

for _, name in ipairs({
    'RED',
    'ORANGE',
    'BLUE',
    'BLACK',
    'WHITE',
    'GREY',
    'CLEAR',
    'L_BLACK',
    'JOKER_GREY',
}) do
    G.C[name] = { 0.5, 0.5, 0.5, 1 }
end

function copy_table(value)
    return value
end

function darken(value)
    return value
end

lighten = darken

function localize(key)
    return key
end

function Event(args)
    return args
end

function Moveable()
    return { remove = function() end }
end

function Sprite()
    return { states = { drag = {}, visible = true } }
end

function UIBox(args)
    return { definition = args.definition, remove = function() end }
end

assert(loadfile(arg[1] .. '/UI_definitions.lua'))()
assert(loadfile(arg[1] .. '/button_callbacks.lua'))()

Object = {
    extend = function()
        return {}
    end,
}
assert(loadfile(arg[1] .. '/controller.lua'))()

local native_ui = assert(io.open(arg[1] .. '/ui.lua'))
local update_text = native_ui:read('*a'):match(
    '(function UIElement:update_text%(%)%s.-)\nfunction UIElement:update_object'
)
native_ui:close()
UIElement = {}
assert(load(update_text))()

G.FUNCS.overlay_menu = function(args)
    overlay = args.definition
    G.OVERLAY_MENU = {
        config = {},
        remove = function()
            overlay = nil
        end,
    }
end

G.CONTROLLER = { locks = {}, mod_cursor_context_layer = function() end }

function G:save_settings() end

local function escape()
    G.CONTROLLER.locks.frame = false
    G.CONTROLLER.frame_buttonpress = true
    Controller.key_press_update(G.CONTROLLER, 'escape', 0)
end

G.UIDEF.settings_tab = function()
    return { n = G.UIT.ROOT, config = {}, nodes = {} }
end

local assertions = 0
local function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))

    assertions = assertions + 1
end

local function find(node, key, value)
    if node.config and node.config[key] == value then
        return node
    end

    for _, child in ipairs(node.nodes or {}) do
        local found = find(child, key, value)

        if found then
            return found
        end
    end
end

local function texts(node)
    local result = node.config and node.config.text or ''

    for _, child in ipairs(node.nodes or {}) do
        result = result .. '\n' .. texts(child)
    end

    return result
end

local function toggle_for(node, key)
    if
        node.config
        and node.config.button == 'toggle_button'
        and node.config.ref_table.ref_value == key
    then
        return node
    end

    for _, child in ipairs(node.nodes or {}) do
        local found = toggle_for(child, key)

        if found then
            return found
        end
    end
end

local Status = require('balatro_stagehand.status')
local Panel = require('balatro_stagehand.panel')
local State = require('balatro_stagehand.state')
local Actions = require('balatro_stagehand.actions')
local service_failure, applied = nil, 0
package.preload['balatro_stagehand.boot'] = function()
    return {
        configure = function(settings)
            applied = applied + 1
            settings.host = settings.host or Status.host
            if settings.requireToken == nil then
                settings.requireToken = Status.requireToken
            end

            Status.configure(settings)

            if service_failure then
                Status.fail(service_failure)

                return false, service_failure
            end

            if settings.enabled then
                Status.running(
                    { { host = settings.host, port = 4500 } },
                    settings.host,
                    settings.requireToken and 'launch-token' or nil
                )
            end

            return true
        end,
    }
end

Status.configure({ enabled = false })
Panel.install()
Panel.install()
local options = create_UIBox_options()
local entries = options.nodes[1].nodes[1].nodes[1].nodes

equal(entries[#entries - 1].nodes[1].config.button, 'stagehand_panel')
equal(entries[#entries].nodes[1].config.button, 'show_credits')
equal(find(options, 'button', 'stagehand_panel').config.colour, G.C.BLUE)

G.STAGE = G.STAGES.RUN
options = create_UIBox_options()

equal(find(options, 'button', 'stagehand_panel') ~= nil, true)
equal(find(options, 'button', 'setup_run') ~= nil, true)

G.FUNCS.stagehand_panel()

equal(find(overlay, 'button', 'options') ~= nil, true)
equal(G.SETTINGS.paused, true)
equal(overlay.config.stagehand_local_only, true)

local copy = find(overlay, 'func', 'stagehand_copy_status')
G.FUNCS.stagehand_copy_status(copy)

equal(copy.config.button, nil)

G.FUNCS.stagehand_copy()

equal(clipboard, nil)

Status.configure({ enabled = true, host = 'localhost' })
Status.running({ { host = '127.0.0.1', port = 27121 } }, 'localhost')
local first_use = Panel.definition()
local notice = find(first_use, 'ref_value', 'notice')
local connection = find(first_use, 'ref_value', 'connection')
for _, key in ipairs({ 'copyLabel', 'connection', 'notice', 'problem' }) do
    local label = find(first_use, 'ref_value', key)
    label.config.prev_value = label.config.ref_table[key]
    label.UIBox = { recalculate = function() end }
    UIElement.update_text(label)
    equal(
        label.config.text_drawable and label.config.text_drawable.value,
        label.config.ref_table[key]
    )
end

equal(connection.config.text_drawable.value, 'http://localhost:27121 (No access token required)')
copy = find(first_use, 'func', 'stagehand_copy_status')
G.FUNCS.stagehand_copy_status(copy)
equal(copy.config.button, 'stagehand_copy')
G.FUNCS.stagehand_copy()
equal(clipboard, 'http://localhost:27121')

local remote_toggle = toggle_for(first_use, 'allowRemote')
local auth_toggle = toggle_for(first_use, 'requireToken')
auth_toggle.children = { { states = {}, config = auth_toggle.nodes[1].config } }
G.FUNCS.toggle_button(remote_toggle)
G.FUNCS.stagehand_auth_toggle(auth_toggle)
equal(auth_toggle.config.button, nil)
equal(auth_toggle.config.colour, G.C.GREY)
equal(auth_toggle.config.ref_table.ref_table.requireToken, true)
UIElement.update_text(notice)
equal(notice.config.text_drawable.value, 'Back or Copy applies changes.')
equal(connection.config.text_drawable.value, 'http://localhost:27121 (No access token required)')

G.FUNCS.toggle_button(remote_toggle)
G.FUNCS.stagehand_auth_toggle(auth_toggle)
equal(auth_toggle.config.button, 'toggle_button')
equal(auth_toggle.config.ref_table.ref_table.requireToken, false)
equal(Panel.has_pending(), false)

Status.configure({ enabled = true, requireToken = true })
Status.running({ { host = '::', port = 48201 } }, '::', 'launch-token')
local panel = Panel.definition()
equal(
    find(panel, 'ref_value', 'connection').config.text,
    'http://[::1]:48201 (Access token required)'
)
local token_slot = find(panel, 'func', 'stagehand_token_status')
token_slot.UIBox = { recalculate = function() end }
G.FUNCS.stagehand_token_status(token_slot)
local token_button = find(token_slot.config.object.definition, 'button', 'stagehand_copy_token')

equal(texts(token_button):find('Copy Access Token', 1, true) ~= nil, true)

G.FUNCS.stagehand_copy_token()

equal(clipboard, 'launch-token')

G.FUNCS.stagehand_copy()

equal(
    clipboard,
    [[Stagehand Address: http://[::1]:48201
Access Token: launch-token]]
)
equal(toggle_for(panel.nodes[#panel.nodes], 'developerMode') ~= nil, true)

Status.running({ { host = '127.0.0.2', port = 48201 } }, '127.0.0.2', 'launch-token')
local loopback = toggle_for(Panel.definition(), 'allowRemote')
equal(loopback.config.ref_table.ref_table.allowRemote, false)

for _, scenario in ipairs({
    { host = '0.0.0.0', address = 'http://127.0.0.1:48202' },
    { host = '2001:db8::1', address = 'http://[2001:db8::1]:48202' },
}) do
    Status.running({ { host = scenario.host, port = 48202 } }, scenario.host, 'launch-token')
    G.FUNCS.stagehand_copy()

    equal(clipboard:find('Stagehand Address: ' .. scenario.address .. '\n', 1, true) ~= nil, true)
end

-- Several edits commit together on Back, preserving file-only settings and launch secrets.
contents = '{"host":"::1","requireToken":true,"port":4500}'
environment = { STAGEHAND_PORT = '0', STAGEHAND_TOKEN = 'ephemeral-secret' }
Status.host = '::1'
panel = Panel.definition()
local toggle = toggle_for(panel, 'enabled')
local draft = toggle.config.ref_table.ref_table
local before_edit, applied_before_edit = contents, applied
G.FUNCS.toggle_button(toggle)
G.FUNCS.toggle_button(toggle_for(panel, 'requireToken'))
G.FUNCS.toggle_button(toggle_for(panel, 'developerMode'))

equal(Status.phase, 'running')
equal(contents, before_edit)
equal(applied, applied_before_edit)

-- The ordinary gameplay API cannot drive an overlay transition while edits wait.
local back = find(overlay, 'button', 'options')
back.click = G.FUNCS.options
G.OVERLAY_MENU.UIRoot = { config = overlay.config, children = { back } }
local state = State.new()
equal(#state:choices(), 0)
local actions = Actions.new({}, state)
local allowed, blocked = pcall(actions.start, actions, 'startRun', {}, {})
equal(allowed, false)
equal(blocked.message, 'Finish editing Stagehand settings in Balatro')
actions.pending = { kind = 'startRun', started = 0, params = {}, humanDelayMs = 0 }
actions.dispatch = function()
    error('Queued gameplay ran during Stagehand settings edits')
end
local outcome
actions.finish = function(_, status)
    outcome = status
end
actions:update()
equal(outcome, nil)
equal(contents, before_edit)
time = 121
actions:update()
equal(outcome, 'unconfirmed')

G.FUNCS.options()
local Config = require('balatro_stagehand.server_config')
local saved = Config.read_saved()

equal(saved.enabled, false)
equal(saved.port, 4500)
equal(saved.host, '::1')
equal(saved.requireToken, false)
equal(saved.developerMode, true)
equal(saved.token, nil)
equal(contents:find('ephemeral-secret', 1, true), nil)
equal(Status.phase, 'disabled')
equal(draft.notice, '')
equal(applied, applied_before_edit + 1)

-- Copy can enable a disabled service and uses the newly applied connection details.
panel = Panel.definition()
toggle = toggle_for(panel, 'enabled')
G.FUNCS.toggle_button(toggle)
G.FUNCS.toggle_button(toggle_for(panel, 'allowRemote'))

equal(Status.enabled, false)

copy = find(panel, 'func', 'stagehand_copy_status')
G.FUNCS.stagehand_copy_status(copy)

equal(copy.config.button, 'stagehand_copy')

applied_before_edit = applied
G.FUNCS.stagehand_copy()

equal(Status.enabled, true)
equal(Status.phase, 'running')
equal(Status.host, '*')
equal(Config.read_saved().host, '*')
equal(Config.read_saved().requireToken, true)
equal(Config.read_saved().port, 4500)
equal(applied, applied_before_edit + 1)
equal(clipboard:find('Stagehand Address: http://127.0.0.1:4500\n', 1, true) ~= nil, true)
equal(clipboard:find('Access Token: launch-token', 1, true) ~= nil, true)

G.FUNCS.options()

equal(applied, applied_before_edit + 1)

-- An auth edit ruled out by the remote setting does not cause an Escape save.
G.FUNCS.stagehand_panel()
panel = overlay
local token_toggle = toggle_for(panel, 'requireToken')
G.FUNCS.toggle_button(token_toggle)

equal(token_toggle.config.ref_table.ref_table.requireToken, true)
equal(Status.requireToken, true)

applied_before_edit = applied
escape()

equal(G.OVERLAY_MENU, nil)
equal(Status.requireToken, true)
equal(applied, applied_before_edit)

-- A failed save keeps the draft open, and Back remains available to discard it.
G.FUNCS.stagehand_panel()
panel = overlay
toggle = toggle_for(panel, 'enabled')
draft = toggle.config.ref_table.ref_table

equal(draft.enabled, true)
equal(draft.developerMode, true)

local before, before_applied = contents, applied
G.FUNCS.toggle_button(toggle)
unwritable = true
escape()

equal(contents, before)
equal(overlay, panel)
equal(draft.enabled, false)
equal(draft.notice, 'Could not save. Back discards edits.')
equal(draft.problem:find('cannot write configuration', 1, true) ~= nil, true)
equal(applied, before_applied)
equal(Status.enabled, true)

G.FUNCS.exit_overlay_menu()

equal(G.OVERLAY_MENU, nil)
equal(Status.enabled, true)
equal(contents, before)

unwritable = false
G.FUNCS.stagehand_panel()
G.FUNCS.toggle_button(toggle_for(overlay, 'enabled'))
G.FUNCS.exit_overlay_menu()
equal(Status.enabled, false)

-- Steamodded tab rebuilds retain edits; failed exits do not run its close callback.
local mods_exits = 0
G.FUNCS.exit_mods = function()
    mods_exits = mods_exits + 1
    G.ACTIVE_MOD_UI = nil
    G.FUNCS.exit_overlay_menu()
end

SMODS = { current_mod = {} }

assert(loadfile('mod/smods.lua'))()

panel = SMODS.current_mod.config_tab()
G.ACTIVE_MOD_UI = SMODS.current_mod
G.FUNCS.toggle_button(toggle_for(panel, 'enabled'))
G.FUNCS.toggle_button(toggle_for(panel, 'allowRemote'))
local rebuilt = SMODS.current_mod.config_tab()

equal(toggle_for(rebuilt, 'enabled').config.ref_table.ref_table.enabled, true)
equal(Status.enabled, false)

draft = toggle_for(rebuilt, 'enabled').config.ref_table.ref_table
before_applied = applied
G.FUNCS.exit_mods()

equal(mods_exits, 1)
equal(applied, before_applied + 1)
equal(Status.host, 'localhost')

panel = SMODS.current_mod.config_tab()
G.ACTIVE_MOD_UI = SMODS.current_mod
G.FUNCS.toggle_button(toggle_for(panel, 'developerMode'))
draft = toggle_for(panel, 'enabled').config.ref_table.ref_table
service_failure = 'address already in use'
local previous_clipboard = clipboard
G.FUNCS.stagehand_copy()

equal(clipboard, previous_clipboard)
equal(draft.problem:find(service_failure, 1, true) ~= nil, true)
equal(draft.notice, 'Settings saved. Stagehand could not start.')

copy = find(panel, 'func', 'stagehand_copy_status')
G.FUNCS.stagehand_copy_status(copy)
equal(copy.config.button, 'stagehand_retry')

G.FUNCS.exit_mods()

equal(mods_exits, 2)
equal(G.ACTIVE_MOD_UI, nil)

panel = SMODS.current_mod.config_tab()
draft = toggle_for(panel, 'enabled').config.ref_table.ref_table
copy = find(panel, 'func', 'stagehand_copy_status')
G.FUNCS.stagehand_copy_status(copy)
equal(copy.config.button, 'stagehand_retry')
service_failure = nil
G.FUNCS.stagehand_retry(copy)

equal(Status.enabled, true)
equal(draft.problem, '')

Status.running(
    { { host = '127.0.0.1', port = 48204 }, { host = '::1', port = 48204 } },
    'localhost',
    'launch-token'
)
G.FUNCS.stagehand_copy()

equal(clipboard:find('Stagehand Address: http://localhost:48204', 1, true) ~= nil, true)

Status.configure({ enabled = true, requireToken = false })
Status.running({ { host = '127.0.0.1', port = 48204 } }, 'localhost')
G.FUNCS.stagehand_copy()
equal(clipboard, 'http://localhost:48204')
G.FUNCS.stagehand_token_status(token_slot)
equal(token_slot.config.object.definition, nil)

for _, invalid in ipairs({ 'not json', '{"host":false}' }) do
    contents = invalid
    Status.fail('address already in use')
    panel = Panel.definition()

    equal(texts(panel):find('Cannot read settings.', 1, true) ~= nil, true)
    equal(find(panel, 'button', 'toggle_button'), nil)

    copy = find(panel, 'func', 'stagehand_copy_status')
    G.FUNCS.stagehand_copy_status(copy)

    equal(copy.config.button, nil)
    equal(contents, invalid)
end

contents, unreadable = '{}', true
panel = Panel.definition()

equal(find(panel, 'button', 'toggle_button'), nil)
equal(texts(panel):gsub('\n', ''):find('cannot read configuration', 1, true) ~= nil, true)

contents, unreadable, environment = nil, false, {}
local unicode_problem = string.rep('a', 56) .. 'é界💡/configuration.json'
Status.fail(unicode_problem)
panel = Panel.definition()
draft = toggle_for(panel, 'enabled').config.ref_table.ref_table

equal(draft.problem, unicode_problem)

print('Native panel assertions passed: ' .. assertions)
