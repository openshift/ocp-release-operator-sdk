#!/usr/bin/env bash
#
# Periodic / CI entrypoint for rebasing openshift/ocp-release-operator-sdk onto
# a newer upstream Operator SDK release tag (OAPE-829).
#
# Uses ./UPSTREAM-MERGE.sh for the merge. Opens a PR; does not auto-merge.
#
# Environment:
#   OVERRIDE_TAG           Optional. Override tag discovery; rebase this specific tag.
#   REBASE_BRANCH          Downstream branch to rebase onto (default: main).
#   UPSTREAM_REMOTE        Remote name for upstream SDK (default: upstream).
#   UPSTREAM_URL           URL for the upstream remote (default: https://github.com/operator-framework/operator-sdk.git).
#   ORIGIN_REMOTE          Remote name to push PR branch (default: origin).
#   ORIGIN_URL             URL for the origin remote (default: https://github.com/${DEST_ORG_REPO}.git).
#   DEST_ORG_REPO          GitHub org/repo for PRs (default: openshift/ocp-release-operator-sdk).
#   GITHUB_TOKEN           Token for push + gh pr create (minted by the periodic job).
#   DRY_RUN                If set to 1, only report what would happen (no merge/push/PR).
#   SKIP_BUILD             If set to 1, only run `make -f ci/prow.Makefile patch`.
#   FORCE_REMOTE_URLS      If set to 1, allow rewriting an existing remote whose
#                          org/repo differs from the expected value (e.g. a developer fork).
#                          Default 0 — the script aborts instead to protect local config.
#   ALLOW_BRANCH_DELETE    If set to 1, allow deleting stale local rebase branches.
#                          Automatically enabled in CI (OPENSHIFT_CI / CI / JOB_NAME).
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
SKIP_BUILD=${SKIP_BUILD:-0}
FORCE_REMOTE_URLS=${FORCE_REMOTE_URLS:-0}
GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-openshift-app-platform-shift-bot}
GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-267347085+openshift-app-platform-shift-bot@users.noreply.github.com}

# Log to stderr so messages are not captured by $(...) command substitutions
# (e.g. target_ocp=$(_resolve_builder_ocp ...)).
log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- Cleanup (credential file only) ---
_cred_file=""
# EXIT trap: remove credential file and unset git credential helper.
_cleanup() {
  [[ -n "$_cred_file" ]] && rm -f "$_cred_file"
  git config --unset credential.helper 2>/dev/null || true
}
trap _cleanup EXIT

# True when running inside Prow / CI (checked env vars).
is_ci_context() {
  [[ -n "${OPENSHIFT_CI:-}" || -n "${CI:-}" || -n "${JOB_NAME:-}" ]]
}

# Delete a leftover local rebase branch, but only in CI or with opt-in.
cleanup_stale_branch() {
  local branch=$1
  git show-ref --verify --quiet "refs/heads/${branch}" || return 0
  if is_ci_context || [[ "${ALLOW_BRANCH_DELETE:-0}" == "1" ]]; then
    log "Deleting stale local branch ${branch}"
    git branch -D "$branch"
    return 0
  fi
  die "Local branch ${branch} already exists. Delete it manually or set ALLOW_BRANCH_DELETE=1."
}

