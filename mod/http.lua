local handshake = require('websocket.handshake')
local Config = require('balatro_stagehand.server_config')

local Http = { MAX_HEADER_BYTES = 8192 }
local MARKDOWN = 'text/markdown; charset=utf-8'

function Http.routes(assets, token_required)
    local discovery = {
        '# Stagehand',
        '',
        'Stagehand lets external tools inspect and control Balatro through a JavaScript API.',
        '',
    }
    local routes = {}
    for _, entry in ipairs({
        { '/client.mjs', 'JavaScript client', 'text/javascript; charset=utf-8' },
        { '/api.md', 'Stagehand API', MARKDOWN },
        { '/game.md', 'Balatro API', MARKDOWN },
    }) do
        local path, label, mime = entry[1], entry[2], entry[3]
        if assets[path] then
            routes[path] = { mime = mime, body = assets[path] }
            discovery[#discovery + 1] = '- [' .. label .. '](.' .. path .. ')'
        end
    end

    discovery[#discovery + 1] = ''
    discovery[#discovery + 1] =
        'Connect using this server’s HTTP or HTTPS base address. RPC uses WebSocket at `/rpc`.'
    discovery[#discovery + 1] = token_required and 'Ask the game operator for the access token.'
        or 'This listener does not require an access token.'
    routes['/'] = { mime = MARKDOWN, body = table.concat(discovery, '\n') .. '\n' }

    return routes
end

local function response(status, asset, head_only, extra)
    local body = asset and asset.body or ''
    local header = 'HTTP/1.1 '
        .. status
        .. '\r\nConnection: close\r\nContent-Length: '
        .. #body
        .. '\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n'
    if asset then
        header = header .. 'Content-Type: ' .. asset.mime .. '\r\n'
    end

    return header .. (extra or '') .. '\r\n' .. (head_only and '' or body), false
end

function Http.header_too_large()
    return (response('431 Request Header Fields Too Large'))
end

local function fields(lines)
    local headers = {}
    for line in (lines .. '\r\n'):gmatch('(.-)\r\n') do
        local name, value = line:match("^([!#$%%&'*+.^_`|~%w-]+):[ \t]*([^\r\n]*)$")
        if not name then
            return
        end

        name, value = name:lower(), value:gsub('[ \t]+$', '')
        if headers[name] and name ~= 'connection' and name ~= 'upgrade' then
            return
        end
        headers[name] = headers[name] and headers[name] .. ',' .. value or value
    end

    return headers
end

local function authority(value)
    local host, trailing = value:lower():match('^(%[[%da-f:.]+%])(.*)$')
    if not host then
        host, trailing = value:lower():match('^([%w._-]+)(.*)$')
    end
    if not host then
        return
    end
    if trailing ~= '' then
        local port = trailing:match('^:(%d+)$')
        if not port or #port > 5 or tonumber(port) < 1 or tonumber(port) > 65535 then
            return
        end
    end

    return host
end

local function has_token(value, expected)
    for token in (value or ''):lower():gmatch('[^,]+') do
        if token:match('^%s*(.-)%s*$') == expected then
            return true
        end
    end

    return false
end

local function upgrade(headers)
    if headers.origin then
        return response('403 Forbidden')
    end
    if
        not has_token(headers.connection, 'upgrade') or not has_token(headers.upgrade, 'websocket')
    then
        return response('400 Bad Request')
    end
    if headers['sec-websocket-version'] ~= '13' then
        return response('426 Upgrade Required', nil, false, 'Sec-WebSocket-Version: 13\r\n')
    end

    local key = headers['sec-websocket-key']
    if not key or #key ~= 24 or not key:match('^[%w+/]+[AQgw]==$') then
        return response('400 Bad Request')
    end

    return 'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n'
        .. 'Sec-WebSocket-Accept: '
        .. handshake.sec_websocket_accept(key)
        .. '\r\n\r\n',
        true
end

function Http.respond(head, routes, bind_host)
    if head:find('[^\t\r\n -~]') then
        return response('400 Bad Request')
    end

    local line, remaining = head:match('^([^\r\n]+)\r\n(.*)$')
    local method, target
    if line then
        method, target = line:match('^(%S+) (/[!-~]*) HTTP/1%.1$')
    end

    local headers = method and fields(remaining)
    local host = headers and headers.host and authority(headers.host)
    if not host or headers['transfer-encoding'] or (headers['content-length'] or '0') ~= '0' then
        return response('400 Bad Request')
    end
    if
        Config.is_loopback(bind_host)
        and host ~= 'localhost'
        and host ~= '127.0.0.1'
        and host ~= '[::1]'
        and host ~= bind_host
    then
        return response('403 Forbidden')
    end

    if target == '/rpc' then
        if method ~= 'GET' then
            return response('405 Method Not Allowed', nil, false, 'Allow: GET\r\n')
        end
        return upgrade(headers)
    end
    if method ~= 'GET' and method ~= 'HEAD' then
        return response('405 Method Not Allowed', nil, false, 'Allow: GET, HEAD\r\n')
    end
    if not routes[target] then
        return response('404 Not Found')
    end

    return response('200 OK', routes[target], method == 'HEAD')
end

return Http
