# NintendoSwitchPkg — macOS developer Makefile
#
# Quick-start (Docker Desktop or Colima):
#   make docker-build
#
# Prerequisites: Docker Desktop ≥ 4.x or Colima ≥ 0.5 with a running engine.
# At least 10 GB of free disk space is recommended.
#
# The target Docker platform is auto-detected from the host architecture:
#   Apple Silicon (arm64/aarch64) → linux/arm64
#   Intel/AMD     (x86_64/amd64)  → linux/amd64
# Override with: make docker-build PLATFORM=linux/amd64
#
# See DEVELOPMENT.md §2 for setup details and platform-specific notes.

IMAGE_NAME  ?= switch-edk2
OUT_DIR     ?= $(CURDIR)/out

# Auto-detect host architecture unless PLATFORM is already set by the caller.
ifndef PLATFORM
  _HOST_ARCH := $(shell uname -m)
  ifeq ($(_HOST_ARCH),arm64)
    PLATFORM := linux/arm64
  else ifeq ($(_HOST_ARCH),aarch64)
    PLATFORM := linux/arm64
  else ifeq ($(_HOST_ARCH),x86_64)
    PLATFORM := linux/amd64
  else ifeq ($(_HOST_ARCH),amd64)
    PLATFORM := linux/amd64
  else
    $(error Unknown host architecture '$(_HOST_ARCH)'. \
      Set PLATFORM explicitly: make docker-build PLATFORM=linux/amd64)
  endif
endif

.PHONY: help docker-build check-env clean

help:
	@echo ""
	@echo "NintendoSwitchPkg build targets"
	@echo "================================"
	@echo "  make docker-build   Build firmware in Docker (recommended for macOS)"
	@echo "  make check-env      Validate Docker is available and has sufficient disk"
	@echo "  make clean          Remove local build artefacts"
	@echo ""
	@echo "Platform auto-detection (override with PLATFORM=...):"
	@echo "  Apple Silicon (arm64/aarch64) → linux/arm64"
	@echo "  Intel/AMD     (x86_64/amd64)  → linux/amd64"
	@echo "  Example: make docker-build PLATFORM=linux/amd64"
	@echo ""

check-env:
	@echo "[check-env] Checking Docker daemon..."
	@docker info > /dev/null 2>&1 || { \
	    echo "ERROR: Docker daemon is not running."; \
	    echo "  macOS: start Docker Desktop or run: colima start"; \
	    exit 1; \
	}
	@echo "[check-env] Docker is available."
	@FREE_KB=$$(df -k . | tail -1 | awk '{print $$4}'); \
	REQUIRED_KB=10485760; \
	if [ "$$FREE_KB" -lt "$$REQUIRED_KB" ]; then \
	    echo "ERROR: Less than 10 GB free disk space (have $$(( $$FREE_KB / 1024 / 1024 )) GB)."; \
	    exit 1; \
	fi
	@echo "[check-env] Sufficient disk space available."

docker-build: check-env
	@echo "[docker-build] Building image for platform $(PLATFORM)..."
	docker buildx build \
	    --platform $(PLATFORM) \
	    --tag $(IMAGE_NAME) \
	    --load \
	    .
	@echo "[docker-build] Extracting artifacts from container..."
	@rm -rf "$(OUT_DIR)" && mkdir -p "$(OUT_DIR)"
	@set -eu; \
	ID=$$(docker create --platform $(PLATFORM) $(IMAGE_NAME)); \
	trap 'docker rm -f "$$ID" >/dev/null 2>&1 || true' EXIT; \
	docker cp "$$ID:/build/out/." "$(OUT_DIR)/"; \
	test -s "$(OUT_DIR)/TEGRA210_EFI.fd"   || { echo "ERROR: TEGRA210_EFI.fd missing or empty"; exit 1; }; \
	test -s "$(OUT_DIR)/TEGRA210_EFI.elf"  || { echo "ERROR: TEGRA210_EFI.elf missing or empty"; exit 1; }; \
	test -s "$(OUT_DIR)/SHA256SUMS"        || { echo "ERROR: SHA256SUMS missing or empty"; exit 1; }; \
	(cd "$(OUT_DIR)" && sha256sum --check SHA256SUMS)
	@echo ""
	@echo "[docker-build] Artifacts written to $(OUT_DIR)/"
	@ls -lh "$(OUT_DIR)/"
	@echo ""
	@echo "[docker-build] SHA-256 checksums:"
	@cat "$(OUT_DIR)/SHA256SUMS"

clean:
	@echo "[clean] Removing $(OUT_DIR)..."
	@rm -rf $(OUT_DIR)
	@echo "[clean] Done."
