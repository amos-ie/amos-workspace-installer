# amos-workspace-installer

Sets up the Amos developer workspace. You need access to the Amos GitHub organisation, an SSH key that works with GitHub (`ssh -T git@github.com`), git, bash and Python 3.

In the folder that holds (or will hold) your Amos repos:

```bash
mkdir -p ~/amos && cd ~/amos
curl -fsSL https://raw.githubusercontent.com/amos-ie/amos-workspace-installer/main/setup.sh | bash
```

`setup.sh` clones the workspace over SSH and checks its files out into the folder. It keeps the workspace's git data in `.amos-workspace/store.git` rather than `.git`, so the folder itself isn't a git repo. It never overwrites a file: if any workspace file is already in the folder, it lists them and stops without changing anything. Then it runs the workspace's own `install.sh`, which does the rest of the setup and keeps the workspace up to date.

Everything else (what the workspace is, what `install.sh` does, the tools it needs) is in the workspace's README, which you'll have once setup has run.

## Changing the script

`setup.sh` is the only thing here. Run the tests before pushing (Python 3 standard library only):

```bash
python3 -m unittest -v tests/test_setup.py
shellcheck setup.sh
```
