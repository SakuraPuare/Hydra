#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="hydra/redroid"
IMAGE_TAG="14.0.0-hydra"

# Check prerequisites
MISSING=0
for f in gapps/system mihomo mihomo.rc mihomo-config.yaml Via/Via.apk WhatsApp/WhatsApp.apk WhatsAppBusiness/WhatsAppBusiness.apk; do
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
      -v phone1-data:/data \\
      -p 5555:5555 \\
      ${IMAGE_NAME}:${IMAGE_TAG} \\
      androidboot.use_memfd=true \\
      androidboot.redroid_width=720 \\
      androidboot.redroid_height=1280 \\
      androidboot.redroid_dpi=320 \\
      androidboot.redroid_fps=30 \\
      androidboot.redroid_gpu_mode=guest \\
      ro.setupwizard.mode=DISABLED
EOF
