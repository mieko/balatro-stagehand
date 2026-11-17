local json = require('dkjson')
local utf8 = require('utf8')
local Transport = require('balatro_stagehand.transport')
local Bridge = {}
Bridge.__index = Bridge
Bridge.PARSE_ERROR = -32700
Bridge.INVALID_REQUEST = -32600
Bridge.METHOD_NOT_FOUND = -32601
Bridge.INVALID_PARAMS = -32602
Bridge.INTERNAL_ERROR = -32603
Bridge.AUTHENTICATION_FAILED = -32001
Bridge.UNSUPPORTED_PROTOCOL = -32002
Bridge.UNKNOWN_HANDLE = -32004
Bridge.RESOURCE_LIMIT = -32010
Bridge.IMAGE_UNAVAILABLE = -32020
Bridge.INPUT_CONFLICT = -32030

function Bridge.fail(code, message)
    error({ code = code, message = message }, 0)
end

function Bridge.array(values)
    return setmetatable(values or {}, { __jsontype = 'array' })
end

function Bridge.new(options)
    local self = setmetatable({
        token = assert(options.token),
        instance = assert(options.instance),
        roots = {},
        subscription = 0,
        tick = 0,
    }, Bridge)
    self.transport = Transport.new(
        options.host or '127.0.0.1',
        options.port or 0,
        function(peer, bytes)
            self:message(peer, bytes)
        end,
        function(peer)
            if self.on_close then
                self.on_close(peer)
            end
        end
    )

    self:register('Registry', 'Registry', {
        list = function()
            return self:list()
        end,
    }, function()
        return self:list()
    end)

    return self
end

function Bridge:register(label, kind, operations, observer, events)
    local id = self.instance .. ':' .. label
    self.roots[id] = {
        id = id,
        label = label,
        kind = kind,
        operations = operations,
        observer = observer,
        events = events or {},
        version = '1.0.0',
    }

    return id
end

