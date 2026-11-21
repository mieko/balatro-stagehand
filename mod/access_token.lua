local Token = {}
local current

local function random_bytes()
    if jit and jit.os == 'Windows' then
        local ffi = require('ffi')
        ffi.cdef([[long BCryptGenRandom(void *, unsigned char *, unsigned long, unsigned long);]])
        local bytes = ffi.new('unsigned char[32]')
        local result = ffi.load('bcrypt').BCryptGenRandom(nil, bytes, 32, 2)
        assert(result == 0, 'Cannot generate an access token')

        return ffi.string(bytes, 32)
    end

    local file = assert(io.open('/dev/urandom', 'rb'))
    local bytes = file:read(32)
    file:close()
    assert(bytes and #bytes == 32, 'Cannot generate an access token')

    return bytes
end

local function generate()
    local alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local characters = {}

    while #characters < 20 do
        for byte in random_bytes():gmatch('.') do
            local value = byte:byte()

            -- Reject the uneven tail so every character has the same probability.
            if value < 248 then
                local index = value % #alphabet + 1
                characters[#characters + 1] = alphabet:sub(index, index)

                if #characters == 20 then
                    return table.concat(characters)
                end
            end
        end
    end
end

function Token.get()
    if current then
        return current
    end

    local supplied = os.getenv('STAGEHAND_TOKEN')
    current = supplied and supplied ~= '' and supplied or generate()

    return current
end

return Token
