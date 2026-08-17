#!/usr/bin/env bash
# scripts/fetch-deps.sh — fetch and pin EDK2 and required submodules.
#
# Pinning strategy:
#   EDK2 is cloned from an immutable commit SHA corresponding to the
#   edk2-stable202108 release tag.  APT packages installed at image-build
#   time are Ubuntu 22.04 repo versions and are NOT independently pinned;
#   that limitation is documented in DEVELOPMENT.md.
#
# Usage (from the repository root or from /build inside the container):
#   bash scripts/fetch-deps.sh
#
# Environment variables (all optional):
#   BUILD_ROOT   — parent directory that will contain the edk2 clone.
#                  Defaults to the parent of the directory containing this
#                  script's repository checkout.
#   EDK2_DIR     — full path to place the edk2 clone.
#                  Defaults to ${BUILD_ROOT}/edk2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_ROOT="${BUILD_ROOT:-$(cd "${REPO_DIR}/.." && pwd)}"
EDK2_DIR="${EDK2_DIR:-${BUILD_ROOT}/edk2}"

# Immutable commit SHA for the edk2-stable202108 release.
# EDK2_COMMIT is the source of truth; EDK2_TAG is retained only as
# human-readable release context for the initial clone command.
# Verify with: git -C <edk2-clone> rev-parse edk2-stable202108
EDK2_COMMIT="7b4a99be8a39c12d3a7fc4b8db9f0eab4ac688d5"
EDK2_TAG="edk2-stable202108"

echo "[fetch-deps] EDK2 target: ${EDK2_TAG} (${EDK2_COMMIT})"
echo "[fetch-deps] EDK2 destination: ${EDK2_DIR}"

if [ -d "${EDK2_DIR}/.git" ]; then
    echo "[fetch-deps] EDK2 directory already exists; verifying commit..."
    CURRENT=$(git -C "${EDK2_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")
    if [ "${CURRENT}" = "${EDK2_COMMIT}" ]; then
        echo "[fetch-deps] Already at correct commit ${EDK2_COMMIT}; skipping clone."
    else
        echo "[fetch-deps] WARNING: ${EDK2_DIR} is at ${CURRENT}, expected ${EDK2_COMMIT}."
        echo "[fetch-deps] Remove ${EDK2_DIR} and re-run to reclone."
        exit 1
    fi
else
    echo "[fetch-deps] Cloning EDK2..."
    git clone \
        --branch "${EDK2_TAG}" \
        --depth 1 \
        "https://github.com/tianocore/edk2.git" \
        "${EDK2_DIR}"
    # Verify the clone landed on the expected commit.
    ACTUAL=$(git -C "${EDK2_DIR}" rev-parse HEAD)
    if [ "${ACTUAL}" != "${EDK2_COMMIT}" ]; then
        echo "[fetch-deps] ERROR: cloned HEAD is ${ACTUAL}, expected ${EDK2_COMMIT}."
        echo "[fetch-deps] The upstream tag may have been moved.  Update EDK2_COMMIT in this script."
        exit 1
    fi
fi

echo "[fetch-deps] Initialising required submodules..."
git -C "${EDK2_DIR}" submodule update --init --recursive -- \
    MdePkg \
    MdeModulePkg \
    ArmPkg \
    ArmPlatformPkg \
    EmbeddedPkg \
    NetworkPkg \
    FatPkg \
    BaseTools

echo "[fetch-deps] Done."
