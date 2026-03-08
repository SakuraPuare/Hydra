#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="hydra/redroid"
IMAGE_TAG="14.0.0-hydra"

# Check prerequisites
MISSING=0
for f in gapps/system ndk_translation.tar mihomo mihomo.rc mihomo-config.yaml WhatsApp/WhatsApp.apk TikTok/TikTok.apk; do
    if [ ! -e "$f" ]; then
        echo "ERROR: Missing required file: $f"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "Run 'bash download.sh' first to download auto-downloadable dependencies."
    echo "APKs must be downloaded manually (see download.sh output for instructions)."
    exit 1
fi

echo "==> Building Hydra Redroid image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -t "${IMAGE_NAME}:latest" .

echo "==> Build complete: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "==> Run with:"
cat <<EOF
    docker run -itd --name phone1 --privileged \\
      -v /dev/binderfs:/dev/binderfs \\
      -v phone1-data:/data \\
      -p 5555:5555 \\
      ${IMAGE_NAME}:${IMAGE_TAG} \\
      androidboot.redroid_width=720 \\
      androidboot.redroid_height=1280 \\
      androidboot.redroid_dpi=320 \\
      androidboot.redroid_fps=30 \\
      androidboot.redroid_gpu_mode=guest \\
      ro.product.cpu.abilist=x86_64,arm64-v8a,x86,armeabi-v7a,armeabi \\
      ro.product.cpu.abilist64=x86_64,arm64-v8a \\
      ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi \\
      ro.dalvik.vm.isa.arm=x86 \\
      ro.dalvik.vm.isa.arm64=x86_64 \\
      ro.enable.native.bridge.exec=1 \\
      ro.dalvik.vm.native.bridge=libndk_translation.so \\
      ro.ndk_translation.version=0.2.3 \\
      ro.setupwizard.mode=DISABLED
EOF
