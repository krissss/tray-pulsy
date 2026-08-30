## Project Rules

- **修改 README 时必须同步中英文两个版本**（`README.md` 中文、`README_EN.md` 英文），确保内容一致。
- 涉及 SwiftUI/AppKit 窗口、设置页、Popover 或打包资源的改动，不能只依赖 `swift build`/`swift test`；发布前至少执行 `make app` 并启动本地 `./TrayPulsy.app` 验证目标入口能打开，避免 dev/build 与真实 `.app` 行为不一致。

## 皮肤尺寸与渲染标准（与 tray-pulsy-skins 同步）

皮肤帧渲染尺寸必须和 [tray-pulsy-skins](https://github.com/krissss/tray-pulsy-skins) 的网页预览保持一致，否则同一皮肤在「在线预览 / 状态栏 / 浮窗 / 设置页 / 总览页」大小会脱节。**完整规则见该仓库 `AGENTS.md`**，此处为 AI 改动渲染代码时的硬性约束：

- 统一常量（与 skins 仓库 `preview.js` 的 `SCALE_K=3 / DISPLAY_CAP=92 / MAX_FILL=0.8` 等价），**集中定义在 `Sources/Core/SkinSizing.swift` 的 `SkinSizing` 枚举**，不要在各渲染面再复制一份：
  ```text
  SkinSizing.refScale = 3.0 / 92.0   // == SCALE_K / DISPLAY_CAP
  SkinSizing.maxFill  = 0.8          // 最长边最多占框的 80%
  ```
- 缩放公式（box 为渲染面目标盒子，src 为真实像素尺寸）：
  ```text
  upscaleCap   = min(box.w, box.h) * refScale
  maxDimScale  = maxFill * min(box.w, box.h) / max(src.w, src.h)
  fit          = min(upscaleCap, box.w/src.w, box.h/src.h, maxDimScale)
  dest         = src * fit   // 居中绘制
  ```
- **5 个渲染面必须全部调用 `SkinSizing.displaySize(source:box:)`**（不要各写一份缩放公式）：状态栏 `StatusBarView`(22×22)、浮窗 `FloatingSkinFrameView`(22×22)、设置页在线预览 `AppearanceDetail`(40×40)、皮肤选择器 `SkinThumbnail`(34×34)、总览页 `OverviewDetail`(56×56)。要改尺寸标准只动 `Sources/Core/SkinSizing.swift` 一处。
- **铁律**：绝不在加载帧后把 `image.size` 强写成正方形（必须用 cgImage 真实宽高）；绘制层用 aspect-fit/contain 等比缩放，**绝不同时设 `width`/`height` 再依赖 `max-*` 各自截断**（非方 sprite 会被压成方块横向变宽）。
- 帧率/节奏必须镜像 `TrayAnimator.computeInterval`，不另造调速；低帧兜底：帧数 `< 5` 且整圈 `< 0.12s` → 每帧拉伸到 `0.12/count`（最短整圈 120ms），阈值 5 与 120ms 两处一致。
- 改动任一渲染面后，`swift build` 验证编译。

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
