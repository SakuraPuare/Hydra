#!/bin/bash
# 05-package-image.sh — Package AOSP build output into Docker image
# NOTE: This script runs on the HOST (not in builder container) and needs sudo
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/redroid-src}"
IMAGE_NAME="${IMAGE_NAME:-hydra/redroid}"
IMAGE_TAG="${IMAGE_TAG:-14.0.0-custom}"
OUT_DIR="$SRC_DIR/out/target/product/redroid_x86_64"

echo "═══════════════════════════════════════"
echo "  Step 5: Package Docker Image"
echo "  Output: $IMAGE_NAME:$IMAGE_TAG"
echo "═══════════════════════════════════════"

# Verify build output exists
if [ ! -d "$OUT_DIR" ]; then
    echo "ERROR: Build output not found at $OUT_DIR"
    echo "  Run 'make build' first"
    exit 1
fi

# Create temporary working directory
WORK_DIR=$(mktemp -d)
MOUNT_DIR="$WORK_DIR/mount"
ROOTFS_DIR="$WORK_DIR/rootfs"
mkdir -p "$MOUNT_DIR" "$ROOTFS_DIR"

cleanup() {
    echo "Cleaning up..."
    umount "$MOUNT_DIR/vendor" 2>/dev/null || true
    umount "$MOUNT_DIR/system" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "[1/4] Mounting system and vendor images..."

# Mount system image
SYSTEM_IMG="$OUT_DIR/system.img"
VENDOR_IMG="$OUT_DIR/vendor.img"

if [ -f "$SYSTEM_IMG" ]; then
    mkdir -p "$MOUNT_DIR/system"
    mount -o ro,loop "$SYSTEM_IMG" "$MOUNT_DIR/system"
    echo "  Mounted system.img"
else
    # Some builds produce system directory directly
    if [ -d "$OUT_DIR/system" ]; then
        ln -sf "$OUT_DIR/system" "$MOUNT_DIR/system"
        echo "  Using system directory directly"
    else
        echo "ERROR: No system.img or system/ directory found"
        exit 1
    fi
fi

if [ -f "$VENDOR_IMG" ]; then
    mkdir -p "$MOUNT_DIR/vendor"
    mount -o ro,loop "$VENDOR_IMG" "$MOUNT_DIR/vendor"
    echo "  Mounted vendor.img"
fi

echo "[2/5] Creating root filesystem..."

# Copy system as root
cp -a "$MOUNT_DIR/system/." "$ROOTFS_DIR/"

# Merge vendor into system/vendor
if [ -d "$MOUNT_DIR/vendor" ]; then
    mkdir -p "$ROOTFS_DIR/vendor"
    cp -a "$MOUNT_DIR/vendor/." "$ROOTFS_DIR/vendor/"
fi

# Ensure init exists at root
if [ ! -f "$ROOTFS_DIR/init" ] && [ -f "$ROOTFS_DIR/system/bin/init" ]; then
    ln -sf /system/bin/init "$ROOTFS_DIR/init"
fi

# ─── Inject XAPK split APKs into /system/priv-app/ ──────────────
echo "[3/5] Injecting pre-installed apps (XAPK split APKs)..."

STAGED_APPS_DIR="$SRC_DIR/.hydra-staged-apps"
PRIV_APP_DIR="$ROOTFS_DIR/system/priv-app"
# Fallback: some builds have priv-app at root level
[ -d "$PRIV_APP_DIR" ] || PRIV_APP_DIR="$ROOTFS_DIR/priv-app"
mkdir -p "$PRIV_APP_DIR"

if [ -d "$STAGED_APPS_DIR" ]; then
    for APP_DIR in "$STAGED_APPS_DIR"/*/; do
        [ -d "$APP_DIR" ] || continue
        APP_NAME=$(basename "$APP_DIR")
        TARGET_DIR="$PRIV_APP_DIR/$APP_NAME"

        echo "  Installing $APP_NAME..."
        mkdir -p "$TARGET_DIR"

        # Copy all APK files (base + splits)
        cp "$APP_DIR"/*.apk "$TARGET_DIR/" 2>/dev/null || true

        # Set proper permissions (owner=root, readable by all)
        chmod 755 "$TARGET_DIR"
        chmod 644 "$TARGET_DIR"/*.apk

        APK_COUNT=$(ls "$TARGET_DIR"/*.apk 2>/dev/null | wc -l)
        echo "    Placed $APK_COUNT APK(s) in $TARGET_DIR"
    done
else
    echo "  No staged apps found at $STAGED_APPS_DIR (skipping)"
fi

echo "[4/5] Creating tarball with extended attributes..."

TAR_FILE="$WORK_DIR/rootfs.tar"
cd "$ROOTFS_DIR"
tar --xattrs -cf "$TAR_FILE" .
cd -

TAR_SIZE=$(du -sh "$TAR_FILE" | cut -f1)
echo "  Tarball size: $TAR_SIZE"

echo "[5/5] Importing into Docker..."

IMAGE_ID=$(docker import \
    --change 'ENTRYPOINT ["/init", "androidboot.hardware=redroid"]' \
    "$TAR_FILE" \
    "$IMAGE_NAME:$IMAGE_TAG")

echo ""
echo "════════════════════════════════════════════════"
echo "  Docker image created successfully!"
echo "  Image: $IMAGE_NAME:$IMAGE_TAG"
echo "  ID: $IMAGE_ID"
echo "  Size: $(docker image inspect "$IMAGE_NAME:$IMAGE_TAG" --format='{{.Size}}' | numfmt --to=iec 2>/dev/null || echo 'unknown')"
echo "════════════════════════════════════════════════"
echo ""
echo "Run with:"
echo "  docker run -itd --name phone1 --privileged \\"
echo "    -v /dev/binderfs:/dev/binderfs \\"
echo "    -v phone1-data:/data \\"
echo "    -p 5555:5555 \\"
echo "    $IMAGE_NAME:$IMAGE_TAG"
