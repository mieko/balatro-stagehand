"""Download the pinned official Lovely Mac ARM64 release into this project."""

import hashlib
import json
import pathlib
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = "v0.10.0"
URL = (
    f"https://github.com/ethangreen-dev/lovely-injector/releases/download/{VERSION}/"
    "lovely-aarch64-apple-darwin.tar.gz"
)
SHA256 = "77aeab72adb4e89a5ff6f4df17c4035236d047f46f7513092b042b1558302436"


def main():
    directory = ROOT / ".local/deps"
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / "lovely.tar.gz"
    if not archive.exists():
        urllib.request.urlretrieve(URL, archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != SHA256:
        raise SystemExit("Lovely archive checksum does not match the pinned release")

    with tarfile.open(archive) as package:
        members = package.getmembers()
        for member in members:
            if member.name not in ("liblovely.dylib", "run_lovely_macos.sh") or not member.isfile():
                raise SystemExit("Unexpected Lovely archive member: " + member.name)

        package.extractall(directory, members=members)
    (directory / "lovely.json").write_text(
        json.dumps(
            {
                "version": VERSION,
                "url": URL,
                "sha256": digest,
            },
            indent=2,
        )
    )
    print("Lovely installed locally: " + VERSION)


if __name__ == "__main__":
    main()
