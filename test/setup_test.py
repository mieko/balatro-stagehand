"""Preparation and launch must refuse an incomplete isolated installation."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class IsolatedSetupTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="balatro-setup-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.local = self.root / ".local"
        self.source = self.root / "source.app"
        self.required = [
            "Balatro.app/Contents/MacOS/love",
            "mods/BalatroStagehand/lovely.toml",
            "mods/BalatroStagehand/entry.lua",
            "deps/liblovely.dylib",
            "prepared.json",
        ]
        for filename in self.required:
            target = self.local / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture")
        archive = self.source / "Contents/Resources/Balatro.love"
        archive.parent.mkdir(parents=True)
        archive.write_bytes(b"fixture archive")

    def test_failed_replacement_invalidates_prior_preparation(self):
        prepare = load_tool("prepare")
        with (
            patch.multiple(prepare, ROOT=self.root, LOCAL=self.local, SOURCE=self.source),
            patch.object(
                prepare.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)
            ),
            patch.object(prepare.shutil, "copytree", side_effect=OSError("copy interrupted")),
        ):
            with self.assertRaisesRegex(OSError, "copy interrupted"):
                prepare.main()

        self.assertFalse((self.local / "prepared.json").exists())

    def test_launcher_refuses_missing_artifacts_before_spawning(self):
        launch = load_tool("launch")
        for filename in self.required:
            with self.subTest(missing=filename):
                target = self.local / filename
                target.unlink()
                with (
                    patch.multiple(launch, ROOT=self.root, LOCAL=self.local),
                    patch.object(
                        launch.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)
                    ),
                    patch.object(
                        launch.subprocess,
                        "Popen",
                        side_effect=AssertionError("Incomplete game spawned"),
                    ) as spawn,
                ):
                    with self.assertRaisesRegex(SystemExit, "prepar|Lovely"):
                        launch.main()
                    spawn.assert_not_called()
                target.write_text("fixture")


if __name__ == "__main__":
    unittest.main()