function Bridge:describe(root)
    local operations = Bridge.array()

    for name in pairs(root.operations) do
        operations[#operations + 1] = name
    end

    table.sort(operations)
    local events = Bridge.array()

    for name in pairs(root.events) do
        events[#events + 1] = name
    end

    table.sort(events)

    return {
        id = root.id,
        label = root.label,
        kind = root.kind,
        version = root.version,
        operations = operations,
        events = events,
        operation_info = setmetatable({}, { __jsontype = 'object' }),
    }
end

function Bridge:list()
    local roots = Bridge.array()

    for _, root in pairs(self.roots) do
        roots[#roots + 1] = self:describe(root)
    end

    table.sort(roots, function(a, b)
        return a.label < b.label
    end)

    return roots
end

function Bridge:clock()
    return { process_frame = self.tick, monotonic_ms = love.timer.getTime() * 1000 }
end

function Bridge:dispatch(peer, method, params)
    if method == 'session.hello' then
        if params.token ~= self.token then
            Bridge.fail(Bridge.AUTHENTICATION_FAILED, 'Authentication failed')
        end

        if params.protocol ~= 1 then
            Bridge.fail(Bridge.UNSUPPORTED_PROTOCOL, 'Unsupported protocol')
        end

        peer.authenticated = true
        local major, minor, patch = love.getVersion()

        return {
            protocol = 1,
            instance = self.instance,
            clock = self:clock(),
            objects = self:list(),
            engine = { name = 'LÖVE', major = major, minor = minor, patch = patch },
        }
    end

    if not peer.authenticated then
        Bridge.fail(Bridge.AUTHENTICATION_FAILED, 'Authenticate with session.hello first')
    end

    if method == 'objects.list' then
        return self:list()
    end

    if method == 'object.unsubscribe' then
        local existed = peer.subscriptions[params.subscription] ~= nil
        peer.subscriptions[params.subscription] = nil

        return existed
    end

    local root = self.roots[params.object]

    if not root then
        Bridge.fail(Bridge.UNKNOWN_HANDLE, 'Unknown object')
    end

    if method == 'object.describe' then
        return self:describe(root)
    end

    if method == 'object.observe' then
        return {
            object = root.id,
            value = root.observer and root.observer() or json.null,
            clock = self:clock(),
        }
    end

    if method == 'object.call' then
        local operation = root.operations[params.method]

        if not operation then
            Bridge.fail(Bridge.METHOD_NOT_FOUND, 'Unknown registered operation')
        end

        if type(params.params or {}) ~= 'table' then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Expected parameters object')
        end

        return operation(params.params or {}, peer)
    end

    if method == 'object.subscribe' then
        if not root.events[params.event] then
            Bridge.fail(Bridge.INVALID_PARAMS, 'Unknown event')
        end

        local count = 0

        for _ in pairs(peer.subscriptions) do
            count = count + 1
        end

        if count >= 128 then
            Bridge.fail(Bridge.RESOURCE_LIMIT, 'Subscription limit reached')
        end

        self.subscription = self.subscription + 1
        local id = tostring(self.subscription)
        peer.subscriptions[id] = { object = root.id, event = params.event }

        return id
    end

    Bridge.fail(Bridge.METHOD_NOT_FOUND, 'Unknown method')
end

function Bridge:response(peer, request)
    if
        type(request) ~= 'table'
        or request.jsonrpc ~= '2.0'
        or type(request.method) ~= 'string'
        or (request.params ~= nil and type(request.params) ~= 'table')
    then
        return {
            jsonrpc = '2.0',
            id = json.null,
            error = { code = Bridge.INVALID_REQUEST, message = 'Invalid request' },
        }
    end

    local ok, result = pcall(self.dispatch, self, peer, request.method, request.params or {})

    if request.id == nil then
        return
    end

    local response = { jsonrpc = '2.0', id = request.id }

    if ok then
        response.result = result == nil and json.null or result
    else
        response.error = type(result) == 'table' and result
            or { code = Bridge.INTERNAL_ERROR, message = tostring(result) }
    end

    return response
end

function Bridge:message(peer, bytes)
    local request, position, problem = json.decode(bytes, 1, json.null)

    if problem or bytes:sub(position):match('%S') then
        self.transport:send(
            peer,
            json.encode({
                jsonrpc = '2.0',
                id = json.null,
                error = { code = Bridge.PARSE_ERROR, message = 'Invalid JSON' },
            })
        )
        return
    end

    local metadata = type(request) == 'table' and getmetatable(request)
    local result

    if metadata and metadata.__jsontype == 'array' then
        if #request == 0 or #request > 64 then
            result = {
                jsonrpc = '2.0',
                id = json.null,
                error = {
                    code = Bridge.INVALID_REQUEST,
                    message = 'Expected 1–64 batch requests',
                },
            }
        else
            result = Bridge.array()

            for _, item in ipairs(request) do
                local response = self:response(peer, item)

                if response then
                    result[#result + 1] = response
                end
            end

            if #result == 0 then
                return
            end
        end
    else
        result = self:response(peer, request)
    end

    if result then
        self.transport:send(peer, self:encode_response(result))
    end
end

function Bridge:encode_response(response)
    local ok, encoded = pcall(json.encode, response)

    local message

    if not ok then
        message = 'RPC result cannot be encoded'
    elseif #encoded > Transport.MAX_BYTES then
        message = 'RPC result exceeds the message limit'
    elseif not utf8.len(encoded) then
        message = 'RPC result is not valid UTF-8'
    else
        return encoded
    end
    local function failure(item)
        return {
            jsonrpc = '2.0',
            id = item.id,
            error = {
                code = Bridge.RESOURCE_LIMIT,
                message = message .. '; do not replay automatically',
            },
        }
    end

    if response.jsonrpc then
        return json.encode(failure(response))
    end

    local failures = Bridge.array()

    for _, item in ipairs(response) do
        failures[#failures + 1] = failure(item)
    end

    return json.encode(failures)
end

function Bridge:emit(object, event, value)
    for peer in pairs(self.transport.peers) do
        for id, subscription in pairs(peer.subscriptions) do
            if subscription.object == object and subscription.event == event then
                self.transport:send(
                    peer,
                    json.encode({
                        jsonrpc = '2.0',
                        method = 'object.event',
                        params = {
                            subscription = id,
                            object = object,
                            event = event,
                            value = value,
                            clock = self:clock(),
                        },
                    })
                )
            end
        end
    end
end

function Bridge:update()
    self.tick = self.tick + 1
    self.transport:update()
end

return Bridge
