"""Tests for setup.sh, against a local bare repo standing in for amos-workspace.

The stand-in's install.sh only records that it ran, so these test setup.sh alone.
Run: python3 -m unittest -v tests/test_setup.py   (Python 3 standard library only)
"""

import os
import subprocess
import tempfile
import unittest

SETUP = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "setup.sh")

FAKE_INSTALL = """#!/usr/bin/env bash
echo "install ran in $(pwd -P) from ${0%/.amos-workspace/scripts/install.sh}"
exit "${FAKE_INSTALL_EXIT:-0}"
"""


def sh(*cmd, cwd=None, env=None, check=True, stdin=None):
    return subprocess.run(cmd, cwd=cwd, env=env, check=check, capture_output=True, text=True, stdin=stdin)


def read(path):
    with open(path) as fh:
        return fh.read()


def write(root, path, text):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as fh:
        fh.write(text)


class SetupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = os.path.realpath(self.tmp.name)
        self.env = {**os.environ, "HOME": os.path.join(t, "home"), "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                    "GIT_COMMITTER_EMAIL": "t@t", "AMOS_GIT_BASE": os.path.join(t, "remotes")}
        os.makedirs(self.env["HOME"])
        src = os.path.join(t, "src")
        write(src, "AGENTS.md", "agents\n")
        write(src, ".claude/skills/x/SKILL.md", "skill\n")
        write(src, ".amos-workspace/scripts/install.sh", FAKE_INSTALL)
        os.chmod(os.path.join(src, ".amos-workspace/scripts/install.sh"), 0o755)
        sh("git", "init", "-q", "-b", "main", cwd=src, env=self.env)
        sh("git", "add", "-A", cwd=src, env=self.env)
        sh("git", "commit", "-q", "-m", "ws", cwd=src, env=self.env)
        sh("git", "clone", "-q", "--bare", src, os.path.join(t, "remotes", "amos-workspace.git"), env=self.env)
        self.amos = os.path.join(t, "amos")
        os.makedirs(os.path.join(self.amos, "amos-connect"))
        write(self.amos, "notes.md", "mine\n")

    def tearDown(self):
        self.tmp.cleanup()

    def setup(self, *args, env=None):
        return sh("bash", SETUP, *args, cwd=self.amos, env={**self.env, **(env or {})}, check=False)

    def store(self, *args):
        return sh("git", "--git-dir", os.path.join(self.amos, ".amos-workspace", "store.git"), *args,
                  env=self.env).stdout.strip()

    def leftovers(self):
        return [name for name in os.listdir(self.amos) if name.startswith(".amos-workspace-setup.")]

    def test_installs_into_the_folder_without_a_git_folder(self):
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(read(os.path.join(self.amos, "AGENTS.md")), "agents\n")
        self.assertEqual(read(os.path.join(self.amos, "notes.md")), "mine\n")  # untouched
        self.assertFalse(os.path.exists(os.path.join(self.amos, ".git")))
        self.assertNotEqual(sh("git", "rev-parse", "--git-dir", cwd=self.amos, env=self.env, check=False).returncode, 0)
        self.assertEqual(self.store("config", "core.worktree"), "../..")
        self.assertEqual(self.store("rev-parse", "--show-toplevel"), self.amos)
        self.assertEqual(self.store("status", "--porcelain", "--untracked-files=no"), "")
        self.assertEqual(self.store("rev-parse", "--abbrev-ref", "main@{upstream}"), "origin/main")
        self.assertIn(f"install ran in {self.amos}", result.stdout)
        self.assertIn("setup: done.", result.stdout)
        self.assertEqual(self.leftovers(), [])

    def test_installs_main_even_when_the_default_branch_is_another(self):
        remote = os.path.join(self.env["AMOS_GIT_BASE"], "amos-workspace.git")
        sh("git", "--git-dir", remote, "branch", "dev", "main", env=self.env)
        sh("git", "--git-dir", remote, "symbolic-ref", "HEAD", "refs/heads/dev", env=self.env)
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.store("symbolic-ref", "--short", "HEAD"), "main")
        self.assertEqual(self.store("rev-parse", "--abbrev-ref", "main@{upstream}"), "origin/main")

    def test_runs_from_a_pipe_and_with_the_folder_named(self):
        with open(SETUP) as script:
            result = sh("bash", "-s", "--", self.amos, cwd=self.env["HOME"], env=self.env, check=False, stdin=script)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("setup: done.", result.stdout)

    def test_clashing_files_are_all_listed_and_nothing_changes(self):
        write(self.amos, "AGENTS.md", "old\n")
        write(self.amos, ".claude/skills/x/SKILL.md", "old\n")
        result = self.setup()
        self.assertEqual(result.returncode, 1)
        self.assertIn("  .claude/skills/x/SKILL.md\n  AGENTS.md\n", result.stderr)
        self.assertIn("nothing was changed", result.stderr)
        self.assertEqual(read(os.path.join(self.amos, "AGENTS.md")), "old\n")
        self.assertFalse(os.path.exists(os.path.join(self.amos, ".amos-workspace")))
        self.assertEqual(self.leftovers(), [])

    def test_second_run_only_runs_install(self):
        self.setup()
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("already set up", result.stdout)
        self.assertIn("install ran", result.stdout)
        self.assertNotIn("cloning", result.stdout)

    def test_refuses_a_git_checkout_a_folder_inside_a_repo_and_home(self):
        sh("git", "init", "-q", cwd=self.amos, env=self.env)
        result = self.setup()
        self.assertEqual(result.returncode, 1)
        self.assertIn("is a git checkout", result.stderr)

        inside = os.path.join(self.amos, "sub")
        os.makedirs(inside)
        result = self.setup(inside)
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"is inside the git repo {self.amos}", result.stderr)

        result = self.setup(self.env["HOME"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("not installing into", result.stderr)
        self.assertEqual(os.listdir(self.env["HOME"]), [])

    def test_repos_already_in_the_folder_keep_their_own_git(self):
        connect = os.path.join(self.amos, "amos-connect")
        sh("git", "init", "-q", "-b", "dev", cwd=connect, env=self.env)
        write(connect, "app.py", "x = 1\n")
        sh("git", "add", "-A", cwd=connect, env=self.env)
        sh("git", "commit", "-q", "-m", "connect", cwd=connect, env=self.env)
        write(connect, "app.py", "x = 2\n")  # uncommitted work
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sh("git", "rev-parse", "--show-toplevel", cwd=connect, env=self.env).stdout.strip(), connect)
        self.assertEqual(sh("git", "status", "--porcelain", cwd=connect, env=self.env).stdout, " M app.py\n")
        self.assertEqual(sh("git", "branch", "--show-current", cwd=connect, env=self.env).stdout.strip(), "dev")
        # The workspace's git never sees inside the repo, and the repo's git never sees the workspace.
        self.assertEqual(self.store("status", "--porcelain", "--untracked-files=no"), "")
        self.assertEqual(sh("git", "ls-files", cwd=connect, env=self.env).stdout, "app.py\n")

    def test_refuses_a_maintainer_clone_of_the_workspace_and_changes_nothing(self):
        os.rmdir(os.path.join(self.amos, "amos-connect"))
        os.remove(os.path.join(self.amos, "notes.md"))
        os.rmdir(self.amos)
        sh("git", "clone", "-q", os.path.join(self.env["AMOS_GIT_BASE"], "amos-workspace.git"), self.amos,
           env=self.env)
        head = sh("git", "rev-parse", "HEAD", cwd=self.amos, env=self.env).stdout
        before = sorted(os.listdir(self.amos))
        result = self.setup()
        self.assertEqual(result.returncode, 1)
        self.assertIn("is a git checkout (it has .git). If it's amos-workspace, it's already installed", result.stderr)
        self.assertNotIn("install ran", result.stdout)
        self.assertEqual(sorted(os.listdir(self.amos)), before)
        self.assertFalse(os.path.exists(os.path.join(self.amos, ".amos-workspace", "store.git")))
        self.assertEqual(sh("git", "rev-parse", "HEAD", cwd=self.amos, env=self.env).stdout, head)

    def test_refuses_a_git_file_and_a_folder_that_is_some_other_repo(self):
        write(self.amos, ".git", "gitdir: /somewhere/else\n")  # a worktree or submodule checkout
        result = self.setup()
        self.assertEqual(result.returncode, 1)
        self.assertIn("is a git checkout", result.stderr)
        self.assertEqual(read(os.path.join(self.amos, ".git")), "gitdir: /somewhere/else\n")

        result = self.setup(os.path.join(self.amos, "amos-connect"))  # a plain folder: still fine
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_maintainer_clone_switched_to_the_setup_layout_is_then_just_installed(self):
        os.rmdir(os.path.join(self.amos, "amos-connect"))
        os.remove(os.path.join(self.amos, "notes.md"))
        os.rmdir(self.amos)
        sh("git", "clone", "-q", os.path.join(self.env["AMOS_GIT_BASE"], "amos-workspace.git"), self.amos,
           env=self.env)
        # The switch in docs/amos-workspace.md, "How amos/ holds the workspace".
        os.rename(os.path.join(self.amos, ".git"), os.path.join(self.amos, ".amos-workspace", "store.git"))
        self.store("config", "core.worktree", "../..")
        result = self.setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("already set up", result.stdout)
        self.assertEqual(self.store("status", "--porcelain", "--untracked-files=no"), "")

    def test_failed_clone_leaves_nothing_behind(self):
        result = self.setup(env={"AMOS_GIT_BASE": os.path.join(self.tmp.name, "nowhere")})
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not clone", result.stderr)
        self.assertIn("ssh -T git@github.com", result.stderr)
        self.assertEqual(sorted(os.listdir(self.amos)), ["amos-connect", "notes.md"])

    def test_failed_install_keeps_the_workspace_and_says_what_to_run(self):
        result = self.setup(env={"FAKE_INSTALL_EXIT": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("needs the errors above fixed", result.stderr)
        self.assertTrue(os.path.isdir(os.path.join(self.amos, ".amos-workspace", "store.git")))


if __name__ == "__main__":
    unittest.main()
