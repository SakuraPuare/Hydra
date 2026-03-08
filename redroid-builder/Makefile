# Hydra Custom Redroid Image Builder
# Android 14 (x86_64) with GApps, libndk_translation, Mihomo, WhatsApp, TikTok

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Configuration
ANDROID_VERSION    := 14.0.0
ANDROID_BRANCH     := android-14.0.0_r1
REDROID_BRANCH     := 14.0.0
IMAGE_NAME         := hydra/redroid
IMAGE_TAG          := $(ANDROID_VERSION)-custom
BUILDER_IMAGE      := hydra/redroid-builder:latest
SRC_DIR            := $(HOME)/redroid-src
BUILD_DIR          := $(SRC_DIR)
NPROC              := $(shell nproc)
MIHOMO_VERSION     := v1.19.0
NDK_TRANS_VERSION  := android-14
AOSP_MIRROR        := sustech

# Derived
BUILDER_UID        := $(shell id -u)
BUILDER_GID        := $(shell id -g)
BUILDER_USER       := $(shell id -un)
SCRIPT_DIR         := $(shell pwd)/scripts
OVERLAY_DIR        := $(shell pwd)/overlay
MANIFEST_DIR       := $(shell pwd)/manifests
CONFIG_DIR         := $(shell pwd)/configs
APK_DIR            := $(shell cd .. && pwd)/apks

export ANDROID_VERSION ANDROID_BRANCH REDROID_BRANCH IMAGE_NAME IMAGE_TAG
export SRC_DIR BUILD_DIR NPROC MIHOMO_VERSION NDK_TRANS_VERSION AOSP_MIRROR
export BUILDER_UID BUILDER_GID BUILDER_USER
export SCRIPT_DIR OVERLAY_DIR MANIFEST_DIR CONFIG_DIR APK_DIR

# ─── Targets ────────────────────────────────────────────────────

.PHONY: help setup sync gapps customize build package image all verify clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Build the AOSP builder Docker image
	docker build --network=host \
		--build-arg userid=$(BUILDER_UID) \
		--build-arg groupid=$(BUILDER_GID) \
		--build-arg username=$(BUILDER_USER) \
		-t $(BUILDER_IMAGE) \
		-f Dockerfile.builder .
	@echo "✓ Builder image ready: $(BUILDER_IMAGE)"

sync: ## Download AOSP source + Redroid patches (~100GB, takes hours)
	@mkdir -p $(SRC_DIR)
	SRC_DIR=$(SRC_DIR) bash $(SCRIPT_DIR)/01-sync-source.sh
	@echo "✓ Source sync complete"

gapps: ## Set up MindTheGapps integration
	SRC_DIR=$(SRC_DIR) bash $(SCRIPT_DIR)/02-setup-gapps.sh
	@echo "✓ GApps configured"

customize: ## Apply customizations (libndk, mihomo, apps, props)
	docker run --rm \
		-v $(SRC_DIR):/src \
		-v $(SCRIPT_DIR):/scripts:ro \
		-v $(OVERLAY_DIR):/overlay:ro \
		-v $(CONFIG_DIR):/configs:ro \
		-v $(APK_DIR):/apks:ro \
		$(BUILDER_IMAGE) \
		bash /scripts/03-apply-customizations.sh
	@echo "✓ Customizations applied"

build: ## Compile AOSP (takes 2-4 hours)
	docker run --rm \
		-v $(SRC_DIR):/src \
		-v $(SCRIPT_DIR):/scripts:ro \
		$(BUILDER_IMAGE) \
		bash /scripts/04-build-aosp.sh
	@echo "✓ AOSP build complete"

package: ## Package build output into Docker image
	sudo bash $(SCRIPT_DIR)/05-package-image.sh
	@echo "✓ Docker image ready: $(IMAGE_NAME):$(IMAGE_TAG)"

all: setup sync gapps customize build package ## Full build pipeline
	@echo ""
	@echo "════════════════════════════════════════════════"
	@echo "  Build complete: $(IMAGE_NAME):$(IMAGE_TAG)"
	@echo "════════════════════════════════════════════════"

verify: ## Run verification tests against built image
	bash $(SCRIPT_DIR)/06-verify.sh
	@echo "✓ All verification checks passed"

clean: ## Remove build artifacts (keeps source)
	docker run --rm \
		-v $(SRC_DIR):/src \
		$(BUILDER_IMAGE) \
		bash -c "cd /src && rm -rf out/"
	@echo "✓ Build artifacts cleaned"

clean-all: ## Remove everything including source
	@echo "WARNING: This will delete $(SRC_DIR) (~200GB)"
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	rm -rf $(SRC_DIR)
	@echo "✓ All data removed"

check-space: ## Check available disk space
	@echo "Required: ~250GB free space"
	@df -h $(HOME) | tail -1 | awk '{print "Available:", $$4}'
	@du -sh $(SRC_DIR) 2>/dev/null || echo "Source dir not yet created"

check-apks: ## Verify XAPK files are in place
	@echo "Checking apks/ directory: $(APK_DIR)"
	@ls -lh $(APK_DIR)/*.xapk 2>/dev/null && echo "✓ XAPK files found" || \
		echo "WARNING: No XAPK files found. Place WhatsApp*.xapk and TikTok*.xapk in $(APK_DIR)/"
