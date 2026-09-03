#!/usr/bin/env bash
#
# Periodic / CI entrypoint for rebasing openshift/ocp-release-operator-sdk onto
# a newer upstream Operator SDK release tag (OAPE-829).
#
# Uses ./UPSTREAM-MERGE.sh for the merge. Opens a PR; does not auto-merge.
#
# Environment:
#   FORCE_TAG              Optional. Rebase this tag instead of scanning for newest.
#   REBASE_BRANCH          Downstream branch to rebase onto (default: main).
#   UPSTREAM_REMOTE        Remote name for upstream SDK (default: upstream).
#   UPSTREAM_URL           URL for the upstream remote (default: https://github.com/operator-framework/operator-sdk.git).
#   ORIGIN_REMOTE          Remote name to push PR branch (default: origin).
#   ORIGIN_URL             URL for the origin remote (default: https://github.com/${DEST_ORG_REPO}.git).
#   DEST_ORG_REPO          GitHub org/repo for PRs (default: openshift/ocp-release-operator-sdk).
#   GITHUB_TOKEN           Token for push + gh pr create (minted by the periodic job).
#   DRY_RUN                If set to 1, only report what would happen (no merge/push/PR).
#   SKIP_PUSH              If set to 1, run merge + patch gate but do not push/PR.
#   SKIP_BUILD             If set to 1, only run `make -f ci/prow.Makefile patch`.
#   FORCE_ORIGIN_URL       If set to 1, allow rewriting an existing origin remote whose
#                          org/repo differs from DEST_ORG_REPO (e.g. a developer fork).
#                          Default 0 — the script aborts instead to protect local config.
#   GIT_AUTHOR_NAME        Git identity for commits (default: openshift-app-platform-shift-bot).
#   GIT_AUTHOR_EMAIL       Git identity email (default: 267347085+openshift-app-platform-shift-bot@users.noreply.github.com).
#
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

REBASE_BRANCH=${REBASE_BRANCH:-main}
UPSTREAM_REMOTE=${UPSTREAM_REMOTE:-upstream}
ORIGIN_REMOTE=${ORIGIN_REMOTE:-origin}
DEST_ORG_REPO=${DEST_ORG_REPO:-openshift/ocp-release-operator-sdk}
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/operator-framework/operator-sdk.git}
ORIGIN_URL=${ORIGIN_URL:-https://github.com/${DEST_ORG_REPO}.git}
DRY_RUN=${DRY_RUN:-0}
SKIP_PUSH=${SKIP_PUSH:-0}
SKIP_BUILD=${SKIP_BUILD:-0}
FORCE_ORIGIN_URL=${FORCE_ORIGIN_URL:-0}
GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-openshift-app-platform-shift-bot}
GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-267347085+openshift-app-platform-shift-bot@users.noreply.github.com}

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Compare release-only semver tags (vMAJOR.MINOR.PATCH). sort -V does not
# guarantee correct ordering for pre-release suffixes.
version_gt() {
  local a=${1#v} b=${2#v}
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" && "$a" != "$b" ]]
}

# Extract owner/repo from a GitHub URL (strips scheme, host, .git, trailing slash).
_extract_org_repo() {
  local url=$1
  url=${url%.git}
  url=${url%/}
  url=${url#*github.com[:/]}
  url=${url#*github.com/}
  printf '%s\n' "$url"
}

ensure_remote() {
  local name=$1 url=$2
  if git remote get-url "$name" >/dev/null 2>&1; then
    local current
    current=$(git remote get-url "$name")
    if [[ "$current" != "$url" ]]; then
      if [[ "$name" == "$ORIGIN_REMOTE" ]]; then
        local cur_repo exp_repo
        cur_repo=$(_extract_org_repo "$current")
        exp_repo=$(_extract_org_repo "$url")
        if [[ "$cur_repo" == "$exp_repo" ]]; then
          log "Origin org/repo matches (${cur_repo}); keeping existing URL"
          return 0
        fi
        if [[ "$FORCE_ORIGIN_URL" != "1" ]]; then
          die "Origin remote points at ${cur_repo} but expected ${exp_repo}. Set FORCE_ORIGIN_URL=1 to overwrite, or set ORIGIN_URL to match your fork."
        fi
      fi
      log "Rewriting remote ${name}: ${current} -> ${url}"
      git remote set-url "$name" "$url"
    fi
  else
    git remote add "$name" "$url"
  fi
}

load_github_token() {
  [[ -n "${GITHUB_TOKEN:-}" ]]
}

configure_git_identity() {
  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"
}

_CRED_CONFIGURED=0
setup_credential_helper() {
  [[ "$_CRED_CONFIGURED" -eq 0 ]] || return 0
  [[ -n "${GITHUB_TOKEN:-}" ]] || return 0
  local cred_file
  cred_file=$(mktemp)
  chmod 600 "$cred_file"
  printf 'https://x-access-token:%s@github.com\n' "$GITHUB_TOKEN" >"$cred_file"
  git config credential.helper "store --file=${cred_file}"
  # shellcheck disable=SC2064
  trap "rm -f '${cred_file}'" EXIT
  _CRED_CONFIGURED=1
}

configure_origin_auth() {
  setup_credential_helper
}

ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    return 0
  fi
  local gh_version=2.62.0
  local arch
  case "$(uname -m)" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)       die "Unsupported architecture: $(uname -m)" ;;
  esac
  local tarball="gh_${gh_version}_linux_${arch}.tar.gz"
  local tmpdir
  tmpdir=$(mktemp -d)
  log "Installing gh ${gh_version} (${arch})"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_version}/${tarball}" \
    -o "${tmpdir}/${tarball}"
  tar -C "$tmpdir" -xzf "${tmpdir}/${tarball}"
  mkdir -p "${HOME}/bin"
  install -m 0755 "${tmpdir}/gh_${gh_version}_linux_${arch}/bin/gh" /usr/local/bin/gh || \
    install -m 0755 "${tmpdir}/gh_${gh_version}_linux_${arch}/bin/gh" "${HOME}/bin/gh"
  rm -rf "$tmpdir"
  export PATH="${HOME}/bin:${PATH}"
  command -v gh >/dev/null 2>&1 || die "gh CLI is required but could not be installed"
}

