# Amos-Workspace: Installer

Sets up your `amos/` folder: the shared coding rules, skills and checks that Claude Code and Cursor use on every Amos repo, plus the Amos repos cloned inside it. What the workspace is and how to use it day to day is in its README, which you'll have once setup has run.

## Install

In the folder that holds (or will hold) your Amos repos, for example `~/amos`:

`curl -fsSL https://raw.githubusercontent.com/amos-ie/amos-workspace-installer/main/setup.sh | bash`

This clones the workspace into the folder, clones every Amos repo you don't have yet (on `dev`), downloads Ruff and gitleaks, and installs the pre-commit hook in each repo. The folder itself isn't a git repo (the workspace's git data is in `.amos-workspace/store.git`), so the editor's Source Control panel lists just your Amos repos. Run it again at any time to update.

Your repos and personal files are never touched or deleted. If the folder already has a file the workspace also has (such as `.cursorignore` or `.vscode/settings.json`), or an old copy of an Amos skill or rule, setup moves it into `.amos-workspace-backup-<timestamp>/` and lists it. Merge back anything you still need.

If `amos/` is already a git clone of amos-workspace (it has `.git`), setup refuses: that is the maintainer layout.

## Then open the folder in your editor

Open `amos/` in VS Code or Cursor and install the recommended extensions (Extensions → `@recommended`). **Ruff** is the one that matters: it sorts imports on save.

If the editor asks **"Allow automatic tasks?"**, choose Allow. From then on `install.sh` runs each time you open `amos/`, keeping the workspace up to date. If it never asks, or you chose Disallow, nothing is broken: update by hand with `bash .amos-workspace/scripts/install.sh`.

## If something goes wrong

- **Could not clone:** check your network or VPN, and your GitHub SSH key.
- **`install.sh` reports an `ERROR`:** each one says what to do. Fix it, then run `.amos-workspace/scripts/install.sh` in `amos/`. The output is also in `.amos-workspace/install.log`.
