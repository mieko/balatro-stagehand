local Status = require('balatro_stagehand.status')
require('balatro_stagehand.panel').install()

local ok, problem = pcall(function()
    local config = require('balatro_stagehand.server_config').load()
    Status.configure(config)
    require('balatro_stagehand.boot')
end)

if not ok then
    Status.fail(problem)
    print('Stagehand disabled: ' .. tostring(problem))
end