current_pin() {
  local pin
  pin=$(tr -d '[:space:]' <UPSTREAM-VERSION)
  [[ -n "$pin" ]] || die "UPSTREAM-VERSION is empty"
  printf '%s\n' "$pin"
}

newest_upstream_tag() {
  local pin=$1 tag newest=""
  while IFS= read -r tag; do
    # Release tags only: vMAJOR.MINOR.PATCH
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if version_gt "$tag" "$pin"; then
      if [[ -z "$newest" ]] || version_gt "$tag" "$newest"; then
        newest=$tag
      fi
    fi
  done < <(git tag -l 'v*' --sort=-v:refname)
  printf '%s\n' "$newest"
}

open_pr_exists() {
  local tag=$1
  command -v gh >/dev/null 2>&1 || return 1
  [[ -n "${GITHUB_TOKEN:-}" ]] || return 1
  local branch="${tag}-rebase-${REBASE_BRANCH}"
  local count
  count=$(gh pr list --repo "$DEST_ORG_REPO" --state open --head "$branch" \
    --json headRefName --jq 'length') || die "gh pr list failed for branch ${branch}"
  [[ "$count" -gt 0 ]]
}

update_golang_builder() {
  local new_go current_go
  new_go=$(awk '/^go /{split($2, a, "."); print a[1]"."a[2]}' go.mod)
  [[ -n "$new_go" ]] || { log "WARNING: could not parse go version from go.mod"; return 0; }

  current_go=$(sed -n 's/.*golang-\([0-9]*\.[0-9]*\).*/\1/p' .ci-operator.yaml | head -1)
  [[ -n "$current_go" ]] || { log "WARNING: could not parse golang version from .ci-operator.yaml"; return 0; }

  if [[ "$new_go" == "$current_go" ]]; then
    log "Golang version unchanged (${current_go}); no builder update needed"
    return 0
  fi

  log "Updating golang builder: ${current_go} -> ${new_go}"
  local escaped="${current_go//./\\.}"
  sed -i "s/golang-${escaped}/golang-${new_go}/" .ci-operator.yaml

  if [[ -f release/helm/Dockerfile ]]; then
    sed -i "s/golang-${escaped}/golang-${new_go}/" release/helm/Dockerfile
  fi

  git add .ci-operator.yaml
  git add release/helm/Dockerfile 2>/dev/null || true
  if ! git diff --staged --quiet; then
    git commit -m "UPSTREAM: <carry>: updates golang version from ${current_go} to ${new_go}"
  fi
}

run_patch_gate() {
  local failed=0
  log "Running patch gate"
  if ! make -f ci/prow.Makefile patch; then
    log "WARNING: make -f ci/prow.Makefile patch failed"
    failed=1
  elif [[ "$SKIP_BUILD" != "1" ]]; then
    if ! make -f ci/prow.Makefile build; then
      log "WARNING: make -f ci/prow.Makefile build failed"
      failed=1
    fi
  fi
  log "Restoring working tree after patch gate"
  git checkout -- . 2>&1 || true
  rm -rf build/
  find . -name '*.orig' -not -path './.git/*' -delete 2>/dev/null || true
  return "$failed"
}

