#!/bin/bash
# Download all dependencies for the Hydra Redroid image build
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Downloading dependencies for Hydra Redroid image..."
echo ""

# ============================================
# 1. MindTheGapps (Android 14 x86_64)
# ============================================
GAPPS_URL="https://github.com/MustardChef/MindTheGapps-14.0.0-x86_64/releases/download/MindTheGapps-14.0.0-x86_64-20250202_012724/MindTheGapps-14.0.0-x86_64-20250202_012724.zip"
GAPPS_ZIP="MindTheGapps-14.0.0-x86_64.zip"

if [ ! -d "gapps/system" ]; then
    echo "==> Downloading MindTheGapps..."
    curl -L -o "$GAPPS_ZIP" "$GAPPS_URL"

    echo "==> Extracting MindTheGapps..."
    rm -rf gapps_tmp gapps
    mkdir -p gapps_tmp
    unzip -q "$GAPPS_ZIP" -d gapps_tmp

    # MindTheGapps zip contains system/ directory structure
    # Find the system directory inside the zip
    mkdir -p gapps
    if [ -d "gapps_tmp/system" ]; then
        mv gapps_tmp/system gapps/system
    else
        # Some versions nest it differently - find it
        SYSTEM_DIR=$(find gapps_tmp -type d -name "system" | head -1)
        if [ -n "$SYSTEM_DIR" ]; then
            mv "$SYSTEM_DIR" gapps/system
        else
            echo "ERROR: Could not find system/ directory in MindTheGapps zip"
            exit 1
        fi
    fi

    rm -rf gapps_tmp
    echo "==> MindTheGapps extracted to gapps/system/"
else
    echo "==> MindTheGapps already extracted, skipping."
fi

# ============================================
# 2. libndk_translation (ARM -> x86 translation)
# ============================================
# 14.0.0 is a symlink to 13.0.0 which links to 12.0.0 (same binary)
NDK_URL="https://raw.githubusercontent.com/zhouziyang/libndk_translation/master/libndk_translation-12.0.0.tar"

if [ ! -f "ndk_translation.tar" ]; then
    echo "==> Downloading libndk_translation..."
    curl -L -o ndk_translation.tar "$NDK_URL"

    # Verify it's a valid tar
    if ! tar tf ndk_translation.tar > /dev/null 2>&1; then
        echo "ERROR: Downloaded ndk_translation.tar is not a valid tar archive"
        rm -f ndk_translation.tar
        exit 1
    fi
    echo "==> libndk_translation downloaded."
else
    echo "==> libndk_translation already downloaded, skipping."
fi

# ============================================
# 3. Mihomo (android-amd64)
# ============================================
MIHOMO_VERSION="v1.19.21"
MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-android-amd64-${MIHOMO_VERSION}.gz"

if [ ! -f "mihomo" ]; then
    echo "==> Downloading Mihomo ${MIHOMO_VERSION}..."
    curl -L -o mihomo.gz "$MIHOMO_URL"

    echo "==> Extracting Mihomo..."
    gunzip mihomo.gz
    chmod 755 mihomo
    echo "==> Mihomo downloaded and extracted."
else
    echo "==> Mihomo already downloaded, skipping."
fi

# ============================================
# 4. APKs (WhatsApp)
# ============================================
# XAPK files are stored in Git LFS at apks/ (project root).
# They contain split APKs (base + config splits) in ZIP format.
APKS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/apks"

