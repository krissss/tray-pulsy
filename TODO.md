# TODO

## 发布与打包

- 后续评估是否将发布包拆分为 `arm64` 和 `x86_64` 两个 DMG，以降低单个安装包体积。
  暂缓原因：`v1.1.3` 刚切换到 Xcode 标准 app target 打包并修复了 GitHub 下载版打开设置页崩溃的问题，当前优先保持 universal binary 发布链路稳定，避免同时引入架构分包、Sparkle 更新包选择、Homebrew 下载资产选择等额外变量。
