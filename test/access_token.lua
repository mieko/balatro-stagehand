local original_getenv = os.getenv
local original_open, original_jit = io.open, jit
local supplied
os.getenv = function(name)
    assert(name == 'STAGEHAND_TOKEN')

    return supplied
end

-- Exercise the byte-to-token conversion deterministically on every platform.
jit = nil
io.open = function(filename, mode)
    assert(filename == '/dev/urandom' and mode == 'rb')

    return {
        read = function()
            return string.char(248)
                .. string.rep(string.char(0), 19)
                .. string.char(61)
                .. string.rep(string.char(255), 11)
        end,

        close = function() end,
    }
end

local function token_source()
    return assert(loadfile('mod/access_token.lua'))()
end

local generated = token_source()
local first = generated.get()

assert(#first == 20 and first:match('^[a-zA-Z0-9]+$'))
assert(first == string.rep('a', 19) .. '9')

supplied = 'changed-after-generation'

assert(generated.get() == first)

supplied = 'provided-ENV-token_0'
local provided = token_source()

assert(provided.get() == supplied)

supplied = 'changed-after-initialization'

assert(provided.get() == 'provided-ENV-token_0')

supplied = ''

assert(#token_source().get() == 20)

io.open = original_open
jit = original_jit
os.getenv = original_getenv
print('Access token checks passed')