prepare_app_pkg() {
    local APP_NAME="$1"
    local PACKAGE_NAME="$2"
    local FILE_GLOB="$3"
    local TARGET_DIR="$SCRIPT_DIR/$APP_NAME"

    if [ -d "$TARGET_DIR" ] && [ -n "$(ls "$TARGET_DIR"/*.apk 2>/dev/null)" ]; then
        echo "==> $APP_NAME already exists, skipping."
        return 0
    fi

    local SRC_FILE
    SRC_FILE=$(ls "$APKS_DIR"/${FILE_GLOB} 2>/dev/null | head -1)

    if [ -z "$SRC_FILE" ]; then
        echo ""
        echo "WARNING: No file matching '${FILE_GLOB}' found in $APKS_DIR/"
        echo "  $APP_NAME will NOT be pre-installed."
        echo "  Download the APK from APKPure and place it in $APKS_DIR/"
        echo ""
        return 1
    fi

    local EXTENSION="${SRC_FILE##*.}"

    echo "==> Processing $APP_NAME from $(basename "$SRC_FILE") ($EXTENSION)..."
    rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"

    if [ "$EXTENSION" = "xapk" ]; then
        unzip -q -o "$SRC_FILE" '*.apk' -d "$TARGET_DIR/"
        if [ -f "$TARGET_DIR/${PACKAGE_NAME}.apk" ]; then
            mv "$TARGET_DIR/${PACKAGE_NAME}.apk" "$TARGET_DIR/${APP_NAME}.apk"
        fi
        echo "==> $APP_NAME: extracted from XAPK."
    else
        cp "$SRC_FILE" "$TARGET_DIR/${APP_NAME}.apk"
        echo "==> $APP_NAME: copied plain APK."
    fi

    local COUNT
    COUNT=$(find "$TARGET_DIR" -name '*.apk' | wc -l)
    echo "==> $APP_NAME: $COUNT APK file(s) ready in $APP_NAME/"
}

prepare_app_pkg "Via" "mark.via" "Via*.apk"
prepare_app_pkg "WhatsApp" "com.whatsapp" "WhatsApp*.apk"
prepare_app_pkg "WhatsAppBusiness" "com.whatsapp.w4b" "WhatsAppBusiness*.xapk"

# ============================================
# Summary
# ============================================
echo ""
echo "==> Download summary:"
echo "    MindTheGapps:       $([ -d gapps/system ] && echo 'OK' || echo 'MISSING')"
echo "    libndk_translation: $([ -f ndk_translation.tar ] && echo 'OK' || echo 'MISSING')"
echo "    Mihomo:             $([ -f mihomo ] && echo 'OK' || echo 'MISSING')"
echo "    Via:                $([ -d Via ] && [ -n "$(ls Via/*.apk 2>/dev/null)" ] && echo 'OK' || echo 'MISSING')"
echo "    WhatsApp:           $([ -d WhatsApp ] && [ -n "$(ls WhatsApp/*.apk 2>/dev/null)" ] && echo 'OK' || echo 'MISSING')"
echo "    WhatsAppBusiness:   $([ -d WhatsAppBusiness ] && [ -n "$(ls WhatsAppBusiness/*.apk 2>/dev/null)" ] && echo "OK ($(ls WhatsAppBusiness/*.apk | wc -l) splits)" || echo 'MISSING')"
echo ""

MISSING=0
[ ! -d "gapps/system" ] && MISSING=1
[ ! -f "ndk_translation.tar" ] && MISSING=1
[ ! -f "mihomo" ] && MISSING=1

VIA_OK=0; WA_OK=0; WAB_OK=0
[ -d "Via" ] && [ -n "$(ls Via/*.apk 2>/dev/null)" ] && VIA_OK=1
[ -d "WhatsApp" ] && [ -n "$(ls WhatsApp/*.apk 2>/dev/null)" ] && WA_OK=1
[ -d "WhatsAppBusiness" ] && [ -n "$(ls WhatsAppBusiness/*.apk 2>/dev/null)" ] && WAB_OK=1

if [ $MISSING -eq 0 ] && [ $VIA_OK -eq 1 ] && [ $WA_OK -eq 1 ] && [ $WAB_OK -eq 1 ]; then
    echo "==> All dependencies ready. Run: bash build.sh"
elif [ $MISSING -eq 0 ]; then
    echo "==> Downloads OK but some APKs missing."
    echo "    Place XAPK files in $APKS_DIR/ and re-run this script."
else
    echo "==> ERROR: Some dependencies failed to download."
    exit 1
fi
