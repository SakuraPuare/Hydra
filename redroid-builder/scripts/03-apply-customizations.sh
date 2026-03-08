#!/bin/bash
# 03-apply-customizations.sh — Apply all custom components
set -euo pipefail

SRC_DIR="/src"
MIHOMO_VERSION="${MIHOMO_VERSION:-v1.19.0}"

cd "$SRC_DIR"

echo "═══════════════════════════════════════"
echo "  Step 3: Apply Customizations"
echo "═══════════════════════════════════════"

DEVICE_MK="device/redroid/redroid/device.mk"

# ─── 1. libndk_translation ───────────────────────────────────────

echo "[1/6] Setting up libndk_translation..."

NDK_VENDOR_DIR="vendor/google/chromeos-x86"

if [ ! -d "$NDK_VENDOR_DIR" ]; then
    echo "  Downloading libndk_translation prebuilt..."
    mkdir -p "$NDK_VENDOR_DIR"

    # Download from zhouziyang/libndk_translation releases
    NDK_URL="https://github.com/nicholass003/libndk-translation/releases/download/v14/libndk_translation_14.zip"
    TMPFILE=$(mktemp)
    curl -fSL "$NDK_URL" -o "$TMPFILE"
    unzip -q -o "$TMPFILE" -d "$NDK_VENDOR_DIR"
    rm -f "$TMPFILE"
    echo "  Extracted to $NDK_VENDOR_DIR"
else
    echo "  libndk_translation already present"
fi

# Create vendor makefile for libndk_translation if not exists
NDK_MK="$NDK_VENDOR_DIR/ndk_translation.mk"
if [ ! -f "$NDK_MK" ]; then
    cat > "$NDK_MK" << 'NDK_EOF'
# libndk_translation - ARM to x86 translation layer
PRODUCT_PACKAGES += \
    libndk_translation

PRODUCT_PROPERTY_OVERRIDES += \
    ro.product.cpu.abilist=x86_64,arm64-v8a,x86,armeabi-v7a,armeabi \
    ro.product.cpu.abilist64=x86_64,arm64-v8a \
    ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi \
    ro.dalvik.vm.isa.arm=x86 \
    ro.dalvik.vm.isa.arm64=x86_64 \
    ro.enable.native.bridge.exec=1 \
    ro.dalvik.vm.native.bridge=libndk_translation.so
NDK_EOF
fi

# Add to device.mk
if [ -f "$DEVICE_MK" ] && ! grep -q "ndk_translation" "$DEVICE_MK"; then
    cat >> "$DEVICE_MK" << 'EOF'

# ─── libndk_translation (ARM → x86) ───
$(call inherit-product-if-exists, vendor/google/chromeos-x86/ndk_translation.mk)
EOF
    echo "  Added libndk_translation to device.mk"
fi

# ─── 2. Mihomo proxy kernel ─────────────────────────────────────

echo "[2/6] Setting up Mihomo..."

MIHOMO_DIR="vendor/hydra/mihomo"
mkdir -p "$MIHOMO_DIR/bin" "$MIHOMO_DIR/etc/init" "$MIHOMO_DIR/etc/mihomo"

# Download mihomo binary
if [ ! -f "$MIHOMO_DIR/bin/mihomo" ]; then
    echo "  Downloading Mihomo ${MIHOMO_VERSION}..."
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-amd64-${MIHOMO_VERSION}.gz"
    curl -fSL "$MIHOMO_URL" | gunzip > "$MIHOMO_DIR/bin/mihomo"
    chmod 755 "$MIHOMO_DIR/bin/mihomo"
    echo "  Downloaded mihomo binary"
else
    echo "  Mihomo binary already present"
fi

# Copy init service and default config from overlay
cp /overlay/system/etc/init/mihomo.rc "$MIHOMO_DIR/etc/init/"
cp /overlay/system/etc/mihomo/config.yaml "$MIHOMO_DIR/etc/mihomo/"

# Create Android.mk for mihomo vendor module
cat > "$MIHOMO_DIR/Android.mk" << 'MIHOMO_MK'
LOCAL_PATH := $(call my-dir)

# mihomo binary
include $(CLEAR_VARS)
LOCAL_MODULE := mihomo
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := bin/mihomo
LOCAL_MODULE_PATH := $(TARGET_OUT)/bin
LOCAL_REQUIRED_MODULES :=
include $(BUILD_PREBUILT)

# mihomo init service
include $(CLEAR_VARS)
LOCAL_MODULE := mihomo.rc
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := etc/init/mihomo.rc
LOCAL_MODULE_PATH := $(TARGET_OUT)/etc/init
include $(BUILD_PREBUILT)

# mihomo default config
include $(CLEAR_VARS)
LOCAL_MODULE := mihomo_config
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := etc/mihomo/config.yaml
LOCAL_MODULE_STEM := config.yaml
LOCAL_MODULE_PATH := $(TARGET_OUT)/etc/mihomo
include $(BUILD_PREBUILT)
MIHOMO_MK

# Add mihomo to device.mk PRODUCT_PACKAGES
if [ -f "$DEVICE_MK" ] && ! grep -q "mihomo" "$DEVICE_MK"; then
    cat >> "$DEVICE_MK" << 'EOF'

# ─── Mihomo Proxy ───
PRODUCT_PACKAGES += \
    mihomo \
    mihomo.rc \
    mihomo_config
