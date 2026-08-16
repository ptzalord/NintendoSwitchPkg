# Nintendo Switch UEFI firmware build container
#
# Base: Ubuntu 22.04 LTS (Jammy Jellyfish)
# Digest is pinned for reproducibility.
#
# APT package versions are whatever Ubuntu 22.04 provides at image-build time;
# they are NOT independently version-pinned.  See DEVELOPMENT.md §3 for the
# documented limitation.
#
# Platform support:
#   Apple Silicon (linux/arm64):  docker buildx build --platform linux/arm64 -t switch-edk2 .
#   Intel/AMD     (linux/amd64):  docker build -t switch-edk2 .
#
# A pinned linux/amd64 digest is also provided as a comment if amd64-only
# emulation is ever required; see DEVELOPMENT.md §2 for guidance.
#
# The same scripts invoked here are also invoked by CI so both paths remain in sync.

FROM ubuntu:22.04@sha256:149d67e29f765f4db62aa52161009e99e389544e25a8f43c8c89d4a445a7ca37

LABEL org.opencontainers.image.title="NintendoSwitchPkg EDK2 build environment"
LABEL org.opencontainers.image.description="Reproducible AArch64 UEFI firmware build for Nintendo Switch V1 (Tegra210)"
LABEL org.opencontainers.image.source="https://github.com/ptzalord/NintendoSwitchPkg"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      curl \
      ca-certificates \
      gcc-aarch64-linux-gnu \
      binutils-aarch64-linux-gnu \
      python3 \
      python3-distutils \
      acpica-tools \
      uuid-dev \
      nasm \
      make \
      bison \
      flex \
      libssl-dev \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy only the repository; EDK2 is fetched by scripts/fetch-deps.sh
COPY . /build/NintendoSwitchPkg

# Fetch pinned dependencies, build firmware, collect artifacts to /build/out/
RUN BUILD_ROOT=/build \
    bash /build/NintendoSwitchPkg/scripts/fetch-deps.sh \
 && BUILD_ROOT=/build \
    bash /build/NintendoSwitchPkg/scripts/build.sh \
 && BUILD_ROOT=/build OUT_DIR=/build/out \
    bash /build/NintendoSwitchPkg/scripts/collect-artifacts.sh

# Artifacts land in /build/out/
# Extract with:  docker cp <container>:/build/out ./out
