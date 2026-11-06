# iOS Touch Test Demo

一个最小的原生 iOS 多点触控测试 App。屏幕会显示当前触点数量、坐标、压力值和触点位置。

## 免费构建

每次推送到 `main` 后，GitHub Actions 会生成未签名的 `TouchTestApp-unsigned.ipa`。

下载路径：仓库的 **Releases** → **Latest test build** → `TouchTestApp-unsigned.ipa`。

## 安装

IPA 没有 Apple 签名，不能直接从 Safari 安装。请用 SideStore、AltStore 或其他本地签名工具，以测试者自己的 Apple Account 签名后安装。

免费 Apple Account 的签名一般需要每 7 天刷新，并受最多 3 个侧载 App 等限制。
