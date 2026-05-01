<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **tray-pulsy** (78 symbols, 72 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/tray-pulsy/context` | Codebase overview, check index freshness |
| `gitnexus://repo/tray-pulsy/clusters` | All functional areas |
| `gitnexus://repo/tray-pulsy/processes` | All execution flows |
| `gitnexus://repo/tray-pulsy/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

## Project Rules

- **修改 README 时必须同步中英文两个版本**（`README.md` 中文、`README_EN.md` 英文），确保内容一致。

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


<claude-mem-context>
# Memory Context

# [tray-pulsy] recent context, 2026-05-01 12:07am GMT+8

No previous sessions found.
</claude-mem-context>
