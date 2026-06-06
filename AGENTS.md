<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **tray-pulsy** (129 symbols, 121 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## When Debugging

1. `gitnexus_query({query: "<error or symptom>"})` — find execution flows related to the issue
2. `gitnexus_context({name: "<suspect function>"})` — see all callers, callees, and process participation
3. `READ gitnexus://repo/tray-pulsy/process/{processName}` — trace the full execution flow step by step
4. For regressions: `gitnexus_detect_changes({scope: "compare", base_ref: "main"})` — see what your branch changed

## When Refactoring

- **Renaming**: MUST use `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` first. Review the preview — graph edits are safe, text_search edits need manual review. Then run with `dry_run: false`.
- **Extracting/Splitting**: MUST run `gitnexus_context({name: "target"})` to see all incoming/outgoing refs, then `gitnexus_impact({target: "target", direction: "upstream"})` to find all external callers before moving code.
- After any refactor: run `gitnexus_detect_changes({scope: "all"})` to verify only expected files changed.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Tools Quick Reference

| Tool | When to use | Command |
|------|-------------|---------|
| `query` | Find code by concept | `gitnexus_query({query: "auth validation"})` |
| `context` | 360-degree view of one symbol | `gitnexus_context({name: "validateUser"})` |
| `impact` | Blast radius before editing | `gitnexus_impact({target: "X", direction: "upstream"})` |
| `detect_changes` | Pre-commit scope check | `gitnexus_detect_changes({scope: "staged"})` |
| `rename` | Safe multi-file rename | `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` |
| `cypher` | Custom graph queries | `gitnexus_cypher({query: "MATCH ..."})` |

## Impact Risk Levels

| Depth | Meaning | Action |
|-------|---------|--------|
| d=1 | WILL BREAK — direct callers/importers | MUST update these |
| d=2 | LIKELY AFFECTED — indirect deps | Should test |
| d=3 | MAY NEED TESTING — transitive | Test if critical path |

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/tray-pulsy/context` | Codebase overview, check index freshness |
| `gitnexus://repo/tray-pulsy/clusters` | All functional areas |
| `gitnexus://repo/tray-pulsy/processes` | All execution flows |
| `gitnexus://repo/tray-pulsy/process/{name}` | Step-by-step execution trace |

## Self-Check Before Finishing

Before completing any code modification task, verify:
1. `gitnexus_impact` was run for all modified symbols
2. No HIGH/CRITICAL risk warnings were ignored
3. `gitnexus_detect_changes()` confirms changes match expected scope
4. All d=1 (WILL BREAK) dependents were updated

## Keeping the Index Fresh

After committing code changes, the GitNexus index becomes stale. Re-run analyze to update it:

```bash
npx gitnexus analyze
```

If the index previously included embeddings, preserve them by adding `--embeddings`:

```bash
npx gitnexus analyze --embeddings
```

To check whether embeddings exist, inspect `.gitnexus/meta.json` — the `stats.embeddings` field shows the count (0 means no embeddings). **Running analyze without `--embeddings` will delete any previously generated embeddings.**

> Claude Code users: A PostToolUse hook handles this automatically after `git commit` and `git merge`.

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


<claude-mem-context>
# Memory Context

# [tray-pulsy] recent context, 2026-05-01 12:07am GMT+8

No previous sessions found.
</claude-mem-context>
