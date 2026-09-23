#!/usr/bin/env bash
#
# E2E coverage lifecycle script for helm-operator CI and local use.
#
# Usage:
#   hack/e2e-coverage.sh setup            Prepare the sample operator deployment for coverage
#   hack/e2e-coverage.sh collect          Collect, convert, and optionally upload coverage data
#   hack/e2e-coverage.sh check-freshness  Skip periodic run if Codecov already has e2e coverage
#
# Environment variables:
#   COVERAGE_IMAGE          (setup)           Full pullspec of the coverage-instrumented image
#   CODECOV_TOKEN           (collect)         Codecov upload token; skip upload if unset
#   ARTIFACT_DIR            (collect)         Directory for CI artifacts; defaults to "."
set -euo pipefail

NAMESPACE="memcached-operator-system"
DEPLOYMENT="memcached-operator-controller-manager"
CONTAINER_NAME="manager"
POD_LABEL="control-plane=controller-manager"
GOCOVERDIR_PATH="/tmp/e2e-cover"
CODECOV_SECRET_PATH="/var/run/secrets/codecov/CODECOV_TOKEN"
CODECOV_SLUG="openshift/ocp-release-operator-sdk"

resolve_coverage_sha() {
    local sha=""

    if [[ "${JOB_TYPE:-}" == "presubmit" && -n "${PULL_PULL_SHA:-}" ]]; then
        sha="${PULL_PULL_SHA}"
    elif [[ "${JOB_TYPE:-}" == "postsubmit" && -n "${PULL_BASE_SHA:-}" ]]; then
        sha="${PULL_BASE_SHA}"
    elif [[ "${JOB_TYPE:-}" == "periodic" && -n "${JOB_SPEC:-}" ]]; then
        sha=$(echo "${JOB_SPEC}" | jq -r '
            .extra_refs[]? | select(.repo == "ocp-release-operator-sdk" and .org == "openshift") | .base_sha
        ' 2>/dev/null | head -1 || true)
    fi

    if [[ -z "${sha}" ]]; then
        sha=$(git rev-parse HEAD)
    fi
    echo "${sha}"
}

setup() {
    echo "--- E2E Coverage Setup ---"

    if [[ -z "${COVERAGE_IMAGE:-}" ]]; then
        echo "Error: COVERAGE_IMAGE env var must be set"
        exit 1
    fi
    echo "Coverage image: ${COVERAGE_IMAGE}"

    if ! oc get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" >/dev/null 2>&1; then
        echo "Error: deployment ${DEPLOYMENT} not found in ${NAMESPACE}"
        echo "Run helm e2e deploy before coverage setup."
        exit 1
    fi

    echo "Patching deployment for coverage image, GOCOVERDIR, and emptyDir..."
    oc patch deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --type=strategic -p "$(cat <<EOF
{
  "spec": {
    "template": {
      "spec": {
        "volumes": [
          {
            "name": "e2e-cover",
            "emptyDir": {}
          }
        ],
        "containers": [
          {
            "name": "${CONTAINER_NAME}",
            "image": "${COVERAGE_IMAGE}",
            "env": [
              {
                "name": "GOCOVERDIR",
                "value": "${GOCOVERDIR_PATH}"
              }
            ],
            "volumeMounts": [
              {
                "name": "e2e-cover",
                "mountPath": "${GOCOVERDIR_PATH}"
              }
            ]
          }
        ]
      }
    }
  }
}
EOF
)"

    echo "Waiting for operator rollout with coverage settings..."
    oc rollout status "deployment/${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s

    echo "Verifying GOCOVERDIR is set in the running pod..."
    oc exec -n "${NAMESPACE}" "deploy/${DEPLOYMENT}" -c "${CONTAINER_NAME}" -- env | grep GOCOVERDIR || \
        echo "Warning: GOCOVERDIR not found in pod env (non-fatal)"

    echo "--- Coverage setup complete ---"
}

