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
# and git there only ever finds your Amos repos. It never overwrites or deletes a file: if a
# workspace file already exists in the folder (a .cursorignore of your own, say), it moves yours
# into a timestamped backup folder, keeping its path, and says so.
# Old copies of the Amos skills and rules (from the earlier distribute.sh) that the workspace
# doesn't track would sit beside the new ones and contradict them, so it moves those into the
# same backup folder, and says so.
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

# Red where a person reads the output: a terminal on both stdout and stderr (still true when
# the script itself comes through a pipe from curl), unless NO_COLOR is set.
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ] && [ -t 2 ]; then
  RED=$'\033[31m' RESET=$'\033[0m'
else
  RED="" RESET=""
fi
# error_line <text>: print an error line to stderr, in red where colour is on.
error_line() { printf '%s\n' "$RED$1$RESET" >&2; }

fail() {
  error_line "setup: ERROR: $1"
  exit 1
}

# Folders the AI tools load every file from. Untracked files in them are old copies.
STALE_DIRS=(.claude/skills .cursor/rules .cursor/commands .cursor/skills)

# The backup folder, made on the first file moved into it.
BACKUP=""

# move_to_backup <target> <file>: move target/file into the backup folder, keeping its path.
move_to_backup() {
  local target="$1" file="$2"
  if [ -z "$BACKUP" ]; then
    BACKUP="$target/.amos-workspace-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
  fi
  mkdir -p "$BACKUP/$(dirname "$file")"
  mv "$target/$file" "$BACKUP/$file"
}

# back_up_clashes <target> <store>: move files the workspace is about to check out, and that
# already exist in target, into the backup folder, and say what moved.
back_up_clashes() {
  local target="$1" store="$2" path
  local clashes=()
  while IFS= read -r -d '' path; do
    if [ -e "$target/$path" ] || [ -L "$target/$path" ]; then
      clashes+=("$path")
    fi
  done < <(git --git-dir="$store" ls-tree -r -z --name-only HEAD)
  [ "${#clashes[@]}" -gt 0 ] || return 0
  for path in "${clashes[@]}"; do
    move_to_backup "$target" "$path"
  done
  echo "setup: ${#clashes[@]} of your files are also amos-workspace files. amos-workspace's copies"
  echo "setup: replace them, and yours were moved into $BACKUP:"
  printf 'setup:   %s\n' "${clashes[@]}"
  echo "setup: Merge anything of yours you still need back into the new files."
  echo
}

# back_up_stale <target> <store>: move files in STALE_DIRS that the workspace doesn't track into
# the backup folder, keeping their paths, and say what moved.
back_up_stale() {
  local target="$1" store="$2" dir file count=0 tracked
  tracked="$(git --git-dir="$store" -c core.quotepath=off ls-tree -r --name-only HEAD)"
  for dir in "${STALE_DIRS[@]}"; do
    [ -d "$target/$dir" ] || continue
    while IFS= read -r -d '' file; do
      file="${file#"$target"/}"
      if grep -Fxq -- "$file" <<<"$tracked"; then
        continue
      fi
      move_to_backup "$target" "$file"
      count=$((count + 1))
    done < <(find "$target/$dir" \( -type f -o -type l \) -print0)
    # Leave no empty folders behind where old skills were.
    find "$target/$dir" -mindepth 1 -depth -type d -empty -delete
  done
  if [ "$count" -gt 0 ]; then
    echo "setup: moved $count old skill, rule or command file(s) that amos-workspace doesn't use into"
    echo "setup:   $BACKUP"
    echo "setup: they would have contradicted the new rules. Move one back if you wrote it yourself."
    echo
  fi
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

  # Before the checkout, so a failure here leaves nothing half-installed: a rerun starts clean.
  back_up_clashes "$target" "$tmp/store.git"
  back_up_stale "$target" "$tmp/store.git"

  # read-tree refuses to overwrite a file, so nothing is lost if one appeared since the backup.
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
