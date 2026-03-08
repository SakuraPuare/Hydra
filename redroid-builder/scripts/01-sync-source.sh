#!/bin/bash
# 01-sync-source.sh — Download AOSP source code with Redroid patches
set -euo pipefail

ANDROID_BRANCH="${ANDROID_BRANCH:-android-14.0.0_r1}"
REDROID_BRANCH="${REDROID_BRANCH:-14.0.0}"
SRC_DIR="/src"

cd "$SRC_DIR"

echo "═══════════════════════════════════════"
echo "  Step 1: Sync AOSP + Redroid Source"
echo "  Branch: $ANDROID_BRANCH"
echo "═══════════════════════════════════════"

# Initialize AOSP repo if not already done
if [ ! -d ".repo" ]; then
    echo "[1/3] Initializing AOSP repo..."
    repo init \
        -u https://android.googlesource.com/platform/manifest \
        --git-lfs \
        --depth=1 \
        -b "$ANDROID_BRANCH"
else
    echo "[1/3] Repo already initialized, skipping init"
fi

# Clone Redroid local manifests
if [ ! -d ".repo/local_manifests" ]; then
    echo "[2/3] Cloning Redroid local manifests..."
    git clone \
        https://github.com/remote-android/local_manifests.git \
        .repo/local_manifests \
        -b "$REDROID_BRANCH" \
        --depth=1
else
    echo "[2/3] Local manifests already present, updating..."
    cd .repo/local_manifests
    git pull origin "$REDROID_BRANCH" || true
    cd "$SRC_DIR"
fi

# Sync source
echo "[3/3] Syncing source tree (this will take a long time)..."
repo sync -c \
    -j"$(nproc)" \
    --no-tags \
    --no-clone-bundle \
    --optimized-fetch \
    --force-sync

echo ""
echo "✓ Source sync complete"
echo "  Location: $SRC_DIR"
echo "  Size: $(du -sh "$SRC_DIR" --exclude=.repo | cut -f1)"
