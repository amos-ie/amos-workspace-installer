# Amos-Workspace: Installer

Sets up the Amos developer workspace: your `amos/` folder, with the shared coding rules, skills and checks that Claude Code and Cursor use on every Amos repo, and the Amos repos cloned inside it. This is the one place the install steps are written down. What the workspace is and how to use it day to day is in its README, which you'll have once setup has run.

## Before you start

**Supported setups: macOS, Linux, and Windows using WSL remote mode.** On Windows, keep `amos/` inside WSL and open it with the editor's WSL remote mode (the window's bottom-left corner shows "WSL"). A native Windows editor isn't supported: the editor hooks quietly do nothing there, and the pre-commit hook refuses the commit.

You need:

- Access to the Amos GitHub organisation, and an SSH key that works with GitHub (`ssh -T git@github.com`).
- git, bash and Python 3.
- **Ruff**, the Python linter, and **gitleaks**, the secret scanner. The checks and the pre-commit hook fail without them, and `install.sh` reports an `ERROR` until they are installed:

  ```bash
  pipx install ruff==0.16.10    # the version the workspace pins. No pipx? brew install pipx (macOS) or sudo apt install pipx (WSL/Linux)
  brew install gitleaks         # 8.19.1 or later. WSL/Linux without brew: https://github.com/gitleaks/gitleaks#installing
  ```

  If the workspace moves to a newer Ruff or gitleaks, `install.sh` tells you the version it wants and the command to install it.

## Install

In the folder that holds (or will hold) your Amos repos, for example `~/amos`:

```bash
mkdir -p ~/amos && cd ~/amos
curl -fsSL https://raw.githubusercontent.com/amos-ie/amos-workspace-installer/main/setup.sh | bash
```

Or name the folder: `... | bash -s -- ~/Projects/amos`.

`setup.sh` clones the workspace over SSH and checks its files out into the folder. It keeps the workspace's git data in `.amos-workspace/store.git` rather than `.git`, so the folder itself isn't a git repo: `git` there only finds your Amos repos, and the editor's Source Control panel lists just them.

Then it runs the workspace's own `install.sh`, which pulls the latest workspace, clones every Amos repo you don't have yet (checking out `dev`), checks your Ruff and gitleaks versions, and installs the pre-commit hook in each repo. A repo that is already in the folder is never switched, but its `dev` branch is fast-forwarded when that is safe (otherwise it is left alone).

Run it again in a folder it has already set up and it just runs `install.sh`.

## Then open the folder in your editor

Open `amos/` in VS Code (with Claude Code) or Cursor, and install the **Ruff** extension (`charliermarsh.ruff`, by Astral). Both editors offer it under Extensions → `@recommended`.

The first time, the editor asks **"Allow automatic tasks?"**: choose Allow. From then on `install.sh` runs each time you open `amos/`, which keeps the workspace up to date.

## A folder that already has files in it

If you already have an `amos/` folder with repos and personal files in it, run the same command there. Your repos and personal files are never touched. Setup never overwrites or deletes a file, and it has two rules for what is already there:

- **Files the workspace also has** (usually your own `.cursorignore`, or an old copy of `AGENTS.md`, `CLAUDE.md`, `.vscode/settings.json`, `.claude/settings.json`) are replaced by the workspace's copy. Setup first moves yours into a `.amos-workspace-backup-<timestamp>/` folder in `amos/`, keeping its path, and lists each one. Merge back anything you still need.

- **Old copies of the Amos skills and rules** that the workspace doesn't have (from the earlier `distribute.sh`: files in `.claude/skills/`, `.cursor/rules/`, `.cursor/commands/` and `.cursor/skills/`) would be loaded beside the new ones and contradict them. Setup moves them into a `.amos-workspace-backup-<timestamp>/` folder in `amos/` and tells you. Nothing is deleted: if one was your own, move it back. Your own `.claude/settings.local.json` is never touched.

If `amos/` is already a git clone of amos-workspace (it has `.git`), setup refuses: that is the maintainer layout and is already installed. To switch to the setup layout, see "How amos/ holds the workspace" in the workspace's `docs/amos-workspace.md`.

## If something goes wrong

- **Could not clone:** check your network or VPN, and your GitHub SSH key (`ssh -T git@github.com`).
- **`install.sh` reports an `ERROR`:** each one says what to do. Fix it, then run `./.amos-workspace/scripts/install.sh` in `amos/`. Its output is also in `.amos-workspace/install.log`.
