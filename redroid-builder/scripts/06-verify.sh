#!/bin/bash
# 06-verify.sh — Verify the built Redroid image works correctly
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-hydra/redroid}"
IMAGE_TAG="${IMAGE_TAG:-14.0.0-custom}"
CONTAINER_NAME="hydra-verify-$$"
ADB_PORT=5556
MAX_BOOT_WAIT=120

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC}: $1"; ((WARN++)); }

cleanup() {
    echo ""
    echo "Cleaning up verification container..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "═══════════════════════════════════════"
echo "  Verification: $IMAGE_NAME:$IMAGE_TAG"
echo "═══════════════════════════════════════"

# Check image exists
if ! docker image inspect "$IMAGE_NAME:$IMAGE_TAG" &>/dev/null; then
    echo "ERROR: Image $IMAGE_NAME:$IMAGE_TAG not found"
    echo "  Run 'make package' first"
    exit 1
fi

# ─── Start container ─────────────────────────────────────────────

echo ""
echo "[1/7] Starting container..."

docker run -itd \
    --name "$CONTAINER_NAME" \
    --privileged \
    -v /dev/binderfs:/dev/binderfs \
    -p "$ADB_PORT:5555" \
    "$IMAGE_NAME:$IMAGE_TAG" \
    androidboot.redroid_width=720 \
    androidboot.redroid_height=1280 \
    androidboot.redroid_dpi=320 \
    androidboot.redroid_fps=30 \
    androidboot.redroid_gpu_mode=guest

# ─── Wait for boot ──────────────────────────────────────────────

echo "[2/7] Waiting for boot (max ${MAX_BOOT_WAIT}s)..."

adb connect "localhost:$ADB_PORT" 2>/dev/null || true
sleep 5

BOOT_DONE=0
for i in $(seq 1 "$MAX_BOOT_WAIT"); do
    adb connect "localhost:$ADB_PORT" &>/dev/null || true
    BOOT=$(adb -s "localhost:$ADB_PORT" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
    if [ "$BOOT" = "1" ]; then
        BOOT_DONE=1
        break
    fi
    sleep 1
    printf "\r  Waiting... %ds" "$i"
done
echo ""

if [ "$BOOT_DONE" -eq 1 ]; then
    pass "sys.boot_completed = 1 (booted in ${i}s)"
else
    fail "sys.boot_completed not set after ${MAX_BOOT_WAIT}s"
    echo "  Container may still be booting. Check: docker logs $CONTAINER_NAME"
fi

ADB="adb -s localhost:$ADB_PORT"

# ─── Check Google Play Store ─────────────────────────────────────

echo "[3/7] Checking Google Play Services..."

if $ADB shell pm list packages 2>/dev/null | grep -q "com.android.vending"; then
    pass "Google Play Store installed"
else
    fail "Google Play Store not found"
fi

if $ADB shell pm list packages 2>/dev/null | grep -q "com.google.android.gms"; then
    pass "Google Play Services installed"
else
    fail "Google Play Services not found"
fi

# ─── Check libndk_translation ────────────────────────────────────

echo "[4/7] Checking libndk_translation..."

NDK_BRIDGE=$($ADB shell getprop ro.dalvik.vm.native.bridge 2>/dev/null | tr -d '\r\n')
if [ "$NDK_BRIDGE" = "libndk_translation.so" ]; then
    pass "Native bridge set to libndk_translation.so"
else
    fail "Native bridge: '$NDK_BRIDGE' (expected libndk_translation.so)"
fi

ABILIST=$($ADB shell getprop ro.product.cpu.abilist 2>/dev/null | tr -d '\r\n')
if echo "$ABILIST" | grep -q "arm64-v8a"; then
    pass "ARM ABIs in abilist: $ABILIST"
else
    fail "ARM ABIs missing from abilist: $ABILIST"
fi

NDK_ENABLED=$($ADB shell getprop ro.enable.native.bridge.exec 2>/dev/null | tr -d '\r\n')
if [ "$NDK_ENABLED" = "1" ]; then
    pass "Native bridge execution enabled"
else
    fail "Native bridge execution not enabled"
fi

# ─── Check WhatsApp & TikTok ────────────────────────────────────

echo "[5/7] Checking pre-installed apps..."

if $ADB shell pm list packages 2>/dev/null | grep -q "com.whatsapp"; then
    pass "WhatsApp installed"
else
    warn "WhatsApp not found (may not have been included in build)"
fi

if $ADB shell pm list packages 2>/dev/null | grep -qi "com.zhiliaoapp.musically\|com.ss.android.ugc.trill"; then
    pass "TikTok installed"
else
    warn "TikTok not found (may not have been included in build)"
fi

# ─── Check Mihomo ────────────────────────────────────────────────

echo "[6/7] Checking Mihomo proxy..."

if $ADB shell ls /system/bin/mihomo &>/dev/null; then
    pass "Mihomo binary present at /system/bin/mihomo"
else
    fail "Mihomo binary not found at /system/bin/mihomo"
fi

if $ADB shell ps -A 2>/dev/null | grep -q mihomo; then
    pass "Mihomo process running"
else
    warn "Mihomo process not running (may need config at /data/mihomo/)"
fi

# ─── Check device spoofing ──────────────────────────────────────

echo "[7/7] Checking device fingerprint..."

MODEL=$($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r\n')
if [ "$MODEL" = "Pixel 7" ]; then
    pass "Device model: $MODEL"
else
    warn "Device model: '$MODEL' (expected Pixel 7)"
fi

FINGERPRINT=$($ADB shell getprop ro.build.fingerprint 2>/dev/null | tr -d '\r\n')
if echo "$FINGERPRINT" | grep -q "google/panther"; then
    pass "Build fingerprint spoofed to Pixel 7"
else
    warn "Build fingerprint: '$FINGERPRINT'"
fi

# ─── Summary ─────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "  Verification Results"
echo "═══════════════════════════════════════"
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
echo -e "  ${YELLOW}Warnings: $WARN${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "Some checks failed. Review the output above."
    exit 1
else
    echo "All critical checks passed!"
    exit 0
fi
