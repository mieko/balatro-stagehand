local Status = { phase = 'starting' }

function Status.configure(config)
    Status.enabled = config.enabled
    Status.developerMode = config.developerMode or false
    Status.host = config.host
    Status.requireToken = config.requireToken or false
    Status.error, Status.endpoint, Status.address, Status.token = nil, nil, nil, nil
    Status.phase = config.enabled and 'starting' or 'disabled'
end

function Status.fail(problem)
    Status.phase, Status.error = 'failed', tostring(problem)
    Status.endpoint, Status.address, Status.token = nil, nil, nil
end

local function address(host, port)
    if host:find(':', 1, true) then
        host = '[' .. host .. ']'
    end

    return 'http://' .. host .. ':' .. tostring(port)
end

function Status.running(endpoints, configured_host, token)
    Status.host = configured_host
    Status.phase = 'running'
    Status.token = token
    local urls = {}

    for _, endpoint in ipairs(endpoints) do
        urls[#urls + 1] = address(endpoint.host, endpoint.port)
    end

    Status.endpoint = table.concat(urls, ', ')
    local first = endpoints[1]
    local local_host = first.host

    if configured_host == 'localhost' then
        local_host = 'localhost'
    elseif first.host == '::' then
        local_host = '::1'
    elseif first.host == '0.0.0.0' or first.host == '*' then
        local_host = '127.0.0.1'
    end

    Status.address = address(local_host, first.port)
end

return Status
