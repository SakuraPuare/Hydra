#!/bin/bash
# 04-build-aosp.sh — Compile AOSP with all customizations
set -euo pipefail

SRC_DIR="/src"
NPROC="${NPROC:-$(nproc)}"

cd "$SRC_DIR"

echo "═══════════════════════════════════════"
echo "  Step 4: Build AOSP"
echo "  Target: redroid_x86_64-userdebug"
echo "  Jobs: $NPROC"
echo "═══════════════════════════════════════"

# Enable ccache
export USE_CCACHE=1
export CCACHE_DIR=/src/.ccache
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G 2>/dev/null || true

# Source build environment
echo "[1/3] Setting up build environment..."
source build/envsetup.sh

# Select build target
echo "[2/3] Selecting target: redroid_x86_64-userdebug..."
lunch redroid_x86_64-userdebug

# Build
echo "[3/3] Starting compilation (this will take 2-4 hours)..."
echo "  Start time: $(date)"

m -j"$NPROC" 2>&1 | tee /src/build.log

echo ""
echo "  End time: $(date)"
echo "✓ Build complete"
echo ""

# Show output location
OUT_DIR="out/target/product/redroid_x86_64"
if [ -d "$OUT_DIR" ]; then
    echo "Build output:"
    ls -lh "$OUT_DIR"/system.img "$OUT_DIR"/vendor.img 2>/dev/null || \
    ls -lh "$OUT_DIR"/*.img 2>/dev/null || \
    echo "  (check $OUT_DIR for output files)"
fi