collect() {
    echo "--- E2E Coverage Collection ---"

    local artifact_dir="${ARTIFACT_DIR:-.}"
    local coverage_dir="${artifact_dir}/e2e-cover-data"
    local coverage_profile="${artifact_dir}/coverage-e2e.out"

    if [[ -z "${CODECOV_TOKEN:-}" ]] && [[ -f "${CODECOV_SECRET_PATH}" ]]; then
        CODECOV_TOKEN=$(cat "${CODECOV_SECRET_PATH}")
        export CODECOV_TOKEN
    fi

    local pod
    pod=$(oc get pods -n "${NAMESPACE}" -l "${POD_LABEL}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -z "${pod}" ]]; then
        echo "Error: no operator pod found with label ${POD_LABEL}"
        echo "Coverage collection requires the operator pod to be running."
        exit 1
    fi
    echo "Found operator pod: ${pod}"

    local restart_count
    restart_count=$(oc get pod "${pod}" -n "${NAMESPACE}" \
        -o jsonpath="{.status.containerStatuses[?(@.name==\"${CONTAINER_NAME}\")].restartCount}")

    echo "Sending SIGTERM to flush coverage data (container will restart)..."
    oc exec -n "${NAMESPACE}" "${pod}" -c "${CONTAINER_NAME}" -- /bin/sh -c 'kill -TERM 1'

    echo "Waiting for container restart count to increment..."
    local expected_count=$((restart_count + 1))
    if oc wait "pod/${pod}" \
        -n "${NAMESPACE}" \
        --for="jsonpath={.status.containerStatuses[?(@.name==\"${CONTAINER_NAME}\")].restartCount}=${expected_count}" \
        --timeout=120s; then
        local current
        current=$(oc get pod "${pod}" -n "${NAMESPACE}" \
            -o jsonpath="{.status.containerStatuses[?(@.name==\"${CONTAINER_NAME}\")].restartCount}")
        echo "Container restarted (count: ${current})"
    else
        echo "Timed out waiting for container restart"
        return 1
    fi

    oc wait pod/"${pod}" --for=condition=Ready -n "${NAMESPACE}" --timeout=120s

    echo "Copying coverage data from the restarted container..."
    mkdir -p "${coverage_dir}"
    oc cp "${NAMESPACE}/${pod}:${GOCOVERDIR_PATH}/." "${coverage_dir}" -c "${CONTAINER_NAME}"

    echo "Coverage files:"
    ls -la "${coverage_dir}/" 2>/dev/null || true

    if ls "${coverage_dir}"/covmeta.* >/dev/null 2>&1; then
        echo "Converting coverage data to Go profile format..."
        go tool covdata textfmt -i="${coverage_dir}" -o="${coverage_profile}"

        echo ""
        echo "=== E2E Coverage Summary ==="
        go tool covdata percent -i="${coverage_dir}"
        echo "============================="
        echo ""
        echo "Coverage profile: ${coverage_profile} ($(wc -l < "${coverage_profile}") lines)"

        if [[ -n "${CODECOV_TOKEN:-}" ]]; then
            echo "Uploading to Codecov..."
            local codecov_dir
            codecov_dir=$(mktemp -d)
            local codecov_bin="${codecov_dir}/codecov"
            curl -sS -o "${codecov_bin}"              https://uploader.codecov.io/latest/linux/codecov
            curl -sS -o "${codecov_bin}.SHA256SUM"    https://uploader.codecov.io/latest/linux/codecov.SHA256SUM
            curl -sS -o "${codecov_bin}.SHA256SUM.sig" https://uploader.codecov.io/latest/linux/codecov.SHA256SUM.sig

            if command -v gpg >/dev/null 2>&1 && command -v gpgv >/dev/null 2>&1; then
                curl -sS https://keybase.io/codecovsecurity/pgp_keys.asc \
                    | gpg --no-default-keyring --keyring trustedkeys.gpg --import 2>/dev/null || true
                if gpgv "${codecov_bin}.SHA256SUM.sig" "${codecov_bin}.SHA256SUM" 2>/dev/null; then
                    echo "PGP signature verified"
                else
                    echo "Warning: PGP signature verification failed (continuing with SHA256 check)"
                fi
            fi
            (cd "${codecov_dir}" && sha256sum -c codecov.SHA256SUM)
            chmod +x "${codecov_bin}"

            local upload_dir git_root
            upload_dir=$(mktemp -d)
            cp "${coverage_profile}" "${upload_dir}/coverage-e2e.out"
            git_root=$(git rev-parse --show-toplevel)

            local -a codecov_args=(
                upload-coverage
                --file="${upload_dir}/coverage-e2e.out"
                --rootDir="${git_root}"
                -X search
                --flags=e2e
                --name="E2E Coverage"
                --verbose
            )

            local job_type="${JOB_TYPE:-local}"
            local target_sha
            target_sha=$(resolve_coverage_sha)
            if [[ "${job_type}" == "presubmit" ]]; then
                echo "Detected presubmit (PR #${PULL_NUMBER:-unknown}, sha ${target_sha})"
                [[ -n "${PULL_NUMBER:-}" ]]    && codecov_args+=(--pr "${PULL_NUMBER}")
                codecov_args+=(--sha "${target_sha}")
                [[ -n "${PULL_BASE_REF:-}" ]]   && codecov_args+=(--branch "${PULL_BASE_REF}")
                codecov_args+=(--slug "${CODECOV_SLUG}")
            elif [[ "${job_type}" == "postsubmit" ]]; then
                echo "Detected postsubmit (branch ${PULL_BASE_REF:-unknown}, sha ${target_sha})"
                codecov_args+=(--sha "${target_sha}")
                [[ -n "${PULL_BASE_REF:-}" ]]   && codecov_args+=(--branch "${PULL_BASE_REF}")
                codecov_args+=(--slug "${CODECOV_SLUG}")
            elif [[ "${job_type}" == "periodic" ]]; then
                echo "Detected periodic (sha ${target_sha})"
                codecov_args+=(--sha "${target_sha}" --branch "main" --slug "${CODECOV_SLUG}")
            else
                echo "Local run -- no Prow context, Codecov will auto-detect from git"
            fi

            "${codecov_bin}" "${codecov_args[@]}" || echo "Warning: Codecov upload failed (non-fatal)"
            rm -rf "${upload_dir}" "${codecov_dir}"
        else
            echo "CODECOV_TOKEN not set -- skipping Codecov upload."
            echo "Coverage profile saved as artifact: ${coverage_profile}"
        fi
    else
        echo "Warning: No coverage data found in ${coverage_dir}"
        echo "The operator may not have been built with coverage instrumentation,"
        echo "or the process did not exit cleanly (SIGKILL instead of SIGTERM)."
    fi

    echo "--- Coverage collection complete ---"
}

check_freshness() {
    echo "--- Coverage Freshness Check ---"

    local target_sha
    target_sha=$(resolve_coverage_sha)
    echo "Target commit: ${target_sha}"

    local response http_code body
    response=$(curl -sS -w "\n%{http_code}" \
        "https://api.codecov.io/api/v2/github/${CODECOV_SLUG}/totals/?sha=${target_sha}&flag=e2e") || {
        echo "Error: Codecov API request failed (network/DNS error). Aborting."
        exit 1
    }

    http_code=$(echo "${response}" | tail -1)
    body=$(echo "${response}" | sed '$d')

    if [[ "${http_code}" == "404" ]]; then
        echo "No e2e coverage for ${target_sha} on Codecov yet. Proceeding with coverage run."
        exit 0
    fi

    if [[ "${http_code}" != "200" ]]; then
        echo "Error: Codecov API returned HTTP ${http_code}. Aborting."
        exit 1
    fi

    local covered
    covered=$(echo "${body}" | jq -r '.coverage // empty' 2>/dev/null || true)
    if [[ -n "${covered}" && "${covered}" != "null" ]]; then
        echo "[SKIP] E2E coverage already published for ${target_sha} (${covered}%). Nothing to do."
        exit 1
    fi

    echo "No e2e coverage totals for ${target_sha}. Proceeding with e2e."
    exit 0
}

case "${1:-}" in
    setup)
        setup
        ;;
    collect)
        collect
        ;;
    check-freshness)
        check_freshness
        ;;
    *)
        echo "Usage: $0 {setup|collect|check-freshness}" >&2
        exit 1
        ;;
esac
