#!/usr/bin/env bash
# Installs amos-workspace (the shared coding rules, skills and checks for every Amos repo)
# into your amos/ folder: the folder that holds, or will hold, your Amos repos. Run it there:
#
#   curl -fsSL https://raw.githubusercontent.com/amos-ie/amos-workspace-installer/main/setup.sh | bash
#
# or name the folder:  ... | bash -s -- ~/Projects/amos
#
# It clones amos-workspace over SSH and checks its files out into the folder. amos-workspace's
# git data goes in .amos-workspace/store.git instead of .git, so the folder isn't a git repo
# and git there only ever finds your Amos repos. It never overwrites a file: if any workspace
# file already exists in the folder, it lists them all and stops, having changed nothing.
# Then it runs .amos-workspace/scripts/install.sh, which clones the Amos repos and installs
# the checks, and from then on keeps amos-workspace up to date.
#
# Run it again in a folder it has already set up and it just runs install.sh.
#
# Environment:
#   AMOS_GIT_BASE   clone URL prefix (default git@github.com:amos-ie)
set -euo pipefail

STORE=.amos-workspace/store.git
SSH_HINT="check your network or VPN, and that your GitHub SSH key works (ssh -T git@github.com)"
# The scratch folder, deleted on exit.
SCRATCH=""
trap '[ -z "$SCRATCH" ] || rm -rf "$SCRATCH"' EXIT

fail() {
  printf 'setup: ERROR: %s\n' "$1" >&2
  exit 1
}

run_install() {
  # stdin may be this script, coming through a pipe: install.sh mustn't read it.
  (cd "$1" && bash .amos-workspace/scripts/install.sh </dev/null)
}

# Everything happens in main, called on the last line, so a download cut short runs nothing.
main() {
  local target="${1:-$PWD}"
  local base="${AMOS_GIT_BASE:-git@github.com:amos-ie}"

  local tool
  for tool in git python3; do
    command -v "$tool" >/dev/null || fail "$tool is required"
  done
  [ -d "$target" ] || fail "$target is not a folder. Create your amos/ folder first (mkdir -p ~/amos), then run setup in it."
  target="$(cd "$target" && pwd -P)"
  if [ "$target" = / ] || [ "$target" = "$(cd ~ && pwd -P)" ]; then
    fail "not installing into $target. Run setup in your amos/ folder (create it first: mkdir -p ~/amos && cd ~/amos)."
  fi

  if [ -d "$target/$STORE" ]; then
    echo "setup: amos-workspace is already set up in $target, so just running install.sh"
    run_install "$target"
    return
  fi
  if [ -e "$target/.git" ]; then
    fail "$target is a git checkout (it has .git). If it's amos-workspace, it's already installed: run .amos-workspace/scripts/install.sh. Otherwise run setup in your amos/ folder, not in a repo."
  fi
  local top
  if top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    fail "$target is inside the git repo $top. Run setup in your amos/ folder, not inside a repo."
  fi

  # A scratch folder in the target, so the store moves into place with a rename.
  SCRATCH="$(mktemp -d "$target/.amos-workspace-setup.XXXXXX")"
  local tmp="$SCRATCH"

  echo "setup: cloning $base/amos-workspace.git"
  # main by name, whatever the repo's default branch: main is the released workspace,
  # and the only branch install.sh pulls for developers.
  git clone -q --branch main --no-checkout --separate-git-dir="$tmp/store.git" "$base/amos-workspace.git" "$tmp/checkout" ||
    fail "could not clone $base/amos-workspace.git (see above); $SSH_HINT."

  # List every clash, not only the first one git would stop at.
  local clashes path
  clashes="$(git --git-dir="$tmp/store.git" ls-tree -r -z --name-only HEAD | while IFS= read -r -d '' path; do
    if [ -e "$target/$path" ] || [ -L "$target/$path" ]; then
      printf '  %s\n' "$path"
    fi
  done)"
  if [ -n "$clashes" ]; then
    fail "these amos-workspace files are already in $target, so nothing was changed:
$clashes
Move them out of the way (for example into ~/amos-backup), then run setup again.
If they are old copies of the Amos rules or skills, delete them: the workspace replaces them."
  fi

  # read-tree refuses to overwrite a file, so nothing is lost if one appeared since the check.
  git --git-dir="$tmp/store.git" config core.worktree "$target"
  git --git-dir="$tmp/store.git" read-tree -m -u HEAD || fail "could not check out amos-workspace (see above)."
  mv "$tmp/store.git" "$target/$STORE"
  # Relative to the store, so the amos/ folder can be moved or renamed later.
  git --git-dir="$target/$STORE" config core.worktree ../..
  echo "setup: amos-workspace $(git --git-dir="$target/$STORE" rev-parse --short HEAD) is in $target"
  echo

  run_install "$target" || {
    echo
    echo "setup: amos-workspace is installed, but install.sh needs the errors above fixed. Then run:" >&2
    echo "  cd $target && .amos-workspace/scripts/install.sh" >&2
    exit 1
  }
  echo
  echo "setup: done. Open $target in VS Code or Cursor, and choose Allow when it asks to allow automatic tasks."
}

main "$@"
