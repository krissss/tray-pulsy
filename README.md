<div align="center">

# TrayPulsy

**Tray + Pulsy — 托盘心跳，持续感知系统脉动。**

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)]() [![Swift](https://img.shields.io/badge/Swift-6.3-orange)]() [![License: MIT](https://img.shields.io/badge/License-MIT-green)]()

[中文](README.md) · [English](README_EN.md)

</div>

**TrayPulsy** 是一款轻量的 macOS 菜单栏应用，在状态栏显示一个小动画角色，它的奔跑速度随系统使用率实时变化。Mac 越忙，跑得越快！灵感来自 [RunCat365](https://github.com/Kyome22/RunCat365)。

<p align="center">
  <img src="assets/tray.gif" width="600" alt="TrayPulsy Preview">
</p>

## 📦 安装

```bash
brew tap krissss/tap
brew install --cask tray-pulsy
```

> **首次打开提示"已损坏"？** 这是 macOS Gatekeeper 对未签名应用的限制，执行以下命令即可：
> ```bash
> xattr -cr /Applications/TrayPulsy.app
> ```

## ✨ 功能

| 功能           | 说明 |
|--------------|------|
| 🐱 **多款皮肤**  | Cat、Parrot、Horse、Mona、Dab、Pulsy 波形等，支持自定义扩展 |
| ⚡  **动态速度**  | 动画速度可跟随 CPU、GPU、内存或磁盘实时变化 |
| 🔢 **状态栏指标** | 可选择在菜单栏图标旁显示 CPU、GPU、内存、磁盘、网络指标，并设置阈值颜色 |
| 📊 **实时监控**  | 菜单栏 Popover 与概览面板显示实时状态和历史趋势图 |
| 🧭 **进程排行**  | Popover 与概览面板展示 CPU、内存、网络 Top 进程，网络支持多种排序 |
| 🩺 **尖峰诊断**  | CPU、内存或网络突然升高时自动记录事件，并按需抓取当时 Top 进程 |
| 🎛️ **个性化设置** | 支持皮肤、主题、速度来源、帧率限制、状态栏指标和开机启动配置 |
| 🔄 **自动更新**  | 集成 Sparkle 2，可检查、下载、安装更新并重启应用 |
| ♿ **无障碍**    | 支持 VoiceOver，可通过无障碍标签读取状态 |

## 🎨 皮肤

- **内置皮肤**：包含 Cat、Dab、Horse、Mario、Mona、Parrot、PartyBlobCat、Points、RunCat_U，以及程序生成的 Pulsy 波形皮肤。
- **Pulsy 配置**：Pulsy 皮肤支持配色主题、波形样式、线条粗细、发光强度和振幅大小。
- **外部皮肤**：可在设置中选择外部皮肤目录；每个子文件夹是一套 PNG 帧序列，文件夹名即皮肤名，同名会覆盖内置皮肤。

## 📊 系统监控

- **菜单栏 Popover**：左键点击菜单栏图标即可打开实时指标面板，查看当前数值和历史趋势。
- **概览面板**：主界面内展示系统趋势图和 CPU、内存、网络进程排行。
- **进程详情**：CPU 进程占用按整机口径显示，内存同时显示占用量和百分比，网络进程可按活跃度、下行、上行或总量排序。
- **尖峰诊断**：当 CPU、内存或网络指标突然跳高时，概览面板会记录尖峰时间、变化幅度和当时 Top 进程。
- **按需采样**：进程监控仅在 Popover 展开或概览面板可见时运行，关闭后会停止并释放数据。

## 🔄 自动更新

TrayPulsy 使用 Sparkle 2 提供自动更新能力。你可以在关于页面检查更新；新版本会通过 GitHub Release 和 appcast 发布，支持下载、安装并重启到最新版本。

## 🙏 致谢

- **[Kyome22/RunCat365](https://github.com/Kyome22/RunCat365)** — 灵感来源 & Cat、Parrot、Horse 像素素材
- **[chux0519/runcat-tray](https://github.com/chux0519/runcat-tray)** — Mona、Dab、PartyBlobCat 素材
- **[shenbo/runcat-pyqt5-win](https://github.com/shenbo/runcat-pyqt5-win)** — Mario、Points、RunCat_U 素材