# Return 0 if $1 is a strictly newer semver than $2 (release tags only).
version_gt() {
  local a=${1#v} b=${2#v}
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" && "$a" != "$b" ]]
}

# Replace userinfo in a URL with *** before logging.
_redact_url() {
  local url=$1
  printf '%s\n' "${url//:\/\/*@/:\/\/***@}"
}

# Extract "org/repo" from any GitHub URL form.
_extract_org_repo() {
  local url=$1
  url=${url%.git}
  url=${url%/}
  url=${url#*github.com[:/]}
  url=${url#*github.com/}
  printf '%s\n' "$url"
}

# Add or update a git remote; protects all remotes from silent org/repo overwrites.
ensure_remote() {
  local name=$1 url=$2
  if git remote get-url "$name" >/dev/null 2>&1; then
    local current
    current=$(git remote get-url "$name")
    if [[ "$current" != "$url" ]]; then
      local cur_repo exp_repo
      cur_repo=$(_extract_org_repo "$current")
      exp_repo=$(_extract_org_repo "$url")
      if [[ "$cur_repo" == "$exp_repo" ]]; then
        log "Remote ${name} org/repo matches (${cur_repo}); keeping existing URL"
        return 0
      fi
      if [[ "$FORCE_REMOTE_URLS" != "1" ]]; then
        die "Remote ${name} points at ${cur_repo} but expected ${exp_repo}. Set FORCE_REMOTE_URLS=1 to overwrite, or set the matching URL env var to match your config."
      fi
      log "Rewriting remote ${name}: $(_redact_url "$current") -> $(_redact_url "$url")"
      git remote set-url "$name" "$url"
    fi
  else
    git remote add "$name" "$url"
  fi
}

# Die if gh CLI is not on PATH (CI image must provide it).
ensure_gh() {
  command -v gh >/dev/null 2>&1 || die "gh CLI is required but not found in PATH"
}

# Set git user.name and user.email for the bot's commits.
configure_git_identity() {
  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"
}

# Write GITHUB_TOKEN to a temp file and configure git credential.helper.
setup_credential_helper() {
  [[ -n "${GITHUB_TOKEN:-}" ]] || return 0
  _cred_file=$(mktemp)
  chmod 600 "$_cred_file"
  printf 'https://x-access-token:%s@github.com\n' "$GITHUB_TOKEN" >"$_cred_file"
  git config credential.helper "store --file=${_cred_file}"
}

# Read the current upstream version pin from UPSTREAM-VERSION.
current_pin() {
  local pin
  pin=$(tr -d '[:space:]' <UPSTREAM-VERSION)
  [[ -n "$pin" ]] || die "UPSTREAM-VERSION is empty"
  printf '%s\n' "$pin"
}

# Query upstream for the newest vMAJOR.MINOR.PATCH tag beyond the pin.
newest_upstream_tag() {
  local pin=$1 tag newest=""
  while IFS=$'\t' read -r _ ref; do
    tag=${ref#refs/tags/}
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if version_gt "$tag" "$pin"; then
      if [[ -z "$newest" ]] || version_gt "$tag" "$newest"; then
        newest=$tag
      fi
    fi
  done < <(git ls-remote --tags "$UPSTREAM_URL" 'v*')
  printf '%s\n' "$newest"
}

# Return 0 if an open PR already targets the rebase branch for this tag.
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

# Pick the best OCP version from a space-separated tag list for a given Go
# version. $3 is the tag regex prefix (without the OCP suffix), e.g.
# "rhel-9-golang-1.26-openshift-" or "rhel-9-release-golang-1.26-openshift-".
_pick_ocp_from_tags() {
  local new_go=$1 current_ocp=$2 prefix=$3
  local all_tags=$4
  local best_ocp

  # Fast path: same OCP version already has the builder
  # shellcheck disable=SC2086
  if printf '%s\n' $all_tags | grep -qF "${prefix}${current_ocp}"; then
    printf '%s\n' "$current_ocp"
    return 0
  fi

  # Fallback: highest OCP version that has this Go builder
  # shellcheck disable=SC2086
  best_ocp=$(printf '%s\n' $all_tags \
    | sed -n "s/^${prefix}\([0-9][0-9]*\.[0-9][0-9]*\)$/\1/p" \
    | sort -V | tail -1)
  if [[ -n "$best_ocp" ]]; then
    printf '%s\n' "$best_ocp"
    return 0
  fi
  return 1
}

# Generate candidate OCP versions to probe when imagestreams are unavailable.
# Includes the current pin, a few forward minors, and the 5.x stream when on 4.x.
_builder_ocp_candidates() {
  local current=$1
  local major=${current%%.*}
  local minor=${current#*.}
  local i
  [[ "$minor" =~ ^[0-9]+$ ]] || return 0
  for ((i = 0; i <= 4; i++)); do
    printf '%s.%s\n' "$major" "$((minor + i))"
  done
  if [[ "$major" -eq 4 ]]; then
    for i in 0 1 2 3; do
      printf '5.%s\n' "$i"
    done
  fi
}

# True if the ocp/builder image for go+ocp is pullable/inspectable.
_builder_image_exists() {
  local new_go=$1 ocp=$2
  local ref="registry.ci.openshift.org/ocp/builder:rhel-9-golang-${new_go}-openshift-${ocp}"
  oc image info "$ref" --filter-by-os=linux/amd64 >/dev/null 2>&1
}

# Resolve the correct OCP version for a given Go builder image.
# Tries, in order:
#   1. ocp/builder imagestream (app.ci — has rhel-9-golang-* tags)
#   2. openshift/release imagestream (build farms — has rhel-9-release-golang-* tags)
#   3. oc image info against registry.ci.openshift.org for candidate OCP versions
# Returns the OCP version on stdout, or non-zero if nothing is found.
_resolve_builder_ocp() {
  local new_go=$1 current_ocp=$2
  local all_tags best_ocp ocp

  if ! command -v oc >/dev/null 2>&1; then
    log "oc not on PATH; cannot resolve builder image"
    return 1
  fi

  # 1) app.ci-style: ocp/builder with rhel-9-golang-* tags
  if all_tags=$(oc get is builder -n ocp \
      -o jsonpath='{.status.tags[*].tag}' 2>/dev/null) && [[ -n "$all_tags" ]]; then
    if best_ocp=$(_pick_ocp_from_tags "$new_go" "$current_ocp" \
        "rhel-9-golang-${new_go}-openshift-" "$all_tags"); then
      printf '%s\n' "$best_ocp"
      return 0
    fi
    log "ocp/builder has tags but none for golang-${new_go}; trying other sources"
  else
    log "ocp/builder imagestream unavailable; trying openshift/release"
  fi

  # 2) build-farm-style: openshift/release with rhel-9-release-golang-* tags
  #    (what .ci-operator.yaml pins; Dockerfile builder tags share the same OCP)
  if all_tags=$(oc get is release -n openshift \
      -o jsonpath='{.status.tags[*].tag}' 2>/dev/null) && [[ -n "$all_tags" ]]; then
    if best_ocp=$(_pick_ocp_from_tags "$new_go" "$current_ocp" \
        "rhel-9-release-golang-${new_go}-openshift-" "$all_tags"); then
      printf '%s\n' "$best_ocp"
      return 0
    fi
    log "openshift/release has tags but none for golang-${new_go}; trying registry probe"
  else
    log "openshift/release imagestream unavailable; trying registry probe"
  fi

  # 3) Direct registry inspect for a small set of candidate OCP versions
  #    (newest first so we stop at the best match)
  while IFS= read -r ocp; do
    [[ -n "$ocp" ]] || continue
    if _builder_image_exists "$new_go" "$ocp"; then
      printf '%s\n' "$ocp"
      return 0
    fi
  done < <(_builder_ocp_candidates "$current_ocp" | sort -uVr)

  return 1
}

_builder_todo=""

# Bump golang builder pins in .ci-operator.yaml and Dockerfile if needed.
# Verifies the target builder image exists via oc before committing.
update_golang_builder() {
  local new_go current_go current_ocp
  new_go=$(awk '/^go /{split($2, a, "."); print a[1]"."a[2]}' go.mod)
  [[ -n "$new_go" ]] || { log "WARNING: could not parse go version from go.mod"; return 0; }

  current_go=$(sed -n 's/.*golang-\([0-9]*\.[0-9]*\).*/\1/p' .ci-operator.yaml | head -1)
  current_ocp=$(sed -n 's/.*openshift-\([0-9]*\.[0-9]*\).*/\1/p' .ci-operator.yaml | head -1)
  [[ -n "$current_go" && -n "$current_ocp" ]] \
    || { log "WARNING: could not parse builder tag from .ci-operator.yaml"; return 0; }

  if [[ "$new_go" == "$current_go" ]]; then
    log "Golang version unchanged (${current_go}); no builder update needed"
    return 0
  fi

  local target_ocp
  if target_ocp=$(_resolve_builder_ocp "$new_go" "$current_ocp"); then
    log "Verified builder image: golang-${new_go}-openshift-${target_ocp}"
  else
    log "WARNING: no builder image found for golang-${new_go}; skipping builder bump"
    _builder_todo="Go ${current_go} -> ${new_go} (builder image not found; update \`.ci-operator.yaml\` and \`release/helm/Dockerfile\` manually)"
    return 0
  fi

  local old_suffix="golang-${current_go}-openshift-${current_ocp}"
  local new_suffix="golang-${new_go}-openshift-${target_ocp}"
  log "Updating golang builder: ${old_suffix} -> ${new_suffix}"

  sed -i "s/release-${old_suffix}/release-${new_suffix}/" .ci-operator.yaml
  if [[ -f release/helm/Dockerfile ]]; then
    sed -i "s/${old_suffix}/${new_suffix}/" release/helm/Dockerfile
  fi

  git add .ci-operator.yaml
  git add release/helm/Dockerfile 2>/dev/null || true
  if ! git diff --staged --quiet; then
    git commit -m "UPSTREAM: <carry>: updates golang builder from ${old_suffix} to ${new_suffix}"
  fi
}

# Apply patches and optionally build; restore tree afterward.
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
  find . -name '*.rej' -not -path './.git/*' -delete 2>/dev/null || true
  return "$failed"
}

# Open a PR (or draft if gate failed) for the rebase branch.
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
$([[ -n "$_builder_todo" ]] && printf '%s\n' "- [ ] **Builder image update needed**: ${_builder_todo}")
- Do **not** auto-merge until patches and CI are green.

## Test plan
- [ ] \`make -f ci/prow.Makefile patch build\`
- [ ] Presubmit unit / sanity / e2e-helm
EOF
)
  if [[ "$patch_ok" != "1" ]]; then
    gh pr create --repo "$DEST_ORG_REPO" --base "$REBASE_BRANCH" --head "$branch" \
      --title "WIP: ${title}" --body "$body" --draft \
      || die "Failed to create draft PR for ${branch}"
  else
    gh pr create --repo "$DEST_ORG_REPO" --base "$REBASE_BRANCH" --head "$branch" \
      --title "$title" --body "$body"
  fi
}

# Orchestrate: discover tag, merge, gate, push, PR.
main() {
  local pin tag branch patch_ok=1

  log "Fetching upstream tags"
  git fetch -t "$UPSTREAM_URL"

  pin=$(current_pin)
  if [[ -n "${OVERRIDE_TAG:-}" ]]; then
    tag=$OVERRIDE_TAG
    log "OVERRIDE_TAG set: ${tag}"
  else
    tag=$(newest_upstream_tag "$pin")
  fi

  if [[ -z "$tag" ]]; then
    log "No newer upstream release tag than ${pin}; nothing to do"
    exit 0
  fi

  if ! version_gt "$tag" "$pin" && [[ -z "${OVERRIDE_TAG:-}" ]]; then
    log "Selected tag ${tag} is not newer than pin ${pin}; nothing to do"
    exit 0
  fi

  branch="${tag}-rebase-${REBASE_BRANCH}"
  log "Candidate rebase: ${pin} -> ${tag} (branch ${branch})"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN=1: would run ./UPSTREAM-MERGE.sh ${tag} ${REBASE_BRANCH} ${UPSTREAM_REMOTE}"
    exit 0
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    die "Working tree must be clean (including untracked files) before mutating"
  fi

  ensure_remote "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
  ensure_remote "$ORIGIN_REMOTE" "$ORIGIN_URL"

  git fetch "$ORIGIN_REMOTE" "$REBASE_BRANCH" || git fetch "$ORIGIN_REMOTE"

  [[ -n "${GITHUB_TOKEN:-}" ]] || log "WARNING: no GITHUB_TOKEN; push/PR may fail"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    ensure_gh
    export GH_TOKEN="$GITHUB_TOKEN"
    if open_pr_exists "$tag"; then
      log "Open PR for ${tag} already exists; skipping"
      exit 0
    fi
  fi

  configure_git_identity
  setup_credential_helper

  git checkout -B "$REBASE_BRANCH" "$ORIGIN_REMOTE/$REBASE_BRANCH"
  git branch --set-upstream-to="$ORIGIN_REMOTE/$REBASE_BRANCH" "$REBASE_BRANCH"

  if is_ci_context; then
    export ALLOW_BRANCH_DELETE=1
  fi

  cleanup_stale_branch "$branch"

  trap 'log "FAILED (rc=$?) on branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"' ERR

  log "Running UPSTREAM-MERGE.sh ${tag} ${REBASE_BRANCH} ${UPSTREAM_REMOTE}"
  ./UPSTREAM-MERGE.sh "$tag" "$REBASE_BRANCH" "$UPSTREAM_REMOTE"

  update_golang_builder

  if ! run_patch_gate; then
    patch_ok=0
  fi

  [[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN required to push and open PR"

  log "Pushing ${branch}"
  git push -u "$ORIGIN_REMOTE" "$branch"

  log "Opening pull request"
  create_pr "$tag" "$branch" "$patch_ok" "$pin"
  if [[ "$patch_ok" != "1" ]]; then
    die "Patch gate failed; draft PR opened for manual fixes"
  fi
  log "Auto-rebase complete for ${tag}"
}

main "$@"
