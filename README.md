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

## ✨ 功能

| 功能           | 说明 |
|--------------|------|
| 🐱 **多款皮肤**  | Cat、Parrot、Horse、Mona、Dab 等，支持自定义扩展 |
| ⚡  **速度来源**  | 动画速度跟随系统多项指标使用率实时变化 |
| 🎯 **帧率限制**  | 可选多种 fps，节省电量 |
| 🌓 **主题适配**  | 支持多种主题模式，图标自动变色 |
| 📊 **实时指标**  | 概览面板实时显示系统状态 |
| 🔢 **状态栏数值** | 可在图标旁显示多项系统指标 |
| 🚀 **开机启动**  | 支持登录时自动启动（SMAppService） |
| 🔒 **单实例**   | 文件锁防止重复启动 |
| 😴 **休眠暂停**  | 显示器休眠时自动暂停动画 |
| ♿ **无障碍**    | 完整 VoiceOver 支持 |
| 💾 **设置持久化** | 所有偏好通过 UserDefaults 保存 |

## 🎨 皮肤

> 想添加新皮肤？只需将 PNG 帧放入 `Sources/Resources/skins/` 下的文件夹，零代码改动。

## 🙏 致谢

- **[Kyome22/RunCat365](https://github.com/Kyome22/RunCat365)** — 灵感来源 & Cat、Parrot、Horse 像素素材
- **[chux0519/runcat-tray](https://github.com/chux0519/runcat-tray)** — Mona、Dab、PartyBlobCat 素材
- **[shenbo/runcat-pyqt5-win](https://github.com/shenbo/runcat-pyqt5-win)** — Mario、Points、RunCat_U 素材
