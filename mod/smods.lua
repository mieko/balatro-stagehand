-- Steamodded registers this mod; Lovely's main.lua patch starts the service.
local installed
SMODS.current_mod.config_tab = function()
    local panel = require('balatro_stagehand.panel')

    if not installed then
        G.FUNCS.exit_mods = panel.before_close(G.FUNCS.exit_mods)
        installed = true
    end

    return panel.definition()
end

-- Settings live in stagehand.json, independently of Steamodded's config store.
SMODS.current_mod.save_mod_config = function() end
