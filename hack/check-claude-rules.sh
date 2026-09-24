#!/usr/bin/env bash
# Copyright 2024 The Operator-SDK Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");

set -o errexit
set -o nounset
set -o pipefail

REQUIRED_FILES=(
  ".claude/rules/go.md"
  ".claude/rules/ci.md"
  ".claude/rules/release-and-patches.md"
  ".claude/rules/docs.md"
)

ROOT="$(git rev-parse --show-toplevel)"
missing=()

for f in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${ROOT}/${f}" ]]; then
    missing+=("$f")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: missing required .claude/rules/ files:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

echo "All required .claude/rules/ files present."
