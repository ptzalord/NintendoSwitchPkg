################################################################################
# NintendoSwitchPkg — top-level Makefile
#
# Usage (macOS with Docker Desktop or Colima):
#   make docker-build      — build full firmware image inside Docker
#   make docker-shell      — drop into an interactive build container
#   make fetch-deps        — clone/update pinned EDK2 dependencies (run inside
#                            the container or a pre-configured Linux host)
#   make build             — build inside the current environment (Linux only)
#   make clean             — remove build artifacts
#   make check-env         — validate prerequisites before building
#
# Artifacts are written to  Build/NintendoSwitch-AARCH64/DEBUG_GCC5/FV/
# and a copy is placed in   out/
################################################################################

SHELL := /bin/bash
.DEFAULT_GOAL := docker-build

# ── Pinned dependency revisions ───────────────────────────────────────────────
# EDK2 tag from October 2021 — last known-compatible with historical ArmPkg
# sources used by this package.  Update both EDK2_TAG and the Dockerfile if you
# need a newer EDK2 baseline.
EDK2_TAG         := edk2-stable202108
EDK2_REPO        := https://github.com/tianocore/edk2.git
EDK2_DIR         := ../edk2

# ── Docker settings ───────────────────────────────────────────────────────────
IMAGE_NAME       := switch-edk2
CONTAINER_NAME   := switch-edk2-builder
PLATFORM         ?= linux/amd64

# Detect Apple Silicon and suggest the right platform flag
UNAME_M := $(shell uname -m 2>/dev/null || echo unknown)
ifeq ($(UNAME_M),arm64)
  PLATFORM := linux/amd64
  $(info [INFO] Apple Silicon detected — using --platform linux/amd64 (QEMU emulation).)
  $(info [INFO] Install Rosetta 2 and enable 'Use Rosetta for x86/amd64 emulation' in)
  $(info [INFO] Docker Desktop settings for best performance.)
endif

# Output directory for final artifacts
OUT_DIR := out

.PHONY: all docker-build docker-shell fetch-deps build clean check-env \
        artifacts help

##
## help — show available targets
##
help:
	@echo ""
	@echo "NintendoSwitchPkg build targets:"
	@echo "  make docker-build   Build firmware in Docker (default, macOS-safe)"
	@echo "  make docker-shell   Interactive shell inside the build container"
	@echo "  make fetch-deps     Fetch/update pinned EDK2 dependencies (Linux)"
	@echo "  make build          Build inside current Linux environment"
	@echo "  make clean          Remove build output"
	@echo "  make check-env      Validate host prerequisites"
	@echo "  make help           Show this help"
	@echo ""
	@echo "Artifacts: $(OUT_DIR)/"
	@echo ""

##
## check-env — validate host prerequisites
##
check-env:
	@echo "[check-env] Validating prerequisites..."
	@command -v docker >/dev/null 2>&1 || \
	  { echo "[ERROR] docker not found."; \
	    echo "  Install Docker Desktop: https://www.docker.com/products/docker-desktop/"; \
	    echo "  Or Colima: brew install colima docker && colima start --cpu 4 --memory 8 --disk 60"; \
	    exit 1; }
	@docker info >/dev/null 2>&1 || \
	  { echo "[ERROR] Docker daemon is not running."; \
	    echo "  Start Docker Desktop, or run:  colima start"; \
	    exit 1; }
	@available=$$(df -Pk . | tail -1 | awk '{print $$4}'); \
	  required=10485760; \
	  if [ "$$available" -lt "$$required" ]; then \
	    echo "[ERROR] Insufficient disk space. Need at least 10 GB free."; \
	    exit 1; \
	  fi
	@docker buildx version >/dev/null 2>&1 || \
	  { echo "[WARN] docker buildx not available — multi-platform builds may fail on Apple Silicon."; }
	@echo "[check-env] All prerequisites satisfied."

##
## docker-build — build firmware image inside Docker
##
docker-build: check-env
	@echo "[docker-build] Building Docker image ($(PLATFORM))..."
	docker buildx build \
	  --platform $(PLATFORM) \
	  --load \
	  -t $(IMAGE_NAME) \
	  -f Dockerfile \
	  .
	@echo "[docker-build] Extracting artifacts..."
	@mkdir -p $(OUT_DIR)
	docker run --rm --platform $(PLATFORM) \
	  -v "$(CURDIR)/$(OUT_DIR)":/artifacts \
	  $(IMAGE_NAME) \
	  bash -c "find /build/Build -name '*.fd' -o -name '*.elf' | xargs -I{} cp {} /artifacts/ 2>/dev/null; \
	           ls /artifacts/ || echo '[WARN] No artifacts found — check build log above'"
	@$(MAKE) artifacts

