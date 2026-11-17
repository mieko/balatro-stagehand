"""Prepare a separate app and Lovely mod directory. Never patch the Steam archive."""

import hashlib
import json
import math
import pathlib
import re
import shutil
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (
    pathlib.Path.home() / "Library/Application Support/Steam/steamapps/common/Balatro/Balatro.app"
)
LOCAL = ROOT / ".local"


def sha256(filename):
    digest = hashlib.sha256()
    with filename.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_manifest(mod):
    modules = {
        **{"balatro_stagehand." + p.stem: p.name for p in mod.glob("*.lua") if p.stem != "entry"},
        **{
            "websocket." + p.stem: "vendor/websocket/" + p.name
            for p in (mod / "vendor/websocket").glob("*.lua")
        },
        "dkjson": "vendor/dkjson.lua",
    }
    manifest = (mod / "lovely.toml").read_text()
    patches = []
    for name, filename in modules.items():
        patches.append(
            f'[[patches]]\n[patches.module]\nsource = "{filename}"\nname = "{name}"\nbefore = "main.lua"\n'
        )

    patches.append(manifest)
    (mod / "lovely.toml").write_text("\n".join(patches))


def main():
    source_pack = SOURCE / "Contents/Resources/Balatro.love"
    original_hash = sha256(source_pack)
    app = LOCAL / "Balatro.app"
    if app.exists():
        running = subprocess.run(
            ["pgrep", "-f", str(app / "Contents/MacOS/love")], capture_output=True
        )
        if running.returncode == 0:
            raise SystemExit("Quit the isolated app before preparing it")
    (LOCAL / "prepared.json").unlink(missing_ok=True)
    if not app.exists():
        subprocess.run(["cp", "-cR", str(SOURCE), str(app)], check=True)

    mod = LOCAL / "mods/BalatroStagehand"
    if mod.exists():
        shutil.rmtree(mod)
    shutil.copytree(ROOT / "mod", mod)
    with zipfile.ZipFile(source_pack) as package:
        definitions = package.read("functions/UI_definitions.lua").decode("utf8")
    native_speeds = re.search(
        r"options\s*=\s*\{([^}]+)\},\s*opt_callback\s*=\s*'change_gamespeed'", definitions
    )
    if not native_speeds:
        raise SystemExit("Cannot locate the native playback-speed choices")

    speeds = [float(value.strip()) for value in native_speeds.group(1).split(",")]
    if not speeds or not all(math.isfinite(value) and value > 0 for value in speeds):
        raise SystemExit("Native playback speeds must be finite positive numbers")

    rarity_table = re.search(
        r"card_type = \(\{(localize\('k_common'\).*?)\}\)\[card.config.center.rarity\]", definitions
    )
    if not rarity_table:
        raise SystemExit("Cannot locate the native Joker rarity labels")

    rarity_keys = re.findall(r"localize\('([a-z_]+)'\)", rarity_table.group(1))
    (mod / "game_options.lua").write_text(
        "return {gameSpeeds = {"
        + ", ".join(map(str, speeds))
        + "}, rarityKeys = {"
        + ", ".join(repr(key) for key in rarity_keys)
        + "}}\n"
    )
    write_manifest(mod)
    assert sha256(source_pack) == original_hash
    assert sha256(app / "Contents/Resources/Balatro.love") == original_hash
    (LOCAL / "prepared.json").write_text(
        json.dumps({"source": str(SOURCE), "sha256": original_hash}, indent=2)
    )
    print("Prepared isolated app and mod; original archive unchanged.")


if __name__ == "__main__":
    main()
