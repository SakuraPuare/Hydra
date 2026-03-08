#!/bin/bash
# 02-setup-gapps.sh — Configure MindTheGapps integration
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/redroid-src}"
MANIFEST_DIR="${MANIFEST_DIR:-$(cd "$(dirname "$0")/../manifests" && pwd)}"

cd "$SRC_DIR"

echo "═══════════════════════════════════════"
echo "  Step 2: Setup MindTheGapps"
echo "═══════════════════════════════════════"

# Copy MindTheGapps manifest to local_manifests
echo "[1/3] Adding MindTheGapps manifest..."
cp "$MANIFEST_DIR/mindthegapps.xml" .repo/local_manifests/mindthegapps.xml

# Sync to fetch MindTheGapps vendor
echo "[2/3] Syncing MindTheGapps vendor..."
repo sync -c -j"$(nproc)" --no-tags vendor/gapps

# Patch device makefile to inherit GApps
echo "[3/3] Patching device configuration for GApps..."

DEVICE_MK="device/redroid/redroid/device.mk"
if [ -f "$DEVICE_MK" ]; then
    # Check if GApps already integrated
    if ! grep -q "vendor/gapps" "$DEVICE_MK"; then
        # Add MindTheGapps inherit before the last line
        cat >> "$DEVICE_MK" << 'GAPPS_EOF'

# ─── MindTheGapps ───
$(call inherit-product-if-exists, vendor/gapps/x86_64/x86_64-vendor.mk)
GAPPS_EOF
        echo "  Patched $DEVICE_MK with GApps inherit"
    else
        echo "  GApps already configured in $DEVICE_MK"
    fi
else
    echo "WARNING: $DEVICE_MK not found. You may need to manually integrate GApps."
    echo "  Expected path: $DEVICE_MK"
    echo "  Looking for alternative device makefiles..."
    find device/redroid -name "*.mk" -type f 2>/dev/null | head -10
fi

echo ""
echo "✓ GApps setup complete"
