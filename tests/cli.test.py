"""Checks bin/titlebars in a throwaway HOME: settings validation, refusal of
symlinked or oversized files, setup/uninstall edits, and the offline build.
Usage (from the plugin directory): python3 tests/cli.test.py
"""

import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "bin", "titlebars")
COLORS = 'background = "#1a1b26"\nred = "#f7768e"\nblue = "#7aa2f7"\n'


def load_module(home):
    os.environ["HOME"] = home
    loader = importlib.machinery.SourceFileLoader("titlebars_cli", SCRIPT)
    spec = importlib.util.spec_from_loader("titlebars_cli", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        for rel in (".config/omarchy", ".config/hypr", ".local/state/omarchy/current/theme"):
            os.makedirs(os.path.join(self.home, rel), mode=0o700)
        self.write(".local/state/omarchy/current/theme/colors.toml", COLORS)
        self.write(".config/hypr/hyprland.lua", 'dofile("x")\nrequire("hypr.autostart")\nrequire("default.hypr.toggles")\n')
        self.cli = load_module(self.home)

    def tearDown(self):
        self.tmp.cleanup()

    def path(self, rel):
        return os.path.join(self.home, rel)

    def write(self, rel, text):
        with open(self.path(rel), "w") as out:
            out.write(text)

    def read(self, rel):
        with open(self.path(rel)) as source:
            return source.read()

    def run_cli(self, *args):
        env = {"HOME": self.home, "PATH": "/usr/bin"}
        return subprocess.run([sys.executable, "-I", SCRIPT, *args], env=env, capture_output=True, text=True, timeout=30)


class Settings(Base):
    def test_set_stores_only_changes(self):
        self.assertEqual(self.run_cli("set", "buttons", "left").returncode, 0)
        self.assertEqual(self.run_cli("set", "colors.close", "#ff0000").returncode, 0)
        self.assertEqual(self.run_cli("set", "buttons", "right").returncode, 0)
        self.assertEqual(json.loads(self.read(".config/omarchy/marcho78.titlebars.json")), {"colors": {"close": "#ff0000"}})

    def test_invalid_values_are_refused(self):
        for key, value in [("buttonSize", "30"), ("title", "maybe"), ("style", "evil"), ("colors.close", "x;rm"),
                           ("colors.close", "tomato"), ("noBarApps", "a`b"), ("nope", "1"), ("colors", "red")]:
            with self.subTest(key=key, value=value):
                self.assertNotEqual(self.run_cli("set", key, value).returncode, 0)
        self.assertFalse(os.path.exists(self.path(".config/omarchy/marcho78.titlebars.json")))

    def test_save_validates_everything(self):
        self.assertEqual(self.run_cli("save", '{"style":"nerd"}').returncode, 0)
        self.assertNotEqual(self.run_cli("save", '{"style":"nerd","titleFont":"a\\u0000b"}').returncode, 0)
        self.assertNotEqual(self.run_cli("save", "[1]").returncode, 0)
        self.assertNotEqual(self.run_cli("save", "x" * 70000).returncode, 0)
        self.assertEqual(json.loads(self.read(".config/omarchy/marcho78.titlebars.json")), {"style": "nerd"})

    def test_load_reports_a_broken_file_instead_of_failing(self):
        self.write(".config/omarchy/marcho78.titlebars.json", "{nope")
        result = self.run_cli("load")
        self.assertEqual(result.returncode, 0)
        loaded = json.loads(result.stdout)
        self.assertEqual(loaded["user"], {})
        self.assertIn("not valid JSON", loaded["problem"])
        self.assertEqual(loaded["palette"]["red"], "f7768e")


class HyprState(Base):
    def test_hypr_never_calls_hyprland_and_reports_bad_values(self):
        cli = self.cli
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "test"

        def no_processes(*args, **kwargs):
            raise AssertionError("titlebars hypr must not run programs: %r" % (args,))

        cli.run = no_processes
        self.write(".config/omarchy/marcho78.titlebars.json", '{"buttons": "left", "style": "evil", "barHeight": 999}')
        import contextlib
        import io
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                cli.cmd_hypr([])
        finally:
            del os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
        state = json.loads(out.getvalue())
        self.assertEqual(state["settings"]["buttons"], "left")
        self.assertEqual(state["settings"]["style"], "dots")
        self.assertEqual(state["settings"]["barHeight"], 26)
        self.assertIn("style", state["problems"][0])
        self.assertIn("barHeight", state["problems"][0])
        self.assertEqual(state["palette"]["red"], "f7768e")


class Refusals(Base):
    def test_symlinked_settings_file(self):
        self.write("secret", "SECRET")
        os.symlink(self.path("secret"), self.path(".config/omarchy/marcho78.titlebars.json"))
        self.assertNotEqual(self.run_cli("get").returncode, 0)
        self.assertNotEqual(self.run_cli("set", "buttons", "left").returncode, 0)
        self.assertEqual(self.read("secret"), "SECRET")

    def test_symlinked_directory(self):
        os.rename(self.path(".config/omarchy"), self.path(".config/real"))
        os.symlink(self.path(".config/real"), self.path(".config/omarchy"))
        self.assertNotEqual(self.run_cli("set", "buttons", "left").returncode, 0)
        self.assertEqual(os.listdir(self.path(".config/real")), [])

    def test_group_writable_directory(self):
        os.chmod(self.path(".config/omarchy"), 0o775)
        self.assertNotEqual(self.run_cli("set", "buttons", "left").returncode, 0)

    def test_oversized_and_hardlinked_files(self):
        self.write(".config/omarchy/marcho78.titlebars.json", " " * 70000)
        self.assertNotEqual(self.run_cli("get").returncode, 0)
        os.unlink(self.path(".config/omarchy/marcho78.titlebars.json"))
        self.write("other.json", "{}")
        os.link(self.path("other.json"), self.path(".config/omarchy/marcho78.titlebars.json"))
        self.assertNotEqual(self.run_cli("get").returncode, 0)

    def test_fifo_does_not_hang(self):
        os.mkfifo(self.path(".config/omarchy/marcho78.titlebars.json"))
        self.assertNotEqual(self.run_cli("get").returncode, 0)


class Setup(Base):
    def test_require_line_is_added_once_after_autostart_and_removed(self):
        cli = self.cli
        hdir = cli.open_dir(cli.HYPR_DIR)
        try:
            add = lambda text: cli.add_require(text, False)
            self.assertTrue(cli.edit_text_file(hdir, cli.HYPR_CONFIG, add))
            self.assertFalse(cli.edit_text_file(hdir, cli.HYPR_CONFIG, add))
        finally:
            os.close(hdir)
        lines = self.read(".config/hypr/hyprland.lua").splitlines()
        self.assertEqual(lines[2], cli.REQUIRE_LINE)
        self.assertEqual(lines.count(cli.REQUIRE_LINE), 1)
        self.assertIsNone(cli.add_require("\n".join(lines), False))
        self.assertNotIn(cli.REQUIRE_LINE, cli.remove_require("\n".join(lines) + "\n", False))

    def test_a_require_line_someone_else_wrote_is_left_alone(self):
        cli = self.cli
        theirs = 'require("hypr.autostart")\nrequire("hypr.titlebars")\n'
        with self.assertRaises(cli.Refused):
            cli.add_require(theirs, False)
        self.assertEqual(cli.remove_require(theirs, False), theirs)
        # The first release wrote the unmarked line next to its own stub: migrate it.
        migrated = cli.add_require(theirs, True)
        self.assertIn(cli.REQUIRE_LINE, migrated)
        self.assertNotIn(cli.LEGACY_REQUIRE_LINE + "\n", migrated)

    def test_setup_and_uninstall_never_touch_files_they_didnt_write(self):
        cli = self.cli
        hook_rel = ".config/omarchy/hooks/post-update.d/titlebars.hook"
        os.makedirs(self.path(".config/omarchy/hooks/post-update.d"), mode=0o700)
        self.write(".config/hypr/titlebars.lua", "-- my own file\n")
        self.write(hook_rel, "#!/bin/bash\necho mine\n")
        hdir = cli.open_dir(cli.HYPR_DIR)
        kdir = cli.open_dir(cli.HOOK_DIR)
        try:
            with self.assertRaises(cli.Refused):
                cli.write_owned(hdir, cli.HYPR_STUB, cli.STUB, 0o644, "stub")
            with self.assertRaises(cli.Refused):
                cli.write_owned(kdir, cli.HOOK_FILE, cli.HOOK, 0o755, "hook")
            cli.remove_owned(hdir, cli.HYPR_STUB, "stub")
            cli.remove_owned(kdir, cli.HOOK_FILE, "hook")
            self.assertEqual(self.read(".config/hypr/titlebars.lua"), "-- my own file\n")
            self.assertEqual(self.read(hook_rel), "#!/bin/bash\necho mine\n")
            # A foreign file that merely mentions our mark is still foreign.
            cli.write_file(hdir, cli.HYPR_STUB, ("-- " + cli.OWNER_MARK + "\n-- but mine\n").encode())
            with self.assertRaises(cli.Refused):
                cli.write_owned(hdir, cli.HYPR_STUB, cli.STUB, 0o644, "stub")
            # Our file, even one byte changed, is foreign.
            cli.write_file(kdir, cli.HOOK_FILE, (cli.HOOK + "\n").encode())
            self.assertEqual(cli.file_state(kdir, cli.HOOK_FILE), "foreign")
            # Exactly what we wrote is replaced and removed.
            for dfd, name, text in ((hdir, cli.HYPR_STUB, cli.STUB), (kdir, cli.HOOK_FILE, cli.HOOK)):
                cli.write_file(dfd, name, text.encode())
                cli.write_owned(dfd, name, text, 0o644, name)
                self.assertEqual(cli.file_state(dfd, name), "ours")
                cli.remove_owned(dfd, name, name)
                self.assertEqual(cli.file_state(dfd, name), "missing")
        finally:
            os.close(hdir)
            os.close(kdir)

    def test_menu_entries_someone_else_wrote_are_left_alone(self):
        cli = self.cli
        theirs = '{\n  "style.titlebars": {"label": "Mine", "action": "foo"},\n}\n'
        self.assertIsNone(cli.add_menu(theirs))
        self.assertEqual(cli.remove_menu(theirs), theirs)

    def test_purge_removes_only_files_it_created(self):
        cli = self.cli
        build = ".local/share/marcho78.titlebars"
        os.makedirs(self.path(build), mode=0o700)
        for name in cli.BUILD_FILES:
            self.write(f"{build}/{name}", "x")
        cli.remove_known_files(cli.BUILD_DIR, cli.BUILD_FILES)
        self.assertFalse(os.path.exists(self.path(build)))
        os.makedirs(self.path(build), mode=0o700)
        self.write(f"{build}/hyprbars.so", "x")
        self.write(f"{build}/notes.txt", "mine")
        cli.remove_known_files(cli.BUILD_DIR, cli.BUILD_FILES)
        self.assertEqual(os.listdir(self.path(build)), ["notes.txt"])


    def test_menu_entry_keeps_the_file_valid(self):
        cli = self.cli
        for original in ["{\n}\n", '{\n  "a": {"label": "A"}\n}\n', '{\n  // comment\n  "a": {"label": "A"},\n}\n', None]:
            with self.subTest(original=original):
                added = cli.add_menu(original)
                self.assertTrue(cli.menu_valid(added))
                self.assertEqual(added.count(cli.MENU_KEY), 1)
                self.assertEqual(cli.add_menu(added).count(cli.MENU_KEY), 1)
                removed = cli.remove_menu(added)
                self.assertTrue(cli.menu_valid(removed))
                self.assertNotIn(cli.MENU_KEY, removed)
        self.assertIn("/usr/bin/omarchy-shell", cli.MENU_ENTRY)

    def test_cli_link_never_replaces_someone_elses_file(self):
        cli = self.cli
        os.makedirs(self.path(".local/bin"), mode=0o700)
        self.write(".local/bin/titlebars", "mine")
        cli.link_cli()
        self.assertEqual(self.read(".local/bin/titlebars"), "mine")
        cli.unlink_cli()
        self.assertEqual(self.read(".local/bin/titlebars"), "mine")
        os.unlink(self.path(".local/bin/titlebars"))
        cli.link_cli()
        self.assertTrue(os.path.islink(self.path(".local/bin/titlebars")))
        cli.unlink_cli()
        self.assertFalse(os.path.lexists(self.path(".local/bin/titlebars")))


class Build(Base):
    def test_unsupported_hyprland_is_refused_before_anything_runs(self):
        cli = self.cli
        cli.hyprland_commit = lambda: "0" * 40
        calls = []
        cli.run = lambda *args, **kwargs: calls.append(args) or (0, "")
        if not all(os.access(tool, os.X_OK) for tool in (cli.CXX, cli.PKG_CONFIG)):
            self.skipTest("build tools not installed")
        with self.assertRaises(cli.Refused) as caught:
            cli.cmd_build([])
        self.assertIn("doesn't support Hyprland", str(caught.exception))
        self.assertEqual(calls, [])

    def test_supported_versions_are_full_commits(self):
        with open(os.path.join(HERE, "..", "hypr", "pins.json")) as source:
            pins = json.load(source)
        self.assertTrue(pins["hyprland"])
        for commit, version in pins["hyprland"].items():
            self.assertRegex(commit, r"^[0-9a-f]{40}$")
            self.assertRegex(version, r"^\d+\.\d+\.\d+$")

    def test_vendored_sources_are_complete_and_hash_the_same_way(self):
        cli = self.cli
        files, digest = cli.vendored_sources()
        self.assertEqual(set(files), set(cli.SOURCES + cli.HEADERS))
        self.assertEqual(cli.vendored_sources()[1], digest)
        self.assertIn(b"opposite", files["globals.hpp"])

    def test_the_build_never_touches_the_network(self):
        with open(SCRIPT) as source:
            code = source.read()
        for word in ("git", "clone", "curl", "wget", "http://", "urlopen"):
            self.assertNotRegex(code, r"(?<![A-Za-z_])%s(?![A-Za-z_])" % re.escape(word), word)


class OfferSetup(Base):
    def test_offers_once_until_set_up(self):
        cli = self.cli
        cli.status = lambda: {"built": False, "hooked": False}
        import contextlib
        import io
        answers = []
        for _ in range(2):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                cli.cmd_offer_setup([])
            answers.append(out.getvalue().strip())
        self.assertEqual(answers, ["yes", "no"])
        cli.status = lambda: {"built": True, "hooked": True}
        os.unlink(self.path(".local/state/marcho78.titlebars/setup-offered"))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            cli.cmd_offer_setup([])
        self.assertEqual(out.getvalue().strip(), "no")


class Processes(Base):
    def test_output_budget_kills_the_group(self):
        cli = self.cli
        with self.assertRaises(cli.Refused):
            cli.run(["/usr/bin/yes"], timeout=10, limit=4096)

    def test_deadline_kills_the_group(self):
        cli = self.cli
        with self.assertRaises(cli.Refused) as caught:
            cli.run(["/usr/bin/sleep", "30"], timeout=1)
        self.assertIn("longer than", str(caught.exception))

    def test_environment_is_minimal(self):
        cli = self.cli
        os.environ["LD_PRELOAD"] = "/nonexistent.so"
        os.environ["PKG_CONFIG_PATH"] = "/evil"
        try:
            _, out = cli.run(["/usr/bin/env"], timeout=10)
        finally:
            del os.environ["LD_PRELOAD"], os.environ["PKG_CONFIG_PATH"]
        self.assertNotIn("LD_PRELOAD", out)
        self.assertNotIn("PKG_CONFIG_PATH", out)
        self.assertIn("PATH=/usr/bin\n", out)


if __name__ == "__main__":
    unittest.main(verbosity=1)
