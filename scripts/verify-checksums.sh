#!/usr/bin/env bash
# verify-checksums.sh — portable SHA-256 verification helper
#
# Usage: verify-checksums.sh <directory>
#
# Verifies SHA256SUMS inside <directory> using the first available tool:
#   1. sha256sum  (Linux / GNU coreutils)
#   2. shasum     (macOS built-in, invoked with -a 256)
#
# Exits nonzero on any failure.

set -euo pipefail

DIR="${1:?Usage: $0 <directory>}"

if [ ! -f "${DIR}/SHA256SUMS" ]; then
    echo "ERROR: ${DIR}/SHA256SUMS not found" >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    (cd "${DIR}" && sha256sum --check SHA256SUMS)
elif command -v shasum >/dev/null 2>&1; then
    (cd "${DIR}" && shasum -a 256 --check SHA256SUMS)
else
    echo "ERROR: neither sha256sum nor shasum is available on PATH" >&2
    exit 1
fi
