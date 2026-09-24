#!/usr/bin/env bash
# Copyright 2024 The Operator-SDK Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");

set -o errexit
set -o nounset
set -o pipefail

MAX_LINES="${MAX_LINES:-600}"
EXCEPTIONS_FILE="docs/architecture-file-exceptions.md"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

oversized=()
while IFS= read -r -d '' file; do
  rel="${file#./}"

  case "$rel" in
    vendor/*|testdata/*|internal/bindata/*) continue ;;
  esac
  [[ "$(basename "$rel")" == zz_generated* ]] && continue
  [[ "$rel" == *fakes/* ]] && continue
  [[ "$rel" == *.pb.go ]] && continue

  if head -n3 "$file" | grep -qE '(DO NOT EDIT|Code generated)'; then
    continue
  fi

  lines=$(wc -l < "$file")
  if (( lines > MAX_LINES )); then
    if [[ -f "$EXCEPTIONS_FILE" ]] && grep -qF "$rel" "$EXCEPTIONS_FILE"; then
      continue
    fi
    oversized+=("$rel ($lines lines)")
  fi
done < <(find ./cmd ./internal ./hack -name '*.go' -print0 2>/dev/null)

if [[ ${#oversized[@]} -gt 0 ]]; then
  echo "Error: the following files exceed the ${MAX_LINES}-line limit:" >&2
  printf '  %s\n' "${oversized[@]}" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  1. Refactor the file into smaller units" >&2
  echo "  2. Add an exception to ${EXCEPTIONS_FILE} with justification" >&2
  exit 1
fi

echo "All first-party Go files are within the ${MAX_LINES}-line limit."
