# Prompt: 构建 Hydra 自定义 Redroid Docker 镜像

## 项目背景

Hydra 是一个云手机管理平台，目标是在 x86 服务器上批量运行 Android 容器（Redroid），用于跑 WhatsApp 和 TikTok。

当前环境：
- 宿主机：Ubuntu 25.10，内核 6.17.0，x86_64 架构
- 硬件：Dell R630 (2x E5-2696 v4, 128GB RAM)，无 GPU
- 已安装：Docker 29.3 + Docker Compose 5.1
- 内核模块：binder_linux 已加载，使用 binderfs 挂载方式（`mount -t binder binder /dev/binderfs`）
- 已验证：`redroid/redroid:14.0.0-latest` 能正常启动，scrcpy 可从 Windows 连接操控

## 目标

从官方 Redroid 基础镜像出发，自行叠加所有组件，构建一个完全自主可控的自定义镜像，实现「创建容器即可用」。

## 镜像内容清单

### 基础镜像
`redroid/redroid:14.0.0-latest`（官方 Android 14 裸镜像，x86_64）

### 1. GApps（Google Play 服务）
- 使用 MindTheGapps（Redroid 官方推荐的 GApps 方案）
- 下载对应 Android 14 (API 34) 的 x86_64 版本：https://github.com/nicholaschum/MindTheGapps
- MindTheGapps 包含：Google Play Store、Google Play Services、Google Services Framework 等核心组件
- 解压后将文件叠加到 `/system/` 对应目录
- 需要处理的关键目录：
  - `/system/priv-app/` — GMS 核心应用（GmsCore, Phonesky 等）
  - `/system/app/` — 附加 Google 应用
  - `/system/framework/` — 框架文件
  - `/system/etc/permissions/` — 权限白名单 XML
  - `/system/etc/sysconfig/` — 系统配置
  - `/system/lib64/` 和 `/system/lib/` — 相关 so 库
- 注意：首次启动后 GApps 需要初始化，会有几分钟的启动延迟

### 2. libndk_translation（ARM 转译层）
- 从 https://github.com/zhouziyang/libndk_translation 下载 Android 14 对应的预编译包（14.0.0 版本，x86_64）
- 解压到镜像根目录，会覆盖到 `/system/` 下的相关路径
- 关键文件：
  - `/system/lib64/libndk_translation.so` — 64 位转译库
  - `/system/lib/libndk_translation.so` — 32 位转译库
  - `/system/bin/arm/` 和 `/system/bin/arm64/` — ARM 运行时
  - `/system/etc/binfmt_misc/` — 二进制格式注册
  - `/system/etc/init/ndk_translation_arm64.rc` — init service
- 启动参数中需传入：
  ```
  ro.product.cpu.abilist=x86_64,arm64-v8a,x86,armeabi-v7a,armeabi
  ro.product.cpu.abilist64=x86_64,arm64-v8a
  ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi
  ro.dalvik.vm.isa.arm=x86
  ro.dalvik.vm.isa.arm64=x86_64
  ro.enable.native.bridge.exec=1
  ro.dalvik.vm.native.bridge=libndk_translation.so
  ro.ndk_translation.version=0.2.3
  ```

### 3. Mihomo 代理内核
- 下载 Mihomo 的 **linux-amd64** 版本二进制（注意：容器虽然运行 Android 但底层是 x86_64 Linux 内核，不要下载 android-arm64 版本）
- GitHub Release: https://github.com/MetaCubeX/mihomo/releases
- 放置到 `/system/bin/mihomo`，权限 755
- 创建 Android init service 文件 `/system/etc/init/mihomo.rc`，实现：
  - 开机自动启动（class main）
  - 进程崩溃自动重启（oneshot 或 restart）
  - 以 root 权限运行（user root / group root）
  - 启动命令示例：`/system/bin/mihomo -d /data/mihomo`
