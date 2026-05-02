# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.2] - 2026-04-25

### Fixed

- 修复 make app 构建版本找不到皮肤：添加 skins 子目录搜索路径

### Changed

- CI 添加单元测试 + push/PR 自动触发测试
- 修复 CI 测试 locale 相关断言

## [1.0.1] - 2026-04-24

### Changed

- README 添加 Homebrew 安装方式 + 更新 badge 版本号
- Release 增加 DMG 打包（含 Applications 快捷方式）

## [1.0.0] - 2026-04-24

First release. TrayPulsy is a lightweight macOS menu bar app that displays animated characters whose speed responds in real time to system usage. Supports multiple skins (Cat, Parrot, Horse, Pulsy waveform, etc.), real-time system metrics (CPU, GPU, RAM, SSD, Network), and full customization through a Settings window.

## [Unreleased]

## [1.0.7] - 2026-05-02

### Fixed

- 修复 Sparkle 自动更新签名验证失败：轮换 EdDSA 密钥对

## [1.0.6] - 2026-05-02

### Added

- 菜单栏 Popover 实时指标面板 + 历史趋势图

### Fixed

- 修复测试稳定性：消除 Timer 竞态与跨框架 L10n 共享状态冲突

### Changed

- 优化构建产物大小：14M → 4.5M (-68%)
- 优化菜单栏视图性能：Pulsy 帧缓存 + 移除冗余 Timer

## [1.0.5] - 2026-04-27

### Fixed

- 修复 Sparkle 更新检查无法启动 + 补全 Info.plist 必要字段
- 修复 Xcode 调试运行时的控制台告警

### Changed

- 引入集中式 AppState 管理模式，消除全局单例
- 用 AsyncStream 替代轮询 Timer，实现数据驱动的更新模式
- 重构自动更新：改用 Sparkle 标准 UI（SPUStandardUpdaterController），更新设置迁移至关于页面
- Release Notes appcast 增加 Markdown→HTML 转换，修复 Sparkle 弹窗中显示
- 统一默认皮肤 ID 至 SkinManager.defaultSkinID，默认改为 pulsy

## [1.0.4] - 2026-04-26

### Fixed

- L10n._strings 加 NSLock 线程安全保护，根治跨 suite 竞态导致 CI 测试失败

### Changed

- Release Notes 改为从 CHANGELOG.md 提取，替代 GitHub 自动生成

## [1.0.3] - 2026-04-26

### Added

- 升级至 macOS 26 + Liquid Glass 设计语言 + 侧边栏导航
- 集成 Sparkle 2 自动更新：静默下载安装重启，设置页展示更新状态和 release notes

### Changed

- CI workflow 集成 Sparkle 签名 + appcast 自动生成
- 构建时从 git tag 注入版本号到 Info.plist
- 移除 workflow 的 generate_release_notes 避免重复 Full Changelog

### Docs

- README 添加首次打开提示损坏的解决方法
- AGENTS.md 添加 Sparkle 自动更新文档

[Unreleased]: https://github.com/krissss/tray-pulsy/compare/v1.0.7...HEAD
[1.0.7]: https://github.com/krissss/tray-pulsy/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/krissss/tray-pulsy/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/krissss/tray-pulsy/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/krissss/tray-pulsy/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/krissss/tray-pulsy/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/krissss/tray-pulsy/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/krissss/tray-pulsy/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/krissss/tray-pulsy/releases/tag/v1.0.0
