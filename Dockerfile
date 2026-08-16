# Nintendo Switch UEFI firmware build container
# Base: Ubuntu 22.04 LTS (Jammy) — pinned digest for reproducibility.
# Build on Apple Silicon with:  docker buildx build --platform linux/amd64 -t switch-edk2 .
# Build on Intel/AMD with:      docker build -t switch-edk2 .

FROM ubuntu:22.04@sha256:149d67e29f765f4db62aa52161009e99e389544e25a8f43c8c89d4a445a7ca37

LABEL org.opencontainers.image.title="NintendoSwitchPkg EDK2 build environment"
LABEL org.opencontainers.image.description="Reproducible AArch64 UEFI firmware build for Nintendo Switch V1 (Tegra210)"
LABEL org.opencontainers.image.source="https://github.com/ptzalord/NintendoSwitchPkg"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── Toolchain versions (change here to update globally) ──────────────────────
# GCC AArch64 cross-compiler from Ubuntu 22.04 repos:  gcc-aarch64-linux-gnu 11.x
# ACPI compiler from Ubuntu 22.04 repos:               acpica-tools 20211217
# EDK2 tag pinned below in fetch-deps
# ─────────────────────────────────────────────────────────────────────────────

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    git \
    curl \
    ca-certificates \
    # AArch64 cross-compiler (GCC 11, matches EDK2 GCC5 toolchain)
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    # Python 3 required by EDK2 BaseTools
    python3 \
    python3-distutils \
    # ACPI source language compiler (required for AcpiTables)
    acpica-tools \
    make \
    bison \
    flex \
    libssl-dev \
    # PowerShell (for existing build scripts)
    && apt-get install -y --no-install-recommends wget \
    && wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends powershell \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory inside container
WORKDIR /build

# Copy only the repository itself; EDK2 and other deps are fetched by fetch-deps
COPY . /build/NintendoSwitchPkg

# Fetch all pinned dependencies and build
RUN make -C /build/NintendoSwitchPkg fetch-deps && \
    make -C /build/NintendoSwitchPkg build

# Artifacts land in /build/Build/
# The CI/local runner copies them out via:
#   docker cp <container>:/build/Build ./Build