- 默认配置文件模板放 `/system/etc/mihomo/config.yaml`
- 首次启动时，init 脚本应将模板配置复制到 `/data/mihomo/config.yaml`（如不存在）
- 后续由 Go 后端通过 ADB push 下发实际配置到 `/data/mihomo/config.yaml` 并重启服务
- Mihomo 配置要点：
  - 使用 TUN 模式或 tproxy 模式接管容器内全部流量
  - mixed-port 或 socks-port 供容器内应用使用
  - external-controller 开启 RESTful API（供后端远程管理）

### 4. 预装应用
- **WhatsApp**：放到 `/system/app/WhatsApp/WhatsApp.apk`
- **TikTok**：放到 `/system/app/TikTok/TikTok.apk`
- 作为系统应用安装（/system/app/），开机直接可用
- APK 文件权限 644，所在目录权限 755
- APK 来源：从 APKMirror 或 APKPure 下载最新稳定版（x86_64 优先，如无则 universal/arm64 均可，有 libndk_translation 转译）

### 5. 容器启动参数（docker run 时传入）
```
androidboot.redroid_width=720
androidboot.redroid_height=1280
androidboot.redroid_dpi=320
androidboot.redroid_fps=30
androidboot.redroid_gpu_mode=guest
```

## Dockerfile

```dockerfile
FROM redroid/redroid:14.0.0-latest

# ============================================
# 1. GApps (MindTheGapps for Android 14 x86_64)
# ============================================
# 需先下载并解压 MindTheGapps 包，整理为 gapps/ 目录结构
# 目录内应包含: system/priv-app/, system/app/, system/framework/,
#              system/etc/permissions/, system/etc/sysconfig/, system/lib64/ 等
COPY gapps/system/ /system/

# 确保权限白名单文件正确
# Google Play Services 需要 privapp-permissions 才能正常工作
COPY gapps/system/etc/permissions/ /system/etc/permissions/
COPY gapps/system/etc/sysconfig/ /system/etc/sysconfig/

# ============================================
# 2. libndk_translation (ARM -> x86 转译)
# ============================================
# 从 zhouziyang/libndk_translation 下载 14.0.0 版本的 tar 包
ADD ndk_translation.tar /

# ============================================
# 3. Mihomo 代理内核
# ============================================
COPY mihomo /system/bin/mihomo
COPY mihomo.rc /system/etc/init/mihomo.rc
RUN mkdir -p /system/etc/mihomo
COPY mihomo-config.yaml /system/etc/mihomo/config.yaml

# ============================================
# 4. 预装应用
# ============================================
RUN mkdir -p /system/app/WhatsApp /system/app/TikTok
COPY WhatsApp.apk /system/app/WhatsApp/WhatsApp.apk
COPY TikTok.apk /system/app/TikTok/TikTok.apk
```

## mihomo.rc 参考内容

```rc
service mihomo /system/bin/mihomo -d /data/mihomo
    class main
    user root
    group root net_admin net_raw inet
    capabilities NET_ADMIN NET_RAW NET_BIND_SERVICE
    seclabel u:r:magisk:s0
    oneshot

on post-fs-data
    mkdir /data/mihomo 0755 root root
    # 如果用户配置不存在，则复制默认模板
    copy /system/etc/mihomo/config.yaml /data/mihomo/config.yaml
    chown root root /data/mihomo/config.yaml
    chmod 644 /data/mihomo/config.yaml
```

## 构建目录结构

```
deployments/redroid/
├── Dockerfile
├── gapps/                  # MindTheGapps 解压后的文件
│   └── system/
│       ├── priv-app/
│       ├── app/
│       ├── framework/
│       ├── etc/
│       │   ├── permissions/
│       │   └── sysconfig/
│       ├── lib/
│       └── lib64/
├── ndk_translation.tar     # libndk_translation 预编译包
├── mihomo                  # Mihomo linux-amd64 二进制
├── mihomo.rc               # Android init service 定义
├── mihomo-config.yaml      # Mihomo 默认配置模板
├── WhatsApp.apk            # WhatsApp APK
├── TikTok.apk              # TikTok APK
└── build.sh                # 一键构建脚本
```

