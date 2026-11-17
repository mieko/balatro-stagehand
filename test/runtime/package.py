"""Build a temporary fixture; optional native Lua is read from the installed game."""

from pathlib import Path
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1], "w") as archive:
    for source in Path("mod").rglob("*.lua"):
        archive.write(source, str(source))
    archive.write("test/runtime/conf.lua", "conf.lua")
    archive.write(
        "test/runtime/source.lua" if len(sys.argv) > 2 else "test/runtime/main.lua", "main.lua"
    )
    if len(sys.argv) > 2:
        with zipfile.ZipFile(sys.argv[2]) as native:
            for name in [
                "engine/object.lua",
                "engine/ui.lua",
                "game.lua",
                "card.lua",
                "cardarea.lua",
                "functions/misc_functions.lua",
                "functions/button_callbacks.lua",
            ]:
                archive.writestr("native/" + name, native.read(name))
