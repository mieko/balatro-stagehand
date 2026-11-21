local socket = require('socket')
local frame = require('websocket.frame')
local Http = require('balatro_stagehand.http')
local Config = require('balatro_stagehand.server_config')

local Transport = {}
Transport.__index = Transport
local MAX_BYTES = 8 * 1024 * 1024
local HELLO_TIMEOUT_SECONDS = 5
Transport.MAX_BYTES = MAX_BYTES

local function bind(host, port)
    if host ~= '*' and host ~= '::' then
        return assert(socket.bind(host, port))
    end

    local listener, problem = socket.tcp6()

    if not listener then
        assert(host == '*', problem)

        return assert(socket.bind('0.0.0.0', port))
    end

    local ok, failure = pcall(function()
        assert(listener:setoption('ipv6-v6only', host ~= '*'))
        assert(listener:setoption('reuseaddr', true))
        assert(listener:bind('::', port))
        assert(listener:listen(32))
    end)

    if not ok then
        listener:close()
        error(failure, 0)
    end

    return listener
end

local function bind_loopbacks(port)
    local hosts = {}
    for _, host in ipairs({ '127.0.0.1', '::1' }) do
        local ok, probe = pcall(socket.bind, host, 0)
        if ok and probe then
            probe:close()
            hosts[#hosts + 1] = host
        end
    end

    assert(#hosts > 0, 'No loopback address is available')
    local listeners = {}
    for _, host in ipairs(hosts) do
        local listener, problem = socket.bind(host, port)
        if not listener then
            for _, opened in ipairs(listeners) do
                opened:close()
            end
            error(problem, 0)
        end

        listeners[#listeners + 1] = listener
        if port == 0 then
            local _, actual_port = listener:getsockname()
            port = actual_port
        end
    end

    return listeners
end

function Transport.new(host, port, on_message, on_close, token_required, assets)
    assert(token_required or Config.is_loopback(host), 'Remote connections require an access token')
    local routes = Http.routes(assets or {}, token_required)
    local listeners = host == 'localhost' and bind_loopbacks(port) or { bind(host, port) }
    for _, listener in ipairs(listeners) do
        listener:settimeout(0)
    end

    return setmetatable({
        listeners = listeners,
        peers = {},
        on_message = on_message,
        on_close = on_close,
        routes = routes,
        host = host,
    }, Transport)
end

function Transport:endpoints()
    local endpoints = {}
    for _, listener in ipairs(self.listeners) do
        local host, port = listener:getsockname()
        endpoints[#endpoints + 1] = { host = host, port = port }
    end

    return endpoints
end

function Transport:shutdown()
    for _, listener in ipairs(self.listeners) do
        listener:close()
    end
    self.listeners = {}
    for peer in pairs(self.peers) do
        self:close(peer)
    end
end

function Transport:close(peer)
    if not self.peers[peer] then
        return
    end

    self.peers[peer] = nil
    peer.socket:close()
    self.on_close(peer)
end

function Transport:queue(peer, bytes)
    if #peer.outgoing + #bytes > MAX_BYTES + 1024 then
        self:close(peer)
        return
    end

    peer.outgoing = peer.outgoing .. bytes
end

function Transport:send(peer, text)
    assert(#text <= MAX_BYTES, 'Stagehand response exceeds message limit')

    if self.peers[peer] then
        self:queue(peer, frame.encode(text, frame.TEXT, false))
    end
end

function Transport:receive(peer)
    local bytes, reason, partial = peer.socket:receive(8192)
    peer.incoming = peer.incoming .. (bytes or partial or '')

    if #peer.incoming > MAX_BYTES + 14 then
        self:close(peer)
        return
    end

    if not peer.upgraded then
        local ending = peer.incoming:find('\r\n\r\n', 1, true)
        if (ending and ending + 3 or #peer.incoming) > Http.MAX_HEADER_BYTES then
            self:queue(peer, Http.header_too_large())
            peer.closing = true
            return
        end

        if not ending then
            if reason == 'closed' then
                self:close(peer)
            end

            return
        end

        local response, upgraded =
            Http.respond(peer.incoming:sub(1, ending - 1), self.routes, self.host)
        self:queue(peer, response)
        if not upgraded then
            peer.closing = true
            return
        end

        peer.incoming = peer.incoming:sub(ending + 4)
        peer.upgraded = true
    end

    for _ = 1, 32 do
        local data, final, opcode, remaining, masked = frame.decode(peer.incoming)

        if not data then
            break
        end

        assert(peer.incoming:byte(1) % 128 < 16, 'Unexpected frame extension')
        assert(masked, 'Client frames must be masked')
        peer.incoming = remaining

        if opcode >= frame.CLOSE then
            assert(final and #data <= 125, 'Invalid control frame')

            if opcode == frame.CLOSE then
                self:close(peer)
                return
            elseif opcode == frame.PING then
                self:queue(peer, frame.encode(data, frame.PONG, false))
            else
                assert(opcode == frame.PONG, 'Unknown control frame')
            end
        else
            assert(opcode == frame.TEXT or opcode == frame.CONTINUATION, 'Text messages required')
            assert((opcode == frame.CONTINUATION) == (peer.fragment ~= nil), 'Invalid continuation')
            local message = (peer.fragment or '') .. data
            assert(#message <= MAX_BYTES, 'Message too large')
            peer.fragment = not final and message or nil

            if final then
                self.on_message(peer, message)
            end
        end
    end

    if reason == 'closed' then
        self:close(peer)
    end
end

function Transport:update()
    local now = socket.gettime()

    for peer in pairs(self.peers) do
        if not peer.authenticated and now >= peer.hello_deadline then
            self:close(peer)
        end
    end

    for _, listener in ipairs(self.listeners) do
        local accepted = listener:accept()

        if accepted then
            local count = 0

            for _ in pairs(self.peers) do
                count = count + 1
            end

            if count >= 8 then
                accepted:close()
            else
                accepted:settimeout(0)
                self.peers[{
                    socket = accepted,
                    incoming = '',
                    outgoing = '',
                    subscriptions = {},
                    hello_deadline = now + HELLO_TIMEOUT_SECONDS,
                }] =
                    true
            end
        end
    end

    for peer in pairs(self.peers) do
        if not peer.closing then
            local ok, problem = pcall(self.receive, self, peer)

            if not ok then
                print('Stagehand connection closed: ' .. tostring(problem))
                self:close(peer)
            end
        end
    end

    self:flush()
end

function Transport:flush()
    for peer in pairs(self.peers) do
        if #peer.outgoing > 0 then
            local sent, reason, last = peer.socket:send(peer.outgoing)
            peer.outgoing = peer.outgoing:sub((sent or last or 0) + 1)

            if (peer.closing and peer.outgoing == '') or (reason and reason ~= 'timeout') then
                self:close(peer)
            end
        end
    end
end

return Transport
