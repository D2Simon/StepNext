# StepNext 1.2.1 · One step closer.

首个 StepNext 公开测试版。原生 macOS 待办与进度管理，蓝白玻璃界面，支持直接在桌面小组件推进任务。

- 单项一行、多步骤两行的紧凑布局。
- 横向步骤连线，点击节点覆盖完成进度。
- 当前只完成第 1 步时，再点第 1 步可回到未开始。
- 可选优先级、可重复使用的类别、日期或文字 DDL。
- 小、中、大、横向超大、纵向超大小组件。
- 独立悬浮小窗及贴边收纳。
- 中英文 README 与独立虚构示例图，不含作者个人待办。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/D2Simon/StepNext/main/install.sh -o install.sh
bash install.sh
```

成品安装不需要 Xcode。脚本下载 Release、校验 SHA-256、验证签名完整性、安装应用并登记小组件。更新时先退出 StepNext；待办不会被删除或上传。

## 测试版限制

Apple Silicon，最低部署目标 macOS 14；在 macOS 27.0 测试。纵向超大号需要 macOS 27。暂不提供 Intel 包。

本 Release 为临时签名、未 Apple 公证的测试版，macOS 可能阻止打开。安装脚本不会移除隔离标记或关闭 Gatekeeper。校验和、GitHub 托管和临时签名都不等于 Apple 公证。

当前没有云同步、到期通知、自动更新或完整英文 UI。源码和素材按 MIT 许可提供。
