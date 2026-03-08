# Hydra Redroid 自定义镜像构建指南

基于官方 `redroid/redroid:14.0.0-latest` 镜像，叠加 GApps、ARM 转译、代理内核和预装应用，构建「创建容器即可用」的自定义镜像。

## 镜像组件

| 组件 | 来源 | 用途 |
|------|------|------|
| MindTheGapps | [MustardChef/MindTheGapps-14.0.0-x86_64](https://github.com/MustardChef/MindTheGapps-14.0.0-x86_64) | Google Play Services / Play Store |
| libndk_translation | [zhouziyang/libndk_translation](https://github.com/zhouziyang/libndk_translation) | ARM → x86 二进制转译 |
| Mihomo | [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) (linux-amd64) | 容器内代理，TUN 模式接管流量 |
| WhatsApp / TikTok | APKPure XAPK | 预装业务应用 |

## 目录结构

```
apks/                                  # Git LFS — 手动下载的 XAPK
├── WhatsApp_*.xapk
└── TikTok_*.xapk

deployments/redroid/                   # 构建目录
├── Dockerfile
├── build.sh                           # 构建镜像
├── download.sh                        # 下载/提取所有依赖
├── docker-compose.yml                 # 单容器启动示例
├── mihomo.rc                          # Android init service
├── mihomo-config.yaml                 # Mihomo 默认配置
├── .dockerignore
│
│  以下由 download.sh 生成，已在 .gitignore 中排除：
├── gapps/system/                      # MindTheGapps 解压
├── ndk_translation.tar                # libndk_translation
├── mihomo                             # Mihomo 二进制
├── WhatsApp/                          # WhatsApp split APKs
└── TikTok/                            # TikTok split APKs
```

## 构建流程

### 前提条件

- Docker 29+
- Git LFS（用于拉取 `apks/*.xapk`）
- 宿主机已加载 binder 内核模块并挂载 binderfs：
  ```bash
  modprobe binder_linux
  mount -t binder binder /dev/binderfs
  ```

### 1. 准备 APK

从 [APKPure](https://apkpure.com) 下载 XAPK 文件，放入项目根目录 `apks/`：

- WhatsApp: 搜 `com.whatsapp`，下载 universal 或 x86_64 版本
- TikTok: 搜 `com.zhiliaoapp.musically`，下载 universal 或 x86_64 版本

文件会通过 Git LFS 管理，团队成员 clone 后自动获取。

### 2. 下载依赖 & 提取 APK

```bash
cd deployments/redroid
bash download.sh
```

脚本会自动：
- 下载 MindTheGapps → 解压到 `gapps/system/`
- 下载 libndk_translation → `ndk_translation.tar`
- 下载 Mihomo linux-amd64 → `mihomo`
- 从 `apks/*.xapk` 提取 split APK → `WhatsApp/`、`TikTok/`

### 3. 构建镜像

```bash
bash build.sh
```

产出镜像：`hydra/redroid:14.0.0-hydra`

### 4. 启动容器

使用 docker-compose：

```bash
docker compose up -d
```

或手动 docker run：

```bash
docker run -itd --name phone1 --privileged \
  -v /dev/binderfs:/dev/binderfs \
  -v phone1-data:/data \
  -p 5555:5555 \
  hydra/redroid:14.0.0-hydra \
  androidboot.redroid_width=720 \
  androidboot.redroid_height=1280 \
  androidboot.redroid_dpi=320 \
  androidboot.redroid_fps=30 \
  androidboot.redroid_gpu_mode=guest \
  ro.product.cpu.abilist=x86_64,arm64-v8a,x86,armeabi-v7a,armeabi \
  ro.product.cpu.abilist64=x86_64,arm64-v8a \
  ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi \
  ro.dalvik.vm.isa.arm=x86 \
  ro.dalvik.vm.isa.arm64=x86_64 \
  ro.enable.native.bridge.exec=1 \
  ro.dalvik.vm.native.bridge=libndk_translation.so \
  ro.ndk_translation.version=0.2.3 \
  ro.setupwizard.mode=DISABLED
```

### 5. 连接验证

从远程机器（如 Windows）连接：

```powershell
adb connect <服务器IP>:5555
scrcpy -s <服务器IP>:5555 --no-audio
```

首次启动 GApps 需要初始化，系统完全就绪约需 2-3 分钟。

## 验证清单

```bash
# 以下命令在服务器上通过 docker exec 执行
docker exec phone1 getprop sys.boot_completed                   # 应返回 1
docker exec phone1 getprop ro.dalvik.vm.native.bridge            # 应返回 libndk_translation.so
docker exec phone1 ps -A | grep mihomo                          # 应看到 mihomo 进程
docker exec phone1 ps -A | grep gms                             # 应看到 gms 相关进程
docker exec phone1 pm list packages | grep -E 'whatsapp|musically'  # 应列出两个包
```

## 启动参数说明

| 参数 | 说明 |
|------|------|
| `androidboot.redroid_width/height/dpi` | 屏幕分辨率和密度 |
| `androidboot.redroid_fps` | 帧率，无 GPU 建议 30 |
| `androidboot.redroid_gpu_mode=guest` | 软件渲染（无 GPU），有 GPU 可改 `host` |
| `ro.product.cpu.abilist*` | 声明支持的 CPU ABI，包含 ARM 以启用转译 |
| `ro.dalvik.vm.native.bridge` | 指定 ARM 转译库 |
| `ro.setupwizard.mode=DISABLED` | 跳过 SetupWizard（容器无 WiFi 会导致崩溃循环） |

## Mihomo 代理配置

Mihomo 在容器内以 root 运行，通过 Android init service 管理。

- 默认配置模板：`/system/etc/mihomo/config.yaml`
- 运行时配置：`/data/mihomo/config.yaml`（首次启动自动从模板复制）
- RESTful API：`http://<容器IP>:9090`
- 工作模式：TUN 模式，接管容器内全部流量

后端下发配置流程：
```bash
# 通过 adb push 下发新配置
adb -s <IP>:5555 push config.yaml /data/mihomo/config.yaml
# 重启 mihomo 服务
adb -s <IP>:5555 shell setprop ctl.restart mihomo
```

## 踩坑记录

### 文件权限必须是 644

Android init 拒绝加载 group-writable（664）的 rc 文件，报 `Skipping insecure file`。构建前必须确保所有 `*.rc`、`*.xml` 等配置文件权限为 644，目录为 755。`download.sh` 中对 GApps 解压后的文件已做权限修正。

### SetupWizard 崩溃循环

MindTheGapps 包含 SetupWizard，它在启动时访问 WifiService，而 Redroid 容器无 WiFi 硬件，导致 `SecurityException: WifiService: Permission denied` 无限崩溃（每分钟 680 次）。解决方案：启动参数加 `ro.setupwizard.mode=DISABLED`。

### XAPK 不是 APK

APKPure 下载的 `.xapk` 实际是 ZIP 包，内含 base APK + 多个 config split APK。作为系统应用安装时，需将所有 `.apk` 放在同一目录（如 `/system/app/WhatsApp/`），Android 包管理器会自动识别 split APK。

### libndk_translation 版本

`zhouziyang/libndk_translation` 仓库中 14.0.0 和 13.0.0 都是到 12.0.0 的符号链接，实际是同一份二进制。直接下载 12.0.0 即可。

### Mihomo 选 linux-amd64 而非 android-arm64

虽然容器运行 Android，但 Mihomo 是直接跑在 Linux 内核上的 ELF 二进制，不经过 Android runtime，所以必须用 `linux-amd64` 版本。
