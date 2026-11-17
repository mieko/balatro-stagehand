"""Launch only the prepared copy, with a dedicated LÖVE identity and no Steam API."""

import json
import os
import pathlib
import secrets
import socket
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local"


def main():
    app = LOCAL / "Balatro.app"
    executable = app / "Contents/MacOS/love"
    running = subprocess.run(["pgrep", "-f", str(executable)], capture_output=True)
    if running.returncode == 0:
        raise SystemExit("The isolated game is already running")

    mod = LOCAL / "mods/BalatroStagehand"
    required = (LOCAL / "prepared.json", executable, mod / "lovely.toml", mod / "entry.lua")
    if not all(item.is_file() for item in required):
        raise SystemExit("Run npm run prepare:game to complete the isolated installation")

    if not (LOCAL / "deps/liblovely.dylib").is_file():
        raise SystemExit("Install Lovely with python3 tools/fetch-lovely.py first")

    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        port = reserved.getsockname()[1]
    token, instance = secrets.token_urlsafe(32), secrets.token_hex(8)
    environment = dict(
        os.environ,
        STAGEHAND_TOKEN=token,
        STAGEHAND_INSTANCE=instance,
        STAGEHAND_PORT=str(port),
        STAGEHAND_ISOLATED="1",
        LOVELY_MOD_DIR=str(LOCAL / "mods"),
        DYLD_INSERT_LIBRARIES=str(LOCAL / "deps/liblovely.dylib"),
    )
    log = LOCAL / ("game-" + time.strftime("%Y%m%d-%H%M%S") + ".log")
    with log.open("wb") as output:
        process = subprocess.Popen(
            [str(executable)],
            cwd=LOCAL,
            env=environment,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    session = LOCAL / "session.json"
    descriptor = os.open(session, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(
            {
                "url": "ws://127.0.0.1:" + str(port),
                "token": token,
                "instance": instance,
                "pid": process.pid,
                "log": str(log),
            },
            stream,
        )
    for _ in range(200):
        if "Stagehand ready:" in log.read_text(errors="replace"):
            print(f"Isolated Balatro ready, PID {process.pid}; session in .local/session.json")
            return
        if process.poll() is not None:
            raise SystemExit("Game exited; inspect " + str(log))

        time.sleep(0.1)
    raise SystemExit("Startup not confirmed; process outcome unknown. Inspect " + str(log))


if __name__ == "__main__":
    main()
