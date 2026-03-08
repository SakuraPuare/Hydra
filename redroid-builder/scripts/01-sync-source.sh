#!/bin/bash
# 01-sync-source.sh — Download AOSP source code with Redroid patches
# Uses Chinese mirror (TUNA/USTC) for AOSP, significantly faster in mainland China
set -euo pipefail

ANDROID_BRANCH="${ANDROID_BRANCH:-android-14.0.0_r1}"
REDROID_BRANCH="${REDROID_BRANCH:-14.0.0}"
SRC_DIR="${SRC_DIR:-$HOME/redroid-src}"

# ─── Mirror configuration ───────────────────────────────────────
# AOSP_MIRROR: sustech (南科大), tuna (清华), ustc (中科大), custom URL
AOSP_MIRROR="${AOSP_MIRROR:-sustech}"

case "$AOSP_MIRROR" in
    sustech)
        MANIFEST_URL="https://mirrors.sustech.edu.cn/AOSP/platform/manifest"
        export REPO_URL="https://mirrors.sustech.edu.cn/git/git-repo"
        MIRROR_NAME="南方科技大学 SUSTech"
        ;;
    tuna)
        MANIFEST_URL="https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/platform/manifest"
        export REPO_URL="https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
        MIRROR_NAME="清华 TUNA"
        ;;
    ustc)
        MANIFEST_URL="https://mirrors.ustc.edu.cn/aosp/platform/manifest"
        export REPO_URL="https://mirrors.ustc.edu.cn/repo-dl/repo"
        MIRROR_NAME="中科大 USTC"
        ;;
    google)
        MANIFEST_URL="https://android.googlesource.com/platform/manifest"
        MIRROR_NAME="Google (原始源)"
        ;;
    *)
        MANIFEST_URL="$AOSP_MIRROR"
        MIRROR_NAME="自定义镜像"
        ;;
esac

cd "$SRC_DIR"

echo "═══════════════════════════════════════"
echo "  Step 1: Sync AOSP + Redroid Source"
echo "  Branch: $ANDROID_BRANCH"
echo "  Mirror: $MIRROR_NAME"
echo "  URL:    $MANIFEST_URL"
echo "═══════════════════════════════════════"

# Initialize AOSP repo if not already done
if [ ! -d ".repo" ]; then
    echo "[1/3] Initializing AOSP repo..."
    repo init \
        -u "$MANIFEST_URL" \
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
# Limit parallel jobs to avoid overwhelming IO/network
SYNC_JOBS="${SYNC_JOBS:-8}"
echo "[3/3] Syncing source tree (-j${SYNC_JOBS}, this will take a long time)..."
repo sync -c \
    -j"$SYNC_JOBS" \
    --no-tags \
    --no-clone-bundle \
    --optimized-fetch \
    --force-sync \
    --verbose

echo ""
echo "✓ Source sync complete"
echo "  Mirror: $MIRROR_NAME"
echo "  Location: $SRC_DIR"
echo "  Size: $(du -sh "$SRC_DIR" --exclude=.repo | cut -f1)"
