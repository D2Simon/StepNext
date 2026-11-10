# 安装 StepNext

## 终端一键安装

Apple Silicon Mac、macOS 14 或以上：

```bash
curl -fsSL https://raw.githubusercontent.com/D2Simon/StepNext/main/install.sh -o install.sh
bash install.sh
```

本机已经有脚本或克隆了仓库时，直接运行 `bash install.sh`。

脚本不需要 Xcode、Python、Homebrew、开发者账号或 sudo。它下载 GitHub Release 中的已编译应用，核对 SHA-256、验证代码签名完整性，安装到可写的应用目录，再登记 WidgetKit 扩展。

安装后右键桌面 → 编辑小组件 → 搜索 StepNext。添加、编辑事项仍使用主 App；日常进度操作不需要主 App 常驻。

## 更新与数据

退出 StepNext 后，再次运行安装命令。脚本会保留旧版应用备份，不会删除待办目录。安装过程不会上传任务、分类、账号或其它本机数据。

- 默认位置：`/Applications/StepNext.app`。
- 没有系统目录写权限时：`~/Applications/StepNext.app`。
- 自定义位置：`bash install.sh --destination "$HOME/Applications"`。
- 已下载 ZIP：`bash install.sh --archive /path/to/StepNext-1.3.0-macOS-arm64-adhoc.zip`，旁边必须有同名 `.sha256`。
- 只安装不打开：`bash install.sh --no-open`。
- Fork 仓库：`bash install.sh --repo owner/repo`。

如果目标位置已有不同 Bundle Identifier 的应用，脚本会停止而不会覆盖。若检测到目标应用仍在运行，也会停止并提示先退出。

## 当前测试版说明

文件名带 `adhoc` 表示临时签名、未公证；`unnotarized` 表示未公证的签名构建；`notarized` 表示维护者已完成公证流程。

当前公开测试包没有 Apple 公证，macOS 可能拦截打开。安装脚本不会删除隔离标记、关闭 Gatekeeper 或修改系统安全设置。GitHub 托管、SHA-256 校验和临时签名都不能代替 Apple 公证。普通用户可以等待正式签名版本；开发者也可自行构建源码。

脚本读取包含测试版的最近 Release 列表，在最新兼容 Release 内优先选择已公证包。下载受 GitHub API 可用性及速率限制影响；如果提示尚无兼容资产，需要维护者先发布应用 ZIP 和 `.sha256`。

## 手动安装

从 [Releases](https://github.com/D2Simon/StepNext/releases) 下载应用 ZIP，解压并将 `StepNext.app` 拖入“应用程序”，打开一次，再添加桌面小组件。

在已完成列表点击前面的勾选圆圈，可以将事项设为未完成并自动切换到进行中。单项与多步骤事项都支持，名称、分类、DDL、优先级和步骤名称保留。
