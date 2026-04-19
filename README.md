# TrayPulsy

> macOS 菜单栏动画工具 — 动画速度跟随系统负载实时变化。

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6.3-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

**TrayPulsy** 是一款轻量的 macOS 菜单栏应用，在状态栏显示一个小动画角色，它的奔跑速度随系统使用率（CPU / GPU / 内存 / 磁盘）实时变化。Mac 越忙，跑得越快！

灵感来自 [Kyome22/RunCat](https://github.com/Kyome22/RunCat)，功能设计参考了 [RunCat365](https://github.com/Yayasyan/RunCat_for_windows)。

## ✨ 功能

| 功能 | 说明 |
|------|------|
| 🐱 **8 款皮肤** | Cat、Parrot、Horse、Mona、Dab、PartyBlobCat、Points、RunCat_U |
| ⚡ **速度来源** | 动画速度跟随 **CPU** / **GPU** / **内存** / **磁盘** 使用率 |
| 🎯 **帧率限制** | 可选 40 / 30 / 20 / 10 fps，节省电量 |
| 🌓 **主题适配** | 跟随系统 / 浅色 / 深色，图标自动变色 |
| 📊 **实时指标** | 概览面板显示 CPU%、内存、磁盘、网速 |
| 🔢 **状态栏数值** | 可在图标旁显示当前指标百分比，自动跟随速度来源 |
| 🚀 **开机启动** | 支持登录时自动启动（SMAppService） |
| 🔒 **单实例** | 文件锁防止重复启动 |
| 😴 **休眠暂停** | 显示器休眠时自动暂停动画 |
| ♿ **无障碍** | 完整 VoiceOver 支持 |
| 💾 **设置持久化** | 所有偏好通过 UserDefaults 保存 |

## 🏗 架构

```
Sources/
├── App/
│   └── App.swift                    # 入口，单实例，开机启动，休眠唤醒
├── Core/
│   ├── SkinManager.swift            # 皮肤加载，主题变色（CIFilter）
│   ├── SystemMonitor.swift          # CPU / 内存 / 磁盘 / GPU 采集（内核 API）
│   ├── TrayAnimator.swift           # 定时器驱动帧动画（RunLoop.common）
│   └── SettingsStore.swift          # 设置持久化（Defaults 库）
├── UI/
│   ├── StatusBarController.swift    # NSStatusItem 管理，设置窗口，无障碍
│   └── Settings/
│       ├── OverviewDetail.swift     # 实时指标概览
│       ├── AppearanceDetail.swift   # 皮肤选择 & 主题
│       ├── GeneralDetail.swift      # 速度来源、帧率、开机启动
│       ├── PerformanceDetail.swift  # 高级性能调优
│       ├── AboutDetail.swift        # 关于页面
│       └── SettingsView.swift       # 设置窗口容器
└── Resources/                       # 各皮肤 PNG 帧序列
```

### 数据流

```
SystemMonitor（后台采样）
    → StatusBarController（每秒读取）
        → SpeedSource.normalizeForAnimation（归一化 0..100）
            → TrayAnimator（调速播放帧）
                → NSStatusItem（菜单栏显示）
```

## 🛠 构建

**前置条件：** Xcode 26+ 或 Swift 6.3+，macOS 26+

```bash
git clone https://github.com/krissss/tray-pulsy.git
cd tray-pulsy
swift build -c release
```

## 🎨 皮肤

| 皮肤 | 帧数 | 风格 |
|------|------|------|
| 🐱 Cat | 5 | 像素风（来自 [RunCat](https://github.com/Kyome22/RunCat)） |
| 🦜 Parrot | 10 | 像素风（来自 [RunCat365](https://github.com/Yayasyan/RunCat_for_windows)） |
| 🐴 Horse | 5 | 像素风（来自 [RunCat365](https://github.com/Yayasyan/RunCat_for_windows)） |
| 🎨 Mona | 7 | 动态贴纸 |
| 💃 Dab | 9 | 动态贴纸 |
| 🎉 PartyBlobCat | 10 | 动态贴纸 |
| ⚫ Points | 8 | 几何动画 |
| 🏃 RunCat_U | 5 | 动态贴纸 |

> 想添加新皮肤？只需将 PNG 帧（18×18 px）放入 `Sources/Resources/` 下的文件夹，零代码改动。

## 🙏 致谢

- **[Kyome22/RunCat](https://github.com/Kyome22/RunCat)** — 原版 macOS 概念 & 猫咪像素素材
- **[Yayasyan/RunCat_for_windows](https://github.com/Yayasyan/RunCat_for_windows)** — 功能灵感（主题、帧率限制、系统指标）

## 📄 许可证

MIT License — 详见 [LICENSE](LICENSE)。