EOF
    echo "  Added Mihomo to device.mk"
fi

# ─── 3. Pre-install APKs (WhatsApp & TikTok) ────────────────────
# XAPK files contain split APKs (base + config splits).
# AOSP BUILD_PREBUILT doesn't support split APKs, so we extract them
# into a staging area. The 05-package-image.sh script will inject them
# into /system/priv-app/ in the final filesystem.

echo "[3/6] Preparing pre-installed apps (XAPK split APKs)..."

STAGED_APPS_DIR="/src/.hydra-staged-apps"
mkdir -p "$STAGED_APPS_DIR"

extract_xapk() {
    local APP_NAME="$1"
    local XAPK_GLOB="$2"
    local PACKAGE_NAME="$3"
    local APP_STAGE_DIR="$STAGED_APPS_DIR/$APP_NAME"

    # Find the XAPK file
    local XAPK_FILE
    XAPK_FILE=$(ls /apks/${XAPK_GLOB} 2>/dev/null | head -1)

    if [ -z "$XAPK_FILE" ]; then
        echo "  WARNING: No XAPK matching '$XAPK_GLOB' found in /apks/"
        echo "  $APP_NAME will NOT be pre-installed"
        return 1
    fi

    echo "  Extracting: $(basename "$XAPK_FILE")"
    rm -rf "$APP_STAGE_DIR"
    mkdir -p "$APP_STAGE_DIR"

    # Extract all APKs from XAPK (which is a ZIP)
    unzip -q -o "$XAPK_FILE" '*.apk' -d "$APP_STAGE_DIR/"

    # Rename base APK to match Android's expected convention
    local BASE_APK="$APP_STAGE_DIR/${PACKAGE_NAME}.apk"
    if [ -f "$BASE_APK" ]; then
        mv "$BASE_APK" "$APP_STAGE_DIR/${APP_NAME}.apk"
    fi

    # List what we extracted
    local APK_COUNT
    APK_COUNT=$(find "$APP_STAGE_DIR" -name '*.apk' | wc -l)
    echo "  Staged $APK_COUNT APK(s) for $APP_NAME:"
    find "$APP_STAGE_DIR" -name '*.apk' -printf "    %f (%s bytes)\n"
}

extract_xapk "WhatsApp" "WhatsApp*.xapk" "com.whatsapp"
extract_xapk "TikTok" "TikTok*.xapk" "com.zhiliaoapp.musically"

echo "  Staged apps dir: $STAGED_APPS_DIR"
echo "  (Will be injected into /system/priv-app/ during packaging step)"

# ─── 4. Device fingerprint spoofing ─────────────────────────────

echo "[4/6] Applying device fingerprint spoofing..."

if [ -f "$DEVICE_MK" ] && ! grep -q "ro.build.fingerprint" "$DEVICE_MK"; then
    cat >> "$DEVICE_MK" << 'EOF'

# ─── Device Spoofing (Pixel 7) ───
PRODUCT_PROPERTY_OVERRIDES += \
    ro.build.fingerprint=google/panther/panther:14/AP2A.240805.005/12025142:user/release-keys \
    ro.product.brand=google \
    ro.product.device=panther \
    ro.product.manufacturer=Google \
    ro.product.model=Pixel 7 \
    ro.product.name=panther \
    ro.build.display.id=AP2A.240805.005 \
    ro.build.product=panther \
    ro.build.description=panther-user 14 AP2A.240805.005 12025142 release-keys \
    ro.build.version.security_patch=2024-08-05 \
    ro.boot.hardware.sku=G03Z5 \
    persist.sys.timezone=America/New_York
EOF
    echo "  Applied Pixel 7 device fingerprint"
fi

# ─── 5. Redroid default boot properties ─────────────────────────

echo "[5/6] Setting default Redroid boot properties..."

if [ -f "$DEVICE_MK" ] && ! grep -q "redroid_width" "$DEVICE_MK"; then
    cat >> "$DEVICE_MK" << 'EOF'

# ─── Redroid Default Display Settings ───
PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=320
EOF
    echo "  Applied default display properties"
fi

# ─── 6. SELinux policy for Mihomo ────────────────────────────────

echo "[6/6] Configuring SELinux for Mihomo..."

# In userdebug builds, su context is available. We create a minimal
# sepolicy addition so mihomo can use network capabilities.
SEPOLICY_DIR="device/redroid/redroid/sepolicy"
if [ -d "$SEPOLICY_DIR" ] || mkdir -p "$SEPOLICY_DIR"; then
    if [ ! -f "$SEPOLICY_DIR/mihomo.te" ]; then
        cat > "$SEPOLICY_DIR/mihomo.te" << 'SEPOLICY'
# Allow mihomo to run with network capabilities
# In userdebug builds, we run under su context
allow su self:tun_socket { create };
allow su self:capability { net_admin net_raw };
allow su tun_device:chr_file { open read write ioctl };
SEPOLICY
        echo "  Created SELinux policy for Mihomo"
    fi
fi

echo ""
echo "✓ All customizations applied"
echo ""
echo "Summary of changes to $DEVICE_MK:"
grep -c "PRODUCT_PACKAGES\|PRODUCT_PROPERTY_OVERRIDES\|inherit-product" "$DEVICE_MK" 2>/dev/null || true