create_pr() {
  local tag=$1 branch=$2 patch_ok=$3 old_pin=$4
  local title body
  title="Rebase to ${tag}"
  body=$(cat <<EOF
## Summary
Automated rebase of downstream Helm Operator midstream onto upstream Operator SDK \`${tag}\` via \`./UPSTREAM-MERGE.sh\` (OAPE-829).

- Previous upstream pin: \`${old_pin}\`
- Patch gate: $([[ "$patch_ok" == "1" ]] && echo "passed \`make -f ci/prow.Makefile patch/build\`" || echo "**failed** — please fix/recreate patches before merge").

## Manual follow-up
- Review conflict fallout (script prefers upstream on conflicts).
- Add any needed \`UPSTREAM: <carry>:\` commits.
- Do **not** auto-merge until patches and CI are green.

## Test plan
- [ ] \`make -f ci/prow.Makefile patch build\`
- [ ] Presubmit unit / sanity / e2e-helm
EOF
)
  # WIP label may not exist in the repo; fall back to unlabeled PR.
  if [[ "$patch_ok" != "1" ]]; then
    gh pr create --repo "$DEST_ORG_REPO" --base "$REBASE_BRANCH" --head "$branch" \
      --title "$title" --body "$body" --label "do-not-merge/work-in-progress" \
      || gh pr create --repo "$DEST_ORG_REPO" --base "$REBASE_BRANCH" --head "$branch" \
        --title "$title" --body "$body"
  else
    gh pr create --repo "$DEST_ORG_REPO" --base "$REBASE_BRANCH" --head "$branch" \
      --title "$title" --body "$body"
  fi
}

main() {
  local pin tag branch patch_ok=1

  # Fetch upstream tags using URL directly — avoid rewriting remotes before DRY_RUN.
  log "Fetching upstream tags"
  git fetch -t "$UPSTREAM_URL"

  pin=$(current_pin)
  if [[ -n "${FORCE_TAG:-}" ]]; then
    tag=$FORCE_TAG
    log "FORCE_TAG set: ${tag}"
  else
    tag=$(newest_upstream_tag "$pin")
  fi

  if [[ -z "$tag" ]]; then
    log "No newer upstream release tag than ${pin}; nothing to do"
    exit 0
  fi

  if ! version_gt "$tag" "$pin" && [[ -z "${FORCE_TAG:-}" ]]; then
    log "Selected tag ${tag} is not newer than pin ${pin}; nothing to do"
    exit 0
  fi

  branch="${tag}-rebase-${REBASE_BRANCH}"
  log "Candidate rebase: ${pin} -> ${tag} (branch ${branch})"

  # Check remote branch existence using URL directly (no remote rewrite needed).
  if git ls-remote --exit-code --heads "$ORIGIN_URL" "$branch" >/dev/null 2>&1; then
    log "Remote branch ${branch} already exists; skipping"
    exit 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN=1: would run ./UPSTREAM-MERGE.sh ${tag} ${REBASE_BRANCH} ${UPSTREAM_REMOTE}"
    exit 0
  fi

  # Beyond this point we mutate the tree — reject untracked files that git clean
  # in run_patch_gate would destroy.
  if [[ -n "$(git status --porcelain)" ]]; then
    die "Working tree must be clean (including untracked files) before mutating"
  fi

  ensure_remote "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
  ensure_remote "$ORIGIN_REMOTE" "$ORIGIN_URL"

  git fetch "$ORIGIN_REMOTE" "$REBASE_BRANCH" || git fetch "$ORIGIN_REMOTE"

  load_github_token || log "WARNING: no GITHUB_TOKEN; push/PR may fail"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    ensure_gh
    export GH_TOKEN="$GITHUB_TOKEN"
    if open_pr_exists "$tag"; then
      log "Open PR for ${tag} already exists; skipping"
      exit 0
    fi
  fi

  configure_git_identity
  configure_origin_auth

  # Ensure rebase target branch exists locally and tracks origin.
  git checkout -B "$REBASE_BRANCH" "$ORIGIN_REMOTE/$REBASE_BRANCH"
  git branch --set-upstream-to="$ORIGIN_REMOTE/$REBASE_BRANCH" "$REBASE_BRANCH"

  # Drop a stale local rebase branch from a previous attempt.
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    git branch -D "$branch"
  fi

  trap 'log "FAILED (rc=$?) on branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"' ERR

  log "Running UPSTREAM-MERGE.sh ${tag} ${REBASE_BRANCH} ${UPSTREAM_REMOTE}"
  ./UPSTREAM-MERGE.sh "$tag" "$REBASE_BRANCH" "$UPSTREAM_REMOTE"

  update_golang_builder

  if ! run_patch_gate; then
    patch_ok=0
  fi

  if [[ "$SKIP_PUSH" == "1" ]]; then
    log "SKIP_PUSH=1: merge complete on ${branch}; not pushing"
    exit 0
  fi

  [[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN required to push and open PR"

  log "Pushing ${branch}"
  git push -u "$ORIGIN_REMOTE" "$branch"

  log "Opening pull request"
  create_pr "$tag" "$branch" "$patch_ok" "$pin"
  log "Auto-rebase complete for ${tag}"
}

main "$@"
