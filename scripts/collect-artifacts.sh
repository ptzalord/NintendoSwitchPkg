#!/usr/bin/env bash
# scripts/collect-artifacts.sh — collect TEGRA210_EFI firmware artifacts,
# wrap the .fd as a UEFI .elf, and generate + verify SHA256SUMS.
#
# The NintendoSwitch.fdf defines a single flash description named TEGRA210_EFI,
# so this script expects exactly:
#   TEGRA210_EFI.fd   — raw firmware volume
#   TEGRA210_EFI.elf  — ELF-wrapped firmware (generated here)
#
# This script is called from inside the Docker container (Dockerfile RUN step)
# or by CI after a successful build.  It FAILS fast on any error.
#
# Usage (from the repository root or from /build inside the container):
#   bash scripts/collect-artifacts.sh
#
# Environment variables (all optional):
#   BUILD_ROOT  — parent directory; defaults to parent of this repo.
#   OUT_DIR     — destination for artifacts; defaults to ${REPO_DIR}/out.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_ROOT="${BUILD_ROOT:-$(cd "${REPO_DIR}/.." && pwd)}"
OUT_DIR="${OUT_DIR:-${REPO_DIR}/out}"
LDSCRIPT="${REPO_DIR}/Tools/FvWrapper.ld"

EXPECTED_FD="TEGRA210_EFI.fd"
EXPECTED_ELF="TEGRA210_EFI.elf"

echo "[collect] BUILD_ROOT: ${BUILD_ROOT}"
echo "[collect] OUT_DIR:    ${OUT_DIR}"

if [ ! -f "${LDSCRIPT}" ]; then
    echo "[collect] ERROR: linker script not found at ${LDSCRIPT}"
    exit 1
fi

# ── Remove and recreate OUT_DIR so stale output cannot pass ──────────────────
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# ── Locate TEGRA210_EFI.fd ───────────────────────────────────────────────────
FD_PATH=""
while IFS= read -r -d '' candidate; do
    BASE="$(basename "${candidate}")"
    if [ "${BASE}" = "${EXPECTED_FD}" ]; then
        if [ -n "${FD_PATH}" ]; then
            echo "[collect] ERROR: duplicate ${EXPECTED_FD} found:"
            echo "  ${FD_PATH}"
            echo "  ${candidate}"
            exit 1
        fi
        FD_PATH="${candidate}"
    fi
done < <(find "${BUILD_ROOT}/Build" -name "${EXPECTED_FD}" -print0 2>/dev/null)

if [ -z "${FD_PATH}" ]; then
    echo "[collect] ERROR: ${EXPECTED_FD} not found under ${BUILD_ROOT}/Build"
    echo "[collect] The firmware build may have failed or BUILD_ROOT is incorrect."
    exit 1
fi

if [ ! -s "${FD_PATH}" ]; then
    echo "[collect] ERROR: ${FD_PATH} is empty"
    exit 1
fi

echo "[collect] Found: ${FD_PATH}"

# ── Copy .fd to OUT_DIR ───────────────────────────────────────────────────────
cp "${FD_PATH}" "${OUT_DIR}/${EXPECTED_FD}"

# ── Wrap as ELF ───────────────────────────────────────────────────────────────
OBJ_TMP=""
cleanup_tmp() { [ -n "${OBJ_TMP}" ] && rm -f "${OBJ_TMP}"; }
trap cleanup_tmp EXIT

OBJ_TMP="$(mktemp /tmp/FD_XXXXXX.o)"

aarch64-linux-gnu-objcopy \
    -I binary \
    -O elf64-littleaarch64 \
    --binary-architecture aarch64 \
    "${OUT_DIR}/${EXPECTED_FD}" "${OBJ_TMP}"

aarch64-linux-gnu-ld \
    -m aarch64linux \
    "${OBJ_TMP}" \
    -T "${LDSCRIPT}" \
    -o "${OUT_DIR}/${EXPECTED_ELF}"

rm -f "${OBJ_TMP}"
OBJ_TMP=""
trap - EXIT

echo "[collect] Generated ELF: ${OUT_DIR}/${EXPECTED_ELF}"

# ── Require nonempty outputs ──────────────────────────────────────────────────
if [ ! -s "${OUT_DIR}/${EXPECTED_FD}" ]; then
    echo "[collect] ERROR: ${EXPECTED_FD} is empty after copy"
    exit 1
fi
if [ ! -s "${OUT_DIR}/${EXPECTED_ELF}" ]; then
    echo "[collect] ERROR: ${EXPECTED_ELF} is empty after ELF wrap"
    exit 1
fi

# ── Generate and immediately verify SHA256SUMS ────────────────────────────────
(cd "${OUT_DIR}" && sha256sum -- "${EXPECTED_FD}" "${EXPECTED_ELF}" > SHA256SUMS)

if [ ! -s "${OUT_DIR}/SHA256SUMS" ]; then
    echo "[collect] ERROR: SHA256SUMS is empty"
    exit 1
fi

(cd "${OUT_DIR}" && sha256sum --check SHA256SUMS)

echo "[collect] SHA256SUMS:"
cat "${OUT_DIR}/SHA256SUMS"

echo "[collect] Artifact listing:"
ls -lh "${OUT_DIR}/"

echo "[collect] Done.  Collected ${EXPECTED_FD} and ${EXPECTED_ELF}."
