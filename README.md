# MacTortoiseSVN

<p align="center">
  <img src="Docs/Assets/wechat-pay.png" alt="MacTortoiseSVN" width="120">
</p>

<p align="center">
  <strong>
    <a href="#english">English</a> · <a href="#中文">中文</a>
  </strong>
</p>

---

# English

A native macOS SVN client inspired by TortoiseSVN, rebuilt around macOS app, extension, sandbox, and process-boundary constraints.

Not just a Windows UI clone — a fast standalone SVN workbench, thin Finder integration, cached badge status, and a service-oriented backend that handles large working copies without making Finder do heavy work.

## Download

[Download Latest Release](https://github.com/MorningStar-Lu/MacMacTortoiseSVN/releases/latest)

1. Download `MacTortoiseSVN.zip`, unzip and drag to `/Applications`
2. Grant file access permission on first launch
3. Enable Finder extension in **System Settings > Privacy & Security > Extensions**

> Requires macOS 14+ and Xcode Command Line Tools (provides `svn`)

## Features

- **Standalone Workbench** — Native SwiftUI macOS client for commit, update, log, browse, diff
- **Finder Integration** — Context menus (Commit / Add / Diff / Refresh) + status badges
- **Status Service** — SQLite cache + FSEvents incremental refresh, never blocks Finder
- **Rust Backend** — mtsvn-rs command bridge with safe svn invocation
- **Security Hardened** — `--` option terminators, parameterized SQL, audit token validation
- **Localization** — Chinese / English UI

## Architecture

```text
MacTortoiseSVN.app          Finder Sync Extension (.appex)
├── SwiftUI Workbench       ├── Badge reads from SQLite cache
├── Commit / Add / Diff     ├── Context menu commands
├── Status cache publish     └── App Group shared state
└── SVNCore client

StatusServiceHost            Rust Core (mtsvn-rs)
├── FSEvents watcher         ├── svn_backend (command wrapper)
├── SQLite badge cache       ├── status_engine (badge pipeline)
└── Incremental refresh      └── Swift process bridge
```

## Build

```sh
# Rust tests
cd rust && /opt/homebrew/bin/cargo test

# Swift tests
env HOME=$PWD/.tmp-home CLANG_MODULE_CACHE_PATH=$PWD/.build/ModuleCache.noindex \
    SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/ModuleCache.noindex swift test

# Build app bundle
./scripts/build_workbench_app.sh

# Install to /Applications
./scripts/install_workbench_app.sh
```

## Remaining Work

- Production signing and notarization
- Larger-scale performance and stress testing
- Native diff / merge UI
- Broader SVN backend coverage
- Stable IPC boundary between Swift and Rust

## License

Licensed under the **Apache License 2.0** — see [LICENSE](LICENSE).

## Support

If this project helps you, sponsorship is welcome.

<p align="center">
  <img src="Docs/Assets/wechat-pay.png" alt="WeChat Pay" width="360">
</p>

---

# 中文

受 TortoiseSVN 启发的原生 macOS SVN 客户端，围绕 macOS 应用、扩展、沙盒和进程边界约束重新设计。

不只是 Windows UI 的克隆——快速的独立 SVN 工作台、轻量 Finder 集成、缓存状态 Badge、面向服务的后端，让大工作副本不会拖慢 Finder。

## 下载

[下载最新 Release](https://github.com/MorningStar-Lu/MacMacTortoiseSVN/releases/latest)

1. 下载 `MacTortoiseSVN.zip`，解压后拖入 `/Applications`
2. 首次打开需授权文件访问权限
3. Finder 扩展在 **系统设置 > 隐私与安全性 > 扩展** 中启用

> 需要 macOS 14+ 且已安装 Xcode Command Line Tools（提供 `svn`）

## 功能特性

- **独立工作台** — 原生 SwiftUI macOS 客户端，支持提交、更新、日志、仓库浏览、Diff
- **Finder 集成** — 右键菜单（Commit / Add / Diff / Refresh）+ 状态 Badge
- **状态服务** — SQLite 缓存 + FSEvents 增量刷新，不阻塞 Finder
- **Rust 后端** — mtsvn-rs 命令桥，安全的 svn 命令调用
- **安全加固** — `--` 选项终止符、参数化 SQL、审计令牌校验
- **本地化** — 中文 / 英文界面

## 架构

```text
MacTortoiseSVN.app          Finder Sync 扩展 (.appex)
├── SwiftUI 工作台           ├── 从 SQLite 缓存读取 Badge
├── 提交 / 添加 / Diff       ├── 右键菜单命令
├── 状态缓存发布              └── App Group 共享状态
└── SVNCore 客户端

StatusServiceHost            Rust 核心 (mtsvn-rs)
├── FSEvents 监听器           ├── svn_backend（命令包装）
├── SQLite Badge 缓存         ├── status_engine（Badge 管道）
└── 增量刷新                  └── Swift 进程桥
```

## 构建

```sh
# Rust 测试
cd rust && /opt/homebrew/bin/cargo test

# Swift 测试
env HOME=$PWD/.tmp-home CLANG_MODULE_CACHE_PATH=$PWD/.build/ModuleCache.noindex \
    SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/ModuleCache.noindex swift test

# 构建应用包
./scripts/build_workbench_app.sh

# 安装到 /Applications
./scripts/install_workbench_app.sh
```

## 待完成

- 正式签名与公证
- 大规模性能与压力测试
- 原生 Diff / Merge 界面
- 更完整的 SVN 后端覆盖
- Swift 与 Rust 之间稳定的 IPC 边界

## 开源协议

本项目基于 **Apache License 2.0** 开源，详见 [LICENSE](LICENSE)。

## 支持项目

如果这个项目对你有帮助，欢迎赞助。

<p align="center">
  <img src="Docs/Assets/wechat-pay.png" alt="微信支付" width="360">
</p>
