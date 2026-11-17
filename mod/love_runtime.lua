local Runtime = {}

function Runtime.info()
    local major, minor, patch, codename = love.getVersion()

    return {
        engine = {
            name = 'LÖVE',
            major = major,
            minor = minor,
            patch = patch,
            codename = codename,
        },
        save_directory = love.filesystem.getSaveDirectory(),
    }
end

function Runtime.quit()
    love.event.quit()

    return true
end

return Runtime
