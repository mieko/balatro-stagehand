local Errors = {}
local installed

function Errors.install()
    if installed then
        return
    end

    installed = true
    local previous = love.errhand
    function love.errhand(message)
        local fatal =
            { message = tostring(message), traceback = debug.traceback(tostring(message)) }
        print(fatal.traceback)
        io.stdout:flush()

        if Errors.notify then
            local ok, problem = pcall(Errors.notify, fatal)

            if not ok then
                print('Stagehand fatal notification failed: ' .. tostring(problem))
                io.stdout:flush()
            end
        end

        return previous(message)
    end
end

return Errors
