# Lua dependencies

- `websocket/`: frame, handshake and utility modules from
  [lua-websockets](https://github.com/lipp/lua-websockets), commit
  `1c6e94b27fe7cb157877987fba86299fb326be0c`. MIT license in `websocket/COPYRIGHT`.
  Its `math.randomseed` call is removed so loading the codec cannot reseed Balatro.
  `mod/transport.lua` owns scheduling; Copas, lua-ev and LuaSec are not required.
- `dkjson.lua`: [dkjson](https://github.com/LuaDist/dkjson), commit
  `e72ba0c9f5d8b8746fc306f6189a819dbb5cd0be`. MIT license included in the source.

LuaSocket and bit operations come from the game's bundled LÖVE/LuaJIT runtime.
Lovely is installed separately; its binaries are not redistributed here.