##
## docker-shell — interactive shell inside build container for debugging
##
docker-shell: check-env
	@echo "[docker-shell] Starting interactive container ($(PLATFORM))..."
	@echo "[docker-shell] Repository is mounted at /repo"
	docker run --rm -it --platform $(PLATFORM) \
	  -v "$(CURDIR)":/repo \
	  -w /repo \
	  --entrypoint /bin/bash \
	  $(IMAGE_NAME) || \
	{ echo "[INFO] Image not yet built — run 'make docker-build' first."; exit 1; }

##
## fetch-deps — clone/update EDK2 and its submodules at pinned revisions
## Intended to run inside the container (or a pre-configured Linux host).
##
fetch-deps:
	@echo "[fetch-deps] Checking EDK2 dependency at $(EDK2_DIR) ..."
	@if [ ! -d "$(EDK2_DIR)/.git" ]; then \
	  echo "[fetch-deps] Cloning EDK2 at tag $(EDK2_TAG) ..."; \
	  git clone --branch $(EDK2_TAG) --depth 1 $(EDK2_REPO) $(EDK2_DIR); \
	else \
	  echo "[fetch-deps] EDK2 already present, verifying tag..."; \
	  cd $(EDK2_DIR) && git fetch --tags origin && git checkout $(EDK2_TAG); \
	fi
	@echo "[fetch-deps] Initialising EDK2 submodules (MdePkg, ArmPkg, etc.)..."
	@cd $(EDK2_DIR) && git submodule update --init --recursive -- \
	  MdePkg \
	  MdeModulePkg \
	  ArmPkg \
	  ArmPlatformPkg \
	  EmbeddedPkg \
	  NetworkPkg \
	  FatPkg \
	  BaseTools
	@echo "[fetch-deps] Done."

##
## build — build inside current Linux environment (requires fetch-deps first)
##
build: _check-linux-env
	@echo "[build] Setting up EDK2 environment and building..."
	@cd .. && \
	  export PACKAGES_PATH="$$(pwd)/edk2:$$(pwd)/NintendoSwitchPkg" && \
	  export WORKSPACE=$$(pwd) && \
	  export GCC5_AARCH64_PREFIX=aarch64-linux-gnu- && \
	  . edk2/BaseTools/BuildEnv && \
	  cd edk2 && make -C BaseTools && \
	  cd .. && \
	  COMMIT=$$(cd NintendoSwitchPkg && git rev-parse --short HEAD 2>/dev/null || echo unknown) && \
	  DATE=$$(date +%m/%d/%Y) && \
	  printf '#ifndef __SMBIOS_RELEASE_INFO_H__\n#define __SMBIOS_RELEASE_INFO_H__\n#define __IMPL_COMMIT_ID__ "%s"\n#define __RELEASE_DATE__ "%s"\n#endif\n' \
	    "$$COMMIT" "$$DATE" > NintendoSwitchPkg/Include/FwReleaseInfo.h && \
	  build -a AARCH64 -p NintendoSwitchPkg/NintendoSwitch.dsc -t GCC5
	@echo "[build] Build complete."
	@$(MAKE) -C NintendoSwitchPkg artifacts 2>/dev/null || true

##
## artifacts — list and checksum build output
##
artifacts:
	@echo ""
	@echo "=== Build Artifacts ==="
	@if compgen -G "$(OUT_DIR)/*.fd" > /dev/null 2>&1 || compgen -G "$(OUT_DIR)/*.elf" > /dev/null 2>&1; then \
	  echo "Directory: $(OUT_DIR)/"; \
	  ls -lh $(OUT_DIR)/; \
	  echo ""; \
	  echo "SHA-256 checksums:"; \
	  (cd $(OUT_DIR) && sha256sum * 2>/dev/null) || (cd $(OUT_DIR) && shasum -a 256 * 2>/dev/null); \
	else \
	  echo "[WARN] No .fd or .elf artifacts found in $(OUT_DIR)/."; \
	  echo "       If the build just completed, check Build/NintendoSwitch-AARCH64/DEBUG_GCC5/FV/"; \
	fi
	@echo ""

##
## clean — remove build output
##
clean:
	@echo "[clean] Removing build artifacts..."
	rm -rf $(OUT_DIR)
	@if [ -d "../Build" ]; then rm -rf ../Build; fi
	@echo "[clean] Done."

# ── Internal guard ────────────────────────────────────────────────────────────
.PHONY: _check-linux-env
_check-linux-env:
	@uname -s | grep -q Linux || \
	  { echo "[ERROR] 'make build' must run on Linux (use 'make docker-build' on macOS)."; exit 1; }
	@command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 || \
	  { echo "[ERROR] aarch64-linux-gnu-gcc not found. Install: apt-get install gcc-aarch64-linux-gnu"; exit 1; }
	@command -v iasl >/dev/null 2>&1 || \
	  { echo "[ERROR] iasl (ACPI compiler) not found. Install: apt-get install acpica-tools"; exit 1; }
	@[ -d "../edk2" ] || \
	  { echo "[ERROR] EDK2 not found at ../edk2. Run 'make fetch-deps' first."; exit 1; }
