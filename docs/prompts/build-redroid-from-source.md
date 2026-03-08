# Prompt: 从 AOSP 源码编译自定义 Redroid 镜像

## 项目背景

我正在搭建一个名为 **Hydra** 的云手机管理系统，核心是在 x86_64 服务器上通过 Docker 运行大量 Android 容器实例（Redroid），每个实例跑 WhatsApp 和 TikTok。

目前已验证的技术栈：
- 宿主机：Dell R630（2x E5-2696 v4, 128GB RAM），Ubuntu 25.10，内核 6.17.0
- 容器运行时：Docker 29.3 + Docker Compose 5.1
- 已成功跑通第三方镜像 `kylindemons/redroid:15.0.0_amd64-GApps-Magisk-latest`，通过 scrcpy 能看到画面
- 内核模块 binder_linux 正常，使用 binderfs 挂载方式（`/dev/binderfs`）
- libndk_translation 已验证可用（ARM → x86 转译层）

## 目标

从 AOSP 源码编译一个自定义的 Redroid Docker 镜像，**一次性内置所有组件**，创建容器即开箱可用。

## 镜像需要包含的组件

### 1. 基础系统
- Android 14 或 15（Redroid 分支）
- 架构：x86_64
- 目标：Docker 容器运行，非物理设备

### 2. GApps（Google 服务）
- 集成 MindTheGapps（WhatsApp 依赖 Google Play Services）
- 参考 Redroid 官方文档的 GApps 集成方式：在 `.repo/local_manifests/` 下添加 MindTheGapps manifest

### 3. libndk_translation（ARM 转译）
- 内置 Google 的 libndk_translation（ARM → x86 转译层）
- 项目参考：https://github.com/zhouziyang/libndk_translation
- 需要配置的 props：
  ```
  ro.product.cpu.abilist=x86_64,arm64-v8a,x86,armeabi-v7a,armeabi
  ro.product.cpu.abilist64=x86_64,arm64-v8a
  ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi
  ro.dalvik.vm.isa.arm=x86
  ro.dalvik.vm.isa.arm64=x86_64
  ro.enable.native.bridge.exec=1
  ro.dalvik.vm.native.bridge=libndk_translation.so
  ```

### 4. Mihomo 代理内核
- 将 Mihomo（Clash Meta 内核）二进制文件集成到 `/system/bin/mihomo`
- 创建 Android init service（`/system/etc/init/mihomo.rc`），实现开机自启、崩溃自动重启
- 默认配置目录：`/data/mihomo/`
- Mihomo 需要以 root 用户运行，监听 tun 或 tproxy 模式做透明代理
- 配置文件由外部（Go 后端）通过 ADB push 下发，镜像内只放一个最小默认配置
- 示例 init service：
  ```
  service mihomo /system/bin/mihomo -d /data/mihomo
      class main
      user root
      group root net_admin net_raw
      seclabel u:r:magisk:s0
      restart on-failure
  ```

### 5. 预装应用
- WhatsApp（以系统应用方式预装到 `/system/app/` 或 `/system/priv-app/`）
- TikTok（同上）
- 注意：以系统应用方式安装可以避免每次创建实例后手动安装

### 6. 设备伪装（可选但建议）
- 修改 build.prop 使设备指纹看起来像真实 Android 手机
- 避免 WhatsApp/TikTok 检测到模拟器环境

## 编译环境要求

- Redroid 源码仓库：https://github.com/remote-android/redroid-doc
- AOSP 编译指南参考：redroid-doc 中的 `android-builder-docker` 目录
- 编译环境：建议使用 Docker 化的编译环境，避免污染宿主机
- 产出物：一个可以直接 `docker run` 的 Redroid Docker 镜像

## 参考资料

- Redroid 官方文档：https://github.com/remote-android/redroid-doc
- Redroid 编译指南：https://github.com/remote-android/redroid-doc/tree/master/android-builder-docker
- libndk_translation 预编译包：https://github.com/zhouziyang/libndk_translation
- GApps 集成 issue：https://github.com/remote-android/redroid-doc/issues/48
- Ivon Blog Redroid 部署教程：https://ivonblog.com/posts/redroid-android-docker/
- Ivon Blog Redroid 多实例：https://ivonblog.com/posts/redroid-multiple-instances/

## 最终交付

1. 完整的编译脚本 / Makefile（一键编译）
2. 编译产出的 Docker 镜像
3. 验证清单：
   - 容器启动后 `sys.boot_completed` 为 1
   - Google Play Store 可用
   - adb shell 中 libndk_translation 加载正常
   - WhatsApp 可打开注册
   - TikTok 可打开浏览
   - Mihomo 进程开机自动运行
   - 从外部可 ADB push 新的 Mihomo 配置并生效

## 运行方式参考

```bash
docker run -itd --name phone1 --privileged \
  -v /dev/binderfs:/dev/binderfs \
  -v phone1-data:/data \
  -p 5555:5555 \
  hydra/redroid:15.0.0-custom \
  androidboot.redroid_width=720 \
  androidboot.redroid_height=1280 \
  androidboot.redroid_dpi=320 \
  androidboot.redroid_fps=30 \
  androidboot.redroid_gpu_mode=guest
```

所有 props 配置应烘焙进镜像默认值，运行时无需手动指定转译层参数。
