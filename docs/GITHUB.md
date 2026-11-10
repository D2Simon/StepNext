# GitHub 仓库与发布

仓库：[D2Simon/StepNext](https://github.com/D2Simon/StepNext)。默认分支为 `main`。

## 发布源码

项目使用 MIT 许可。提交前检查 `git status`，不要提交 `.build/`、`dist/`、真实待办、签名证书、私钥或账号配置。

```bash
git add .
git commit -m "Update StepNext"
git push origin main
```

`.gitignore` 已排除构建产物和常见敏感文件。文档示例来自 `Demo/DemoData.swift`，不能换成个人数据截图。

## 发布应用

```bash
./scripts/test.sh
./scripts/build.sh
./scripts/package.sh
bash Tests/InstallerIntegration.sh dist/StepNext-1.4.0-macOS-arm64-adhoc.zip
```

创建 `v1.4.0` GitHub Release，上传以下两个文件：

- `StepNext-1.4.0-macOS-arm64-adhoc.zip`
- `StepNext-1.4.0-macOS-arm64-adhoc.zip.sha256`

测试包标记 Pre-release，说明使用 `docs/RELEASE_NOTES.md`。可以附上 `install.sh` 和源码 ZIP。

**必须同时发布 ZIP 与 SHA-256 文件。** 安装脚本读取最近 20 个非草稿 Release，包括测试版；在最新兼容 Release 内优先选择 notarized、unnotarized、adhoc 包。文件名需保持 `StepNext-版本-macOS-arm64-签名类型.zip`。

README 的安装命令指向 `main/install.sh`；仅上传 README 或源码而没有 Release 资产时，脚本会提示尚无兼容安装包，不会转而要求用户安装 Xcode。

## 自动构建

工作流在推送、PR 或手动触发时执行应用和安装器检查，并保存应用 ZIP 为 artifact；不会自动公证，也不会自动创建 Release。使用 GitHub `xcode-27` runner；其可用性与配额由 GitHub 决定。

正式签名公证见 [RELEASING.md](RELEASING.md)。
