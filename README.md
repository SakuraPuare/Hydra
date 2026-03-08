<p align="center">
  <img src="docs/assets/hydra-logo.png" alt="Hydra" width="200" />
</p>

<h1 align="center">Hydra</h1>

<p align="center">
  <strong>高性能云端 Android 集群管理平台</strong>
</p>

<p align="center">
  <a href="#核心功能">核心功能</a> &bull;
  <a href="#系统架构">系统架构</a> &bull;
  <a href="#快速开始">快速开始</a> &bull;
  <a href="#开发路线">开发路线</a>
</p>

---

Hydra 是一套云原生 Android 设备集群管理系统，基于 [Redroid](https://github.com/remote-android/redroid-doc) 容器化方案，在裸金属服务器上编排和管理数百台 Android 实例。Go 语言构建的控制平面提供完整的实例生命周期管理、浏览器内实时屏幕操控、独立代理网络隔离，所有操作通过统一的 Web 控制台完成。

## 核心功能

**实例管理**
- 一键创建预装应用的 Android 容器实例
- 批量创建、重启、暂停、销毁
- 自定义 Redroid 镜像，内置 Magisk、Mihomo 及业务应用
- 按实例分配 CPU、内存资源上限

**实时屏幕操控**
- 浏览器内低延迟屏幕投射与触控操作
- Scrcpy 采集 → WebSocket 中继 → Canvas 渲染
- 支持同时查看和操控多个实例

**网络与代理**
- 每个实例内运行 Mihomo 内核，独立代理出口
- 控制平面集中下发代理配置，统一管理节点
- 实例间网络完全隔离

**监控与可观测性**
- 原生 Prometheus metrics 端点
- 预置 Grafana 仪表盘，集群级全局视图
- 每实例 CPU、内存、网络、健康状态实时追踪

**应用生命周期**
- 基于 ADB 的批量 APK 安装 / 卸载
- 预构建黄金镜像，内置 WhatsApp、TikTok 及相关依赖
- 实例创建即自动部署应用，开箱即用

## 系统架构

```
┌──────────────────────────────────────────────────────────┐
│                    Hydra 管理控制台                        │
│                  React + TypeScript                       │
│            屏幕操控 / 集群管理 / 代理配置                   │
└────────────────────────┬─────────────────────────────────┘
                         │ REST API + WebSocket
┌────────────────────────▼─────────────────────────────────┐
│                  Hydra Server (Go)                        │
│                                                          │
│  ┌─────────────┐ ┌──────────────┐ ┌───────────────────┐  │
│  │  实例管理器   │ │   屏幕中继    │ │   代理配置管理     │  │
│  │  Instance   │ │   Screen     │ │   Proxy Config    │  │
│  │  Manager    │ │   Relay      │ │   Manager         │  │
│  └──────┬──────┘ └──────┬───────┘ └───────┬───────────┘  │
│         │               │                 │              │
│  ┌──────┴──────┐ ┌──────┴───────┐ ┌───────┴───────────┐  │
│  │  Docker     │ │   Scrcpy     │ │   ADB             │  │
│  │  Engine API │ │   Bridge     │ │   Controller      │  │
│  └─────────────┘ └──────────────┘ └───────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐   │
│  │           Prometheus Metrics /metrics               │   │
│  └────────────────────────────────────────────────────┘   │
└────────────────────────┬─────────────────────────────────┘
                         │ Docker API + ADB
┌────────────────────────▼─────────────────────────────────┐
│                Redroid 容器集群                            │
│                                                          │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐                    │
│  │ 云手机 1 │ │ 云手机 2 │ │ 云手机 N │  ...               │
│  │ Android │ │ Android │ │ Android │                     │
│  │ 11      │ │ 11      │ │ 11      │                     │
│  │         │ │         │ │         │                     │
│  │ Magisk  │ │ Magisk  │ │ Magisk  │                     │
│  │ Mihomo  │ │ Mihomo  │ │ Mihomo  │                     │
│  │ Apps    │ │ Apps    │ │ Apps    │                     │
│  └─────────┘ └─────────┘ └─────────┘                    │
│                                                          │
│  libndk_translation (ARM → x86 指令转译层)                │
└──────────────────────────────────────────────────────────┘
```

## 技术栈

| 层级 | 技术选型 |
|------|---------|
| 前端 | React, TypeScript, Ant Design |
| 后端 | Go, Gin, Docker SDK |
| Android 运行时 | Redroid (Android 11), libndk_translation |
| Root 框架 | Magisk |
| 网络代理 | Mihomo 内核 |
| 屏幕采集 | Scrcpy → WebSocket |
| 数据库 | PostgreSQL |
| 监控 | Prometheus + Grafana |
| 容器运行时 | Docker / Docker Compose |

## 快速开始

### 环境要求

- Linux 宿主机，需加载内核模块：`binder_linux`、`ashmem_linux`
- Docker & Docker Compose
- Go 1.22+
- Node.js 20+

### 1. 加载内核模块

```bash
sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
sudo modprobe ashmem_linux
```

开机自动加载：

```bash
echo "binder_linux" | sudo tee /etc/modules-load.d/redroid.conf
echo "ashmem_linux" | sudo tee -a /etc/modules-load.d/redroid.conf
echo 'options binder_linux devices="binder,hwbinder,vndbinder"' | sudo tee /etc/modprobe.d/redroid.conf
```

### 2. 启动 Hydra

```bash
git clone https://github.com/SakuraPuare/hydra.git
cd hydra
cp .env.example .env    # 配置宿主机 IP、端口、代理参数
make dev                 # 一键启动后端 + 前端 + 数据库
```

### 3. 打开控制台

浏览器访问 `http://localhost:3000`，开始创建云手机实例。

## 项目结构

```
hydra/
├── cmd/
│   └── hydra/              # 程序入口
├── internal/
│   ├── api/                 # REST API 路由与处理器
│   ├── instance/            # 容器生命周期管理
│   ├── screen/              # Scrcpy 桥接与 WebSocket 中继
│   ├── proxy/               # Mihomo 代理配置管理
│   ├── adb/                 # ADB 连接池与指令控制
│   └── metrics/             # Prometheus 指标采集器
├── web/                     # React 前端
│   ├── src/
│   │   ├── pages/           # 控制台、实例详情、屏幕操控页
│   │   ├── components/      # 公共 UI 组件
│   │   └── services/        # API 客户端
│   └── package.json
├── deployments/
│   ├── docker-compose.yml   # 生产环境编排
│   └── redroid/             # 自定义 Redroid 镜像构建
├── configs/                 # 默认配置文件
├── docs/                    # 文档与素材
├── Makefile
├── go.mod
└── README.md
```

## 开发路线

- [x] 系统架构设计
- [ ] 核心实例生命周期管理（创建 / 启动 / 停止 / 销毁）
- [ ] 基于 Web 的实时屏幕操控
- [ ] 自定义 Redroid 镜像（Magisk + Mihomo + 预装应用）
- [ ] 代理配置集中管理
- [ ] Prometheus 指标 & Grafana 仪表盘
- [ ] 批量操作与集群管理
- [ ] 多用户权限控制与实例分配
- [ ] 桌面客户端（Electron / Tauri）
- [ ] 多主机横向扩展
- [ ] 商业化 SaaS 部署

## 许可证

[MIT](LICENSE)

---

<p align="center">
  <sub>为规模而生，为效率而造。</sub>
</p>
