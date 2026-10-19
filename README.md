# Amos-Workspace: Installer

Sets up the Amos developer workspace. You need access to the Amos GitHub organisation, an SSH key that works with GitHub (`ssh -T git@github.com`), git, bash and Python 3.

In the folder that holds (or will hold) your Amos repos:

```bash
curl -fsSL https://raw.githubusercontent.com/amos-ie/amos-workspace-installer/main/setup.sh | bash
```

`setup.sh` clones the workspace over SSH and checks its files out into the folder. It keeps the workspace's git data in `.amos-workspace/store.git` rather than `.git`, so the folder itself isn't a git repo. It never overwrites a file: if any workspace file is already in the folder, it lists them and stops without changing anything. Old copies of the Amos skills and rules that the workspace doesn't track (untracked files in `.claude/skills/`, `.cursor/rules/`, `.cursor/commands/` and `.cursor/skills/`) would contradict the new ones, so it moves them into a `.amos-workspace-backup-<timestamp>/` folder in your amos/ folder and tells you. Nothing is deleted; move a file back if it was your own. Then it runs the workspace's own `install.sh`, which does the rest of the setup and keeps the workspace up to date.

Everything else (what the workspace is, what `install.sh` does, the tools it needs) is in the workspace's README, which you'll have once setup has run.
