#!/usr/bin/env bash
# scripts/collect-artifacts.sh — wrap .fd files as UEFI.elf, collect all
# firmware artifacts to out/, and generate SHA256SUMS.
#
# This script is called by both the Makefile (local Docker path) and the CI
# workflow after a successful build.  It FAILS if no .fd files are found.
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

echo "[collect] BUILD_ROOT: ${BUILD_ROOT}"
echo "[collect] OUT_DIR:    ${OUT_DIR}"

if [ ! -f "${LDSCRIPT}" ]; then
    echo "[collect] ERROR: linker script not found at ${LDSCRIPT}"
    exit 1
fi

# ── Collect .fd files ─────────────────────────────────────────────────────────
FD_LIST=()
while IFS= read -r -d '' fd; do
    FD_LIST+=("${fd}")
done < <(find "${BUILD_ROOT}/Build" -name '*.fd' -print0 2>/dev/null)

if [ "${#FD_LIST[@]}" -eq 0 ]; then
    echo "[collect] ERROR: no .fd files found under ${BUILD_ROOT}/Build"
    echo "[collect] The firmware build may have failed or BUILD_ROOT is incorrect."
    exit 1
fi

mkdir -p "${OUT_DIR}"

# Use a single cleanup trap for any temporary object file.
OBJ_TMP=""
cleanup_tmp() { [ -n "${OBJ_TMP}" ] && rm -f "${OBJ_TMP}"; }
trap cleanup_tmp EXIT

for fd in "${FD_LIST[@]}"; do
    echo "[collect] Processing: ${fd}"

    # Copy the raw .fd
    cp "${fd}" "${OUT_DIR}/"
    FD_BASENAME="$(basename "${fd}")"

    # Generate ELF wrapper
    ELF_NAME="${FD_BASENAME%.fd}.elf"
    OBJ_TMP="$(mktemp /tmp/FD_XXXXXX.o)"

    aarch64-linux-gnu-objcopy \
        -I binary \
        -O elf64-littleaarch64 \
        --binary-architecture aarch64 \
        "${fd}" "${OBJ_TMP}"

    aarch64-linux-gnu-ld \
        -m aarch64linux \
        "${OBJ_TMP}" \
        -T "${LDSCRIPT}" \
        -o "${OUT_DIR}/${ELF_NAME}"

    rm -f "${OBJ_TMP}"
    OBJ_TMP=""

    echo "[collect] Generated ELF: ${OUT_DIR}/${ELF_NAME}"
done

trap - EXIT

# ── Verify expected outputs exist ─────────────────────────────────────────────
FD_OUT_COUNT=$(find "${OUT_DIR}" -maxdepth 1 -name '*.fd' | wc -l)
ELF_OUT_COUNT=$(find "${OUT_DIR}" -maxdepth 1 -name '*.elf' | wc -l)

if [ "${FD_OUT_COUNT}" -eq 0 ]; then
    echo "[collect] ERROR: no .fd files in ${OUT_DIR} after collection"
    exit 1
fi
if [ "${ELF_OUT_COUNT}" -eq 0 ]; then
    echo "[collect] ERROR: no .elf files in ${OUT_DIR} after ELF wrapping"
    exit 1
fi

# ── Generate SHA256SUMS ───────────────────────────────────────────────────────
# Build an explicit file list from what was actually collected.
ARTIFACT_FILES=()
while IFS= read -r -d '' f; do
    ARTIFACT_FILES+=("$(basename "${f}")")
done < <(find "${OUT_DIR}" -maxdepth 1 \( -name '*.fd' -o -name '*.elf' \) -print0 | sort -z)

(cd "${OUT_DIR}" && sha256sum -- "${ARTIFACT_FILES[@]}" > SHA256SUMS)
echo "[collect] SHA256SUMS:"
cat "${OUT_DIR}/SHA256SUMS"

echo "[collect] Artifact listing:"
ls -lh "${OUT_DIR}/"

echo "[collect] Done.  ${FD_OUT_COUNT} .fd and ${ELF_OUT_COUNT} .elf artifact(s) collected."
