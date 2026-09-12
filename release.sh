#!/usr/bin/env bash
#
# release.sh — merge the open pull request, tag the release, push the tag.
#
# The version is NOT invented here. Every change already bumps it in the five
# source files (CI fails otherwise, because the generated pages would stop
# reproducing), so by release time the number is sitting in the merged code.
# This script reads it, checks every file agrees, and records it as a tag.
#
#   ./release.sh              release the single open PR
#   ./release.sh 9            release PR #9
#   ./release.sh --dry-run    run every check, change nothing
#   ./release.sh -y           skip the confirmation prompt
#
set -euo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; DIM=$'\e[2m'; OFF=$'\e[0m'
ok()   { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$YEL" "$OFF" "$1"; }
die()  { printf '\n%serror:%s %s\n' "$RED" "$OFF" "$1" >&2; exit 1; }

DRY_RUN=0
ASSUME_YES=0
PR=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -h|--help)    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    ''|*[!0-9]*)  die "unrecognised argument: $arg (expected a PR number, --dry-run, -y)" ;;
    *)            PR="$arg" ;;
  esac
done

# ---------------------------------------------------------------- preconditions
printf '\n%sChecking preconditions%s\n' "$DIM" "$OFF"

command -v gh  >/dev/null 2>&1 || die "gh is not installed — https://cli.github.com"
command -v git >/dev/null 2>&1 || die "git is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run: gh auth login"
git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
ok "gh and git are ready"

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "main" ] || die "on branch '$branch' — switch to main first: git checkout main"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  git status --short --untracked-files=no >&2
  die "working tree has uncommitted changes — commit or discard them first"
fi
ok "on main with a clean working tree"

git fetch --quiet origin --prune --tags
local_head=$(git rev-parse HEAD)
remote_head=$(git rev-parse origin/main)
[ "$local_head" = "$remote_head" ] || die "main is out of sync with origin/main — run: git pull --ff-only"
ok "main is in sync with origin/main"

# ------------------------------------------------------------------- locate PR
printf '\n%sLocating the pull request%s\n' "$DIM" "$OFF"

if [ -z "$PR" ]; then
  mapfile -t open_prs < <(gh pr list --state open --json number --jq '.[].number')
  case "${#open_prs[@]}" in
    0) die "no open pull request — nothing to release (pass a PR number to override)" ;;
    1) PR="${open_prs[0]}" ;;
    *) die "${#open_prs[@]} open pull requests (${open_prs[*]}) — say which one: ./release.sh <number>" ;;
  esac
fi

pr_fields=$(gh pr view "$PR" \
  --json state,title,url,headRefName,mergeable,mergeStateStatus \
  --jq '[.state, .title, .url, .headRefName, .mergeable, .mergeStateStatus] | @tsv')
IFS=$'\t' read -r pr_state pr_title pr_url pr_head mergeable merge_state <<<"$pr_fields"

[ "$pr_state" = "OPEN" ] || die "PR #$PR is $pr_state, not OPEN"
ok "PR #$PR — $pr_title"
[ "$mergeable" = "MERGEABLE" ] || die "PR #$PR is not mergeable (mergeable=$mergeable) — rebase it on main"

# ------------------------------------------------------------------ CI must be green
checks=$(gh pr view "$PR" --json statusCheckRollup \
  --jq '.statusCheckRollup // [] | .[] | [(.conclusion // .state // "PENDING"), (.name // .context // "?")] | @tsv')
if [ -z "$checks" ]; then
  warn "no CI checks reported on this PR"
else
  failed=0
  while IFS=$'\t' read -r concl name; do
    [ -z "$name" ] && continue
    if [ "$concl" = "SUCCESS" ]; then
      ok "$name"
    else
      warn "$name is $concl"
      failed=1
    fi
  done <<<"$checks"
  [ "$failed" -eq 0 ] || die "not every check has passed — wait for CI, or fix it"
fi
[ "$merge_state" = "CLEAN" ] || warn "mergeStateStatus is $merge_state (expected CLEAN)"

# ------------------------------------------------------- version, read from the PR
printf '\n%sReading the version from the PR%s\n' "$DIM" "$OFF"

git fetch --quiet origin "pull/$PR/head:refs/release-check/$PR" --force
ref="refs/release-check/$PR"
cleanup() { git update-ref -d "refs/release-check/$PR" 2>/dev/null || true; }
trap cleanup EXIT

at() { git show "$ref:$1" 2>/dev/null || die "PR #$PR has no $1"; }

version=$(at playbook.html | sed -n 's/^const APP_VERSION="\([0-9][0-9.]*\)";.*/\1/p' | head -1)
[ -n "$version" ] || die "could not read APP_VERSION from playbook.html on the PR branch"
tag="v$version"
ok "APP_VERSION is $version"

# every file that carries the version must agree, or the release is half-stamped
mismatch=0
for f in README.md index.html build-arsenal.sh build-cheatsheet.sh; do
  if at "$f" | grep -q "v$version"; then
    ok "$f says $tag"
  else
    warn "$f does not mention $tag"
    mismatch=1
  fi
done
[ "$mismatch" -eq 0 ] || die "the version is not consistent across the source files — bump them all, then re-run"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "tag $tag already exists locally — the version was not bumped for this release"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  die "tag $tag already exists on origin — the version was not bumped for this release"
fi
ok "$tag is free"

# ------------------------------------------------------------------------ confirm
printf '\n  %sPR%s      #%s  %s\n'   "$DIM" "$OFF" "$PR" "$pr_title"
printf '  %sbranch%s  %s\n'          "$DIM" "$OFF" "$pr_head"
printf '  %saction%s  merge (rebase), tag %s, push the tag, delete the branch\n' "$DIM" "$OFF" "$tag"
printf '  %surl%s     %s\n\n'        "$DIM" "$OFF" "$pr_url"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%sdry run — nothing was changed%s\n\n' "$YEL" "$OFF"
  exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  printf 'Go ahead? [y/N] '
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) printf '\nnothing done\n\n'; exit 1 ;;
  esac
fi

# ------------------------------------------------------------------------ release
printf '\n%sReleasing%s\n' "$DIM" "$OFF"

gh pr merge "$PR" --rebase --delete-branch
ok "PR #$PR merged"

git checkout --quiet main
git pull --quiet --ff-only origin main
git fetch --quiet origin --prune          # the merged branch is gone; drop the stale ref
ok "main updated"

merged_version=$(sed -n 's/^const APP_VERSION="\([0-9][0-9.]*\)";.*/\1/p' playbook.html | head -1)
[ "$merged_version" = "$version" ] ||
  die "merged main says $merged_version but the PR said $version — tag by hand after checking what happened"
ok "merged main still says $version"

# A PR titled "v1.6.1 — ..." would otherwise give "v1.6.1 — v1.6.1 — ...".
subject="$pr_title"
case "$subject" in
  "$tag"|"$tag "*|"$tag-"*|"$tag:"*|"$tag —"*) ;;
  *) subject="$tag — $pr_title" ;;
esac

git tag -a "$tag" -m "$subject

Released from #$PR.
$pr_url"
git push --quiet origin "$tag"
ok "tagged $tag and pushed"

printf '\n%sDone.%s %s is live at %s\n\n' "$GRN" "$OFF" "$tag" "$(git rev-parse --short HEAD)"
