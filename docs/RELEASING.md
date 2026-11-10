# 发布指南

## 默认测试版

```bash
./scripts/test.sh
./scripts/build.sh
./scripts/package.sh
```

`dist/` 中生成 `StepNext-1.4.0-macOS-arm64-adhoc.zip` 及 SHA-256 校验文件。ZIP 只包含应用、MIT 许可和安装说明。不要把 `.build/`、个人数据目录、签名证书或整个本机工作目录上传。

在 GitHub Release 中把这个包标记为 **Pre-release / 测试版**，并写明未公证、可能被 macOS 拦截。建议同时提供源码。不应把普通测试包更名为 `notarized`。

## 正式签名与公证

这一步由维护者执行，使用者不需要 Xcode 或开发者账号。维护者需要有效的 Developer ID Application 证书及 Apple 公证服务凭据。

1. 在本机钥匙串安装自己的证书，使用自己持有的开发者身份。不要上传证书、私钥或密码。
2. 用 Developer ID 构建（身份名称按自己钥匙串中的实际值填写）：

```bash
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
DEVELOPMENT_TEAM='TEAMID' ./scripts/build.sh
```

3. 按 Apple 文档配置 `notarytool` 钥匙串凭据，例如 profile 名 `shixu-notary`。脚本不会创建账号或保存明文凭据。
4. 明确授权提交应用给 Apple 后，在自己的终端运行：

```bash
NOTARY_PROFILE=shixu-notary ./scripts/notarize.sh
```

脚本提交 ZIP，等待公证结果为 Accepted，再附加公证票据并生成 `*-notarized.zip`。临时签名构建会被脚本拒绝。此流程已编写，**因当前机器没有 Developer ID 证书，尚未实际执行签名公证流程**。

5. 在另一台干净 Mac 上下载 Release，验证首次打开、系统小组件登记、主 App 退出后的小组件进度操作，以及数据保存恢复。检查通过后再标记正式发行。

## 版本和标识

- 同步修改 `Config/AppInfo.plist` 与 `Config/WidgetInfo.plist` 中的版本号、构建号。
- 默认 Bundle Identifier 是 `local.shixu.app`，扩展为 `local.shixu.app.widget`。如要改成自己的标识，同步修改工程和 `Source/Shared.swift` 中主 App 使用的扩展容器路径。
- 正式发行后保持标识稳定，否则用户的数据目录会变化。
- 当前默认主 App 不启用沙盒，扩展启用沙盒，直接使用扩展容器共享数据。Mac App Store 版本需要另行设计 App Group 与沙盒方案，不能直接用当前测试配置提交。
- 暂未提供 Intel 或 Universal 成品。不要只修改 ZIP 文件名宣称已支持 Intel。

参考：[Apple 的 macOS 分发说明](https://developer.apple.com/macos/distribution/)、[公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
