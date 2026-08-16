# NintendoSwitchPkg — macOS developer Makefile
#
# Quick-start (Docker Desktop or Colima):
#   make docker-build
#
# Prerequisites: Docker Desktop ≥ 4.x or Colima ≥ 0.5 with a running engine.
# At least 10 GB of free disk space is recommended.
#
# See DEVELOPMENT.md §2 for setup details and platform-specific notes.

IMAGE_NAME  ?= switch-edk2
PLATFORM    ?= linux/arm64
OUT_DIR     ?= $(CURDIR)/out

.PHONY: help docker-build check-env clean

help:
	@echo ""
	@echo "NintendoSwitchPkg build targets"
	@echo "================================"
	@echo "  make docker-build   Build firmware in Docker (recommended for macOS)"
	@echo "  make check-env      Validate Docker is available and has sufficient disk"
	@echo "  make clean          Remove local build artefacts"
	@echo ""
	@echo "Platform override (default: linux/arm64):"
	@echo "  make docker-build PLATFORM=linux/amd64"
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
	@rm -rf $(OUT_DIR) && mkdir -p $(OUT_DIR)
	@ID=$$(docker create --platform $(PLATFORM) $(IMAGE_NAME)); \
	docker cp "$$ID:/build/out/." $(OUT_DIR)/; \
	docker rm "$$ID"
	@echo ""
	@echo "[docker-build] Artifacts written to $(OUT_DIR)/"
	@ls -lh $(OUT_DIR)/
	@echo ""
	@echo "[docker-build] SHA-256 checksums:"
	@cat $(OUT_DIR)/SHA256SUMS

clean:
	@echo "[clean] Removing $(OUT_DIR)..."
	@rm -rf $(OUT_DIR)
	@echo "[clean] Done."
