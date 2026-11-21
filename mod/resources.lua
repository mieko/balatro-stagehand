local Resources = {}
-- Lovely supplies this module's installed absolute source path.
local source = debug.getinfo(1, 'S').source
local filename = source:match('^=%[lovely balatro_stagehand.resources "(.*)"%]$')
    or source:match('^@(.*)$')
local directory = filename and filename:match('^(.*)[/\\][^/\\]+$')

function Resources.file_url(path)
    assert(type(path) == 'string', 'Expected an absolute filesystem path')
    local windows = path:match('^%a:[/\\]') or path:sub(1, 2) == '\\\\'
    if windows then
        path = path:gsub('\\', '/')
    end

    local unc = path:sub(1, 2) == '//'
    if path:match('^%a:/') then
        path = '/' .. path
    end

    assert(path:sub(1, 1) == '/', 'Expected an absolute filesystem path')
    local encoded = path:gsub('([^A-Za-z0-9%-%._~/:])', function(byte)
        return string.format('%%%02X', byte:byte())
    end)

    return (unc and 'file:' or 'file://') .. encoded
end

local files = {
    { key = 'stagehandApi', route = '/api.md', relative = 'docs/api.md' },
    { key = 'agentApi', route = '/game.md', relative = 'docs/game.md' },
    { key = 'client', route = '/client.mjs', relative = 'client.mjs' },
}

function Resources.resolve()
    assert(directory, 'Cannot resolve the installed mod directory')
    local resources = {}
    for _, asset in ipairs(files) do
        local path = directory .. '/' .. asset.relative
        local file = io.open(path, 'rb')
        if file then
            file:close()
        end

        resources[asset.key] =
            { path = path, url = Resources.file_url(path), available = file ~= nil }
    end

    return resources
end

function Resources.public_assets()
    local assets = {}
    if not directory then
        return assets
    end

    local limit = 1024 * 1024
    for _, asset in ipairs(files) do
        local file = io.open(directory .. '/' .. asset.relative, 'rb')
        if file then
            local bytes = file:read(limit + 1)
            file:close()
            if bytes and #bytes <= limit then
                assets[asset.route] = bytes
            end
        end
    end

    return assets
end

return Resources
