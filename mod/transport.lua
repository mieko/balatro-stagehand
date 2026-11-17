local socket = require('socket')
local frame = require('websocket.frame')
local handshake = require('websocket.handshake')

local Transport = {}
Transport.__index = Transport
local MAX_BYTES = 8 * 1024 * 1024
Transport.MAX_BYTES = MAX_BYTES

function Transport.new(host, port, on_message, on_close)
    local listener = assert(socket.bind(host, port))
    listener:settimeout(0)

    return setmetatable({
        listener = listener,
        peers = {},
        on_message = on_message,
        on_close = on_close,
    }, Transport)
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

        if not ending then
            assert(#peer.incoming <= 16384, 'WebSocket headers too large')

            if reason == 'closed' then
                self:close(peer)
            end

            return
        end

        local response = handshake.accept_upgrade(peer.incoming:sub(1, ending + 3), {})
        assert(response, 'Invalid WebSocket upgrade')
        self:queue(peer, response)
        peer.incoming = peer.incoming:sub(ending + 4)
        peer.upgraded = true
    end

    for _ = 1, 32 do
        local data, final, opcode, remaining, masked = frame.decode(peer.incoming)

        if not data then
            break
        end

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
    local accepted = self.listener:accept()

    if accepted then
        local count = 0

        for _ in pairs(self.peers) do
            count = count + 1
        end

        if count >= 8 then
            accepted:close()
        else
            accepted:settimeout(0)
            self.peers[{ socket = accepted, incoming = '', outgoing = '', subscriptions = {} }] =
                true
        end
    end

    for peer in pairs(self.peers) do
        local ok, problem = pcall(self.receive, self, peer)

        if not ok then
            print('Stagehand connection closed: ' .. tostring(problem))
            self:close(peer)
        end
    end

    self:flush()
end

function Transport:flush()
    for peer in pairs(self.peers) do
        if #peer.outgoing > 0 then
            local sent, reason, last = peer.socket:send(peer.outgoing)
            peer.outgoing = peer.outgoing:sub((sent or last or 0) + 1)

            if reason and reason ~= 'timeout' then
                self:close(peer)
            end
        end
    end
end

return Transport
