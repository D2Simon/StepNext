# StepNext 1.4.0 · 备忘录

左侧新增「备忘录」：新建多条备忘录，直接输入标题与长篇正文，支持换行、复制粘贴、滚动编辑、按标题或正文搜索，以及字数显示。

输入自动保存，切换页面和退出时也会保存。备忘录仅保存在本机，独立于待办文件，保留上一版备份，保存失败可以重试。删除前会确认。

## 安装或更新

先退出 StepNext，然后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/D2Simon/StepNext/main/install.sh -o install.sh
bash install.sh
```

运行成品不需要 Xcode。Apple Silicon，macOS 14 或以上部署目标；纵向超大号需要 macOS 27。原有数据保留。

仍为临时签名、未 Apple 公证的测试版，macOS 可能拦截打开；脚本不修改系统安全设置。项目演示图只使用虚构数据。
