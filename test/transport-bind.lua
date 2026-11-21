package.path = 'mod/vendor/?.lua;' .. package.path

local created, unavailable, busy, closed_peers
local next_port = 42000
local now, waiting = 0, {}
local socket = {}

function socket.gettime()
    return now
end

function socket.bind(host, port)
    assert(host == '127.0.0.1' or host == '::1', 'Expected a canonical loopback address')

    if unavailable[host] then
        return nil, 'family unavailable'
    end

    if port ~= 0 and busy[host] then
        return nil, 'address already in use'
    end

    local listener = { host = host, port = port == 0 and next_port or port }

    function listener:getsockname()
        return self.host, self.port
    end

    function listener:settimeout() end

    function listener:close()
        self.closed = true
    end

    function listener:accept()
        return table.remove(waiting, 1)
    end

    created[#created + 1] = listener

    return listener
end

package.preload.socket = function()
    return socket
end

package.preload['websocket.frame'] = function()
    return { decode = function() end }
end

package.preload['websocket.handshake'] = function()
    return {}
end

package.preload['balatro_stagehand.http'] = assert(loadfile('mod/http.lua'))
package.preload['balatro_stagehand.server_config'] = assert(loadfile('mod/server_config.lua'))

local Transport = assert(loadfile('mod/transport.lua'))()

for _, host in ipairs({ '*', 'example.com', '127.0.0.256' }) do
    local remote_ok, remote_problem = pcall(Transport.new, host, 0)
    assert(
        not remote_ok
            and tostring(remote_problem):find('Remote connections require an access token', 1, true)
    )
end

local function start(missing, occupied, port)
    created, unavailable, busy, closed_peers = {}, missing or {}, occupied or {}, 0
    return Transport.new('localhost', port or 0, function() end, function()
        closed_peers = closed_peers + 1
    end)
end

local transport = start()
local endpoints = transport:endpoints()

assert(#endpoints == 2)
assert(endpoints[1].host == '127.0.0.1' and endpoints[2].host == '::1')
assert(endpoints[1].port == next_port and endpoints[2].port == next_port)

local peer = { socket = { close = function() end } }
transport.peers[peer] = true
transport:shutdown()

assert(closed_peers == 1 and next(transport.peers) == nil)

for _, listener in ipairs(created) do
    assert(listener.closed)
end

for _, host in ipairs({ '127.0.0.1', '::1' }) do
    transport = start({ [host] = true })
    endpoints = transport:endpoints()

    assert(#endpoints == 1 and endpoints[1].host ~= host)

    transport:shutdown()
end

local ok, problem = pcall(start, {}, { ['::1'] = true }, 27121)

assert(not ok and tostring(problem):find('address already in use', 1, true))

for _, listener in ipairs(created) do
    assert(listener.closed)
end

ok, problem = pcall(start, { ['127.0.0.1'] = true, ['::1'] = true })

assert(not ok and tostring(problem):find('No loopback address', 1, true))

print('Loopback transport assertions passed')

local function connection()
    local peer = {}

    function peer:settimeout() end

    function peer:close()
        self.closed = true
    end

    function peer:receive()
        return nil, 'timeout', ''
    end

    return peer
end

transport = start()
for _ = 1, 8 do
    waiting[#waiting + 1] = connection()
end

for _ = 1, 4 do
    transport:update()
end

local authenticated = next(transport.peers)
authenticated.upgraded, authenticated.authenticated = true, true
now = 4
transport:update()

assert(closed_peers == 0)

local fresh = connection()
waiting[1], now = fresh, 5
transport:update()

assert(closed_peers == 7 and not fresh.closed and not authenticated.socket.closed)

for peer in pairs(transport.peers) do
    -- Completing the WebSocket upgrade alone must not extend the hello deadline.
    peer.upgraded = true
end

now = 10
transport:update()

assert(closed_peers == 8 and fresh.closed)
assert(next(transport.peers) == authenticated and not authenticated.socket.closed)

transport:shutdown()
print('Connection deadline assertions passed')
