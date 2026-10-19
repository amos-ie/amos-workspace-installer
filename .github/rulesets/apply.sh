#!/usr/bin/env bash
#
# Applies every ruleset JSON file in .github/rulesets/ to this repo
# (the repo this checkout's origin points at): creates the ruleset if
# none with that name exists, updates it if one does. A ruleset on the repo that no
# file here defines (for example one renamed here) is never changed or deleted, only
# listed at the end, so an admin can delete it in Settings -> Rules -> Rulesets.
#
# main's branch protection (PRs only, no deletion or force-push)
# comes from amos-ci's single-branch ruleset ("Amos Single Branch Policy"); the
# files here add only what is particular to this repo: checks.json makes the
# "Test" check (shellcheck and the tests) required on main.
#
# The required status check names in the JSON must match the job names in
# .github/workflows/test.yml. Rename a job and the check never reports, which
# blocks every PR.
#
# The same script as amos-workspace's .github/rulesets/apply.sh: it names no repo,
# so keep the two in step if either changes.
#
# Usage: .github/rulesets/apply.sh [--dry-run]
# Requires: gh (authenticated, with admin rights on the repo), jq.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RULESETS_DIR="$ROOT/.github/rulesets"
DRY_RUN="${DRY_RUN:-false}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "::error::Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

command -v gh >/dev/null || { echo "::error::gh CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "::error::jq not found" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "::error::gh is not authenticated (run: gh auth login)" >&2; exit 1; }

shopt -s nullglob
FILES=("$RULESETS_DIR"/*.json)
[[ ${#FILES[@]} -gt 0 ]] || { echo "::error::No ruleset files in $RULESETS_DIR" >&2; exit 1; }

REPO="$(git -C "$ROOT" remote get-url origin | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
[[ "$REPO" == */* ]] || { echo "::error::Could not work out owner/repo from the origin remote" >&2; exit 1; }

echo "Repo:     $REPO"
echo "Dry run:  $DRY_RUN"
echo

if ! existing="$(gh api --paginate "repos/${REPO}/rulesets" 2>&1)"; then
  echo "::error::Could not list rulesets for $REPO:" >&2
  echo "$existing" | sed 's/^/  /' >&2
  exit 1
fi

failed=()
for file in "${FILES[@]}"; do
  name="$(jq -r '.name' "$file")"
  id="$(jq -r --arg n "$name" '.[] | select(.name==$n) | .id' <<<"$existing" | head -n 1)"

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -n "$id" ]]; then
      echo "[dry-run] would UPDATE '$name' (id=$id) from $(basename "$file")"
    else
      echo "[dry-run] would CREATE '$name' from $(basename "$file")"
    fi
    continue
  fi

  if [[ -n "$id" ]]; then
    echo "Updating '$name' (id=$id)"
    method=PUT; endpoint="repos/${REPO}/rulesets/${id}"
  else
    echo "Creating '$name'"
    method=POST; endpoint="repos/${REPO}/rulesets"
  fi
  if ! out="$(gh api --method "$method" "$endpoint" --input "$file" 2>&1)"; then
    echo "  x failed for '$name':" >&2
    echo "$out" | sed 's/^/    /' >&2
    failed+=("$name")
  fi
done

# Rulesets on the repo that no file here defines.
names="$(jq -r '.name' "${FILES[@]}")"
while IFS= read -r live; do
  [[ -n "$live" ]] || continue
  grep -qxF "$live" <<<"$names" || echo "Not defined here, left as it is: '$live'. Delete it in Settings -> Rules -> Rulesets if it's no longer wanted."
done < <(jq -r '.[] | select(.source_type == "Repository") | .name' <<<"$existing")

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "::error::Failed: ${failed[*]}" >&2
  exit 1
fi
echo "Done."
