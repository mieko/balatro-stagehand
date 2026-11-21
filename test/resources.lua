local path = assert(arg[1])
local file = assert(io.open(path, 'rb'))
local source = file:read('*a')
file:close()

local compile = loadstring or load
local Resources =
    assert(compile(source, '=[lovely balatro_stagehand.resources "' .. path .. '"]'))()
local json = assert(loadfile(arg[2]))()
local paths = assert(json.decode(io.read('*a')))
local urls = {}

for index, value in ipairs(paths) do
    urls[index] = Resources.file_url(value)
end

print(json.encode({ resources = Resources.resolve(), urls = urls }))
