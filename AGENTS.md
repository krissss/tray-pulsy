## Project Rules

- **修改 README 时必须同步中英文两个版本**（`README.md` 中文、`README_EN.md` 英文），确保内容一致。
- 涉及 SwiftUI/AppKit 窗口、设置页、Popover 或打包资源的改动，不能只依赖 `swift build`/`swift test`；发布前至少执行 `make app` 并启动本地 `./TrayPulsy.app` 验证目标入口能打开，避免 dev/build 与真实 `.app` 行为不一致。

## Memory Management（内存控制）

本应用是 macOS 菜单栏常驻 app，需要严格控制内存占用。以下是开发中必须遵守的原则：

### 1. 视图按需创建，用完即释放

Popover、Settings 等临时视图，关闭时必须释放 contentViewController / contentView，不要在属性中长期持有。

### 2. 避免隐藏视图中的持续订阅

Timer.publish、onReceive、AsyncStream 等订阅在视图不可见时仍会持有内存，必须随视图释放而停止。

### 3. 数据结构有上限，持久化仅在退出时

内存中的数据缓冲区必须有固定容量上限。磁盘写入仅在退出/睡眠时触发，不做定时全量刷盘。

### 4. 新增功能时的内存检查

- 视图不可见时是否仍占用内存？
- Timer/subscription 是否随视图释放？
- 数据结构是否有大小上限？
- 图片/帧缓存是否有清理机制？

## Sparkle Auto-Update

应用使用 [Sparkle 2](https://sparkle-project.org/) 实现自动更新（下载 + 安装 + 重启）。

- **appcast**：`docs/appcast.xml`，通过 GitHub Pages 托管
- **配置**：`Info.plist` 中 `SUFeedURL` + `SUPublicEDKey`；封装层 `Sources/Core/AppUpdateManager.swift`
- **发布流程**已集成到 `.github/workflows/release.yml`（签名 + 更新 appcast 自动完成）
- **密钥**：EdDSA 私钥需配置为 GitHub Secret `SPARKLE_PRIVATE_KEY`
