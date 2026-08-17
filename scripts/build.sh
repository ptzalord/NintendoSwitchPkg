#!/usr/bin/env bash
# scripts/build.sh — build NintendoSwitchPkg firmware inside a prepared
# environment (Docker container or CI runner that has run fetch-deps.sh).
#
# Usage (from the repository root or from /build inside the container):
#   bash scripts/build.sh
#
# Expected layout on entry:
#   ${BUILD_ROOT}/edk2/          — EDK2 source (populated by fetch-deps.sh)
#   ${BUILD_ROOT}/NintendoSwitchPkg/ — this repository checkout
#
# Build outputs land in:
#   ${BUILD_ROOT}/Build/NintendoSwitch-AARCH64/
#
# Environment variables (all optional):
#   BUILD_ROOT          — parent directory; defaults to parent of this repo.
#   GCC5_AARCH64_PREFIX — cross-compiler prefix; defaults to aarch64-linux-gnu-

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_ROOT="${BUILD_ROOT:-$(cd "${REPO_DIR}/.." && pwd)}"
EDK2_DIR="${EDK2_DIR:-${BUILD_ROOT}/edk2}"
export GCC5_AARCH64_PREFIX="${GCC5_AARCH64_PREFIX:-aarch64-linux-gnu-}"

echo "[build] BUILD_ROOT:          ${BUILD_ROOT}"
echo "[build] EDK2_DIR:            ${EDK2_DIR}"
echo "[build] GCC5_AARCH64_PREFIX: ${GCC5_AARCH64_PREFIX}"

# ── Sanity checks ─────────────────────────────────────────────────────────────
if [ ! -f "${EDK2_DIR}/BaseTools/BuildEnv" ]; then
    echo "[build] ERROR: ${EDK2_DIR}/BaseTools/BuildEnv not found."
    echo "[build] Run scripts/fetch-deps.sh first."
    exit 1
fi

# ── Write FwReleaseInfo.h ─────────────────────────────────────────────────────
COMMIT=$(git -C "${REPO_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
DATE=$(date +%m/%d/%Y)
FW_HEADER="${REPO_DIR}/Include/FwReleaseInfo.h"
echo "[build] Writing ${FW_HEADER}  (commit=${COMMIT}, date=${DATE})"
printf '#ifndef __SMBIOS_RELEASE_INFO_H__\n#define __SMBIOS_RELEASE_INFO_H__\n#define __IMPL_COMMIT_ID__ "%s"\n#define __RELEASE_DATE__ "%s"\n#endif\n' \
    "${COMMIT}" "${DATE}" > "${FW_HEADER}"

# ── Build BaseTools if not already built ──────────────────────────────────────
if [ ! -f "${EDK2_DIR}/BaseTools/Source/C/bin/GenFv" ]; then
    echo "[build] Building EDK2 BaseTools..."
    make -C "${EDK2_DIR}/BaseTools"
fi

# ── Set up EDK2 environment ───────────────────────────────────────────────────
export WORKSPACE="${BUILD_ROOT}"
export PACKAGES_PATH="${EDK2_DIR}:${REPO_DIR}"

echo "[build] Sourcing EDK2 BuildEnv..."
# shellcheck source=/dev/null
source "${EDK2_DIR}/BaseTools/BuildEnv"

# ── Build firmware ─────────────────────────────────────────────────────────────
echo "[build] Starting firmware build (AARCH64, GCC5)..."
build -a AARCH64 \
      -p NintendoSwitchPkg/NintendoSwitch.dsc \
      -t GCC5

echo "[build] Firmware build complete."
echo "[build] Build output: ${BUILD_ROOT}/Build/"
