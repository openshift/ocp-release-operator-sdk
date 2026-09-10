#!/usr/bin/env bash
# Copyright 2024 The Operator-SDK Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");

# Shell-based commit message validation tests (no Node.js required).
# Mirrors the rules in commitlint.config.js.

set -o errexit
set -o nounset
set -o pipefail

PASS=0
FAIL=0

validate_header() {
  local header="$1"
  [[ -z "$header" ]] && return 1
  [[ ${#header} -gt 70 ]] && return 1
  # Downstream carry/drop format
  [[ "$header" =~ ^UPSTREAM:[[:space:]]+\<(carry|drop)\>:[[:space:]]+[^[:space:]] ]] && return 0
  # Subsystem or conventional commits format
  [[ "$header" =~ ^[a-zA-Z][a-zA-Z0-9/_.\(\)-]*:[[:space:]]+[^[:space:]] ]] && return 0
  return 1
}

check() {
  local expected=$1
  local msg=$2

  if validate_header "$msg"; then
    if [[ "$expected" == "pass" ]]; then
      PASS=$((PASS + 1))
    else
      echo "FAIL: expected rejection but passed: $msg"
      FAIL=$((FAIL + 1))
    fi
  else
    if [[ "$expected" == "fail" ]]; then
      PASS=$((PASS + 1))
    else
      echo "FAIL: expected pass but rejected: $msg"
      FAIL=$((FAIL + 1))
    fi
  fi
}

# Valid formats
check pass "olm: fix client initialization"
check pass "internal/helm: refactor controller"
check pass "UPSTREAM: <carry>: adjust image references"
check pass "UPSTREAM: <drop>: update vendor directory"
check pass "hack: update CI scripts"
check pass "feat(olm): add new subcommand"
check pass "fix(helm): correct reconciler race"

# Invalid formats
check fail ""
check fail "no colon or subsystem here"
check fail "$(printf '%0.s=' {1..80})"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
