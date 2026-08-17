#!/usr/bin/env bash
# validate-edk2-pin.sh — keep the documented EDK2 pin aligned with fetch-deps.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FETCH_SCRIPT="${REPO_DIR}/scripts/fetch-deps.sh"
DOC_FILE="${REPO_DIR}/DEVELOPMENT.md"

extract_var() {
    local name="$1"
    sed -n "s/^${name}=\"\\([^\"]*\\)\"$/\\1/p" "${FETCH_SCRIPT}"
}

EDK2_COMMIT="$(extract_var EDK2_COMMIT)"
EDK2_TAG="$(extract_var EDK2_TAG)"

if [[ ! "${EDK2_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "ERROR: EDK2_COMMIT must be a 40-character lowercase hex SHA, got '${EDK2_COMMIT}'" >&2
    exit 1
fi

if [[ -z "${EDK2_TAG}" ]]; then
    echo "ERROR: EDK2_TAG must not be empty" >&2
    exit 1
fi

DOC_PIN_LINE="| EDK2 | commit \`${EDK2_COMMIT}\` (tag \`${EDK2_TAG}\`; commit SHA is the source of truth, tag kept for release context) | ✅ commit-pinned |"

if ! grep -Fqx "${DOC_PIN_LINE}" "${DOC_FILE}"; then
    echo "ERROR: ${DOC_FILE} does not contain the expected EDK2 pin line:" >&2
    echo "  ${DOC_PIN_LINE}" >&2
    exit 1
fi

echo "EDK2 pin validation passed: ${EDK2_TAG} => ${EDK2_COMMIT}"