## build.sh 参考

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="hydra/redroid"
IMAGE_TAG="14.0.0-hydra"

echo "==> Building Hydra Redroid image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -t "${IMAGE_NAME}:latest" .

echo "==> Build complete: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "==> Run with:"
echo "    docker run -itd --name phone1 --privileged \\"
echo "      -v /dev/binderfs:/dev/binderfs \\"
echo "      -v phone1-data:/data \\"
echo "      -p 5555:5555 \\"
echo "      ${IMAGE_NAME}:${IMAGE_TAG} \\"
echo "      androidboot.redroid_width=720 \\"
echo "      androidboot.redroid_height=1280 \\"
echo "      androidboot.redroid_dpi=320 \\"
echo "      androidboot.redroid_fps=30 \\"
echo "      androidboot.redroid_gpu_mode=guest \\"
echo "      ro.product.cpu.abilist=x86_64,arm64-v8a,x86,armeabi-v7a,armeabi \\"
echo "      ro.product.cpu.abilist64=x86_64,arm64-v8a \\"
echo "      ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi \\"
echo "      ro.dalvik.vm.isa.arm=x86 \\"
echo "      ro.dalvik.vm.isa.arm64=x86_64 \\"
echo "      ro.enable.native.bridge.exec=1 \\"
echo "      ro.dalvik.vm.native.bridge=libndk_translation.so \\"
echo "      ro.ndk_translation.version=0.2.3"
```

## 构建与测试流程

1. 下载所有依赖文件到 `deployments/redroid/` 目录：
   - MindTheGapps Android 14 x86_64 包 → 解压到 `gapps/`
   - libndk_translation 14.0.0 tar 包 → `ndk_translation.tar`
   - Mihomo linux-amd64 二进制 → `mihomo`
   - WhatsApp APK → `WhatsApp.apk`
   - TikTok APK → `TikTok.apk`
2. 运行 `bash build.sh`
3. 启动测试容器（见 build.sh 输出的命令）
4. 验证清单：
   - [ ] `adb connect <host>:5555` + `scrcpy` 能看到画面
   - [ ] 应用抽屉中有 Google Play Store 且能打开
   - [ ] WhatsApp 和 TikTok 出现在应用列表中且能启动
   - [ ] `adb shell getprop ro.dalvik.vm.native.bridge` 返回 `libndk_translation.so`
   - [ ] `adb shell ps -A | grep mihomo` 确认 Mihomo 进程在运行
   - [ ] Mihomo RESTful API 可访问（验证代理配置下发通道）

## 注意事项

- Redroid 官方镜像是单层结构，Dockerfile 中 RUN 命令的可用性取决于镜像内是否有对应的 shell 工具。优先使用 COPY/ADD，避免依赖 RUN
- Mihomo 二进制要下载 **linux-amd64** 版本（不是 android-arm64），因为它直接运行在容器的 Linux 内核上
- 不需要 Magisk 来获取 root，容器本身 `--privileged` 已经是 root
- 代理网络不能在 Docker 层面编排，因为 Android 的 netd 会搞乱网络规则，所以必须在 Redroid 内部跑 Mihomo
- GPU 模式用 `guest`（软件渲染），后续如果加 GPU 可以改为 `host`
- MindTheGapps 文件的所有者和权限很重要，必须确保与原系统一致（root:root, 755/644）
- libndk_translation tar 包解压时注意保留文件权限和符号链接（tar 解压默认保留）
- WhatsApp 强依赖 Google Play Services，必须先确保 GApps 正常才能测试 WhatsApp
- seclabel 如果 SELinux 策略不包含 magisk context，可改为 `u:r:su:s0` 或 `u:r:init:s0`
