FROM redroid/redroid:14.0.0-latest

# ============================================
# 1. GApps (MindTheGapps for Android 14 x86_64)
# ============================================
COPY gapps/system/ /system/

# ============================================
# 2. Mihomo 代理内核 (android-amd64)
# ============================================
COPY --chmod=755 mihomo /system/bin/mihomo
COPY --chmod=644 mihomo.rc /system/etc/init/mihomo.rc
COPY --chmod=644 mihomo-config.yaml /system/etc/mihomo/config.yaml

# ============================================
# 3. 预装应用 (split APK — 所有 .apk 放同一目录)
# ============================================
COPY --chmod=755 Via/ /system/app/Via/
COPY --chmod=755 WhatsApp/ /system/app/WhatsApp/
COPY --chmod=755 WhatsAppBusiness/ /system/app/WhatsAppBusiness/
