# iOS Touch Test Demo

一个原生 iOS 常规触控诊断 App，包含：

- 多点触控上限、彩色轨迹、坐标、压力、接触半径和事件率
- 轨迹连续性与疑似断触提示
- 12 × 24 全屏网格死区覆盖
- 四边与四角分段扫描
- 随机靶心点击精度和误差统计
- 长按坐标漂移与稳定性
- 红绿蓝、黑白、灰阶和彩条显示辅助检查

应用读取 iOS 提供的 `UITouch` 事件，不能访问 Goodix 等触控 IC 的原始电容矩阵或工厂固件接口。

## 免费构建

每次推送到 `main` 后，GitHub Actions 会在 macOS runner 上生成未签名的 `TouchTestApp-unsigned.ipa`。

下载路径：仓库的 **Releases** → **Latest test build** → `TouchTestApp-unsigned.ipa`。

## 安装

IPA 没有 Apple 签名，不能直接从 Safari 安装。请用 SideStore、AltStore 或其他本地签名工具，以测试者自己的 Apple Account 签名后安装。

免费 Apple Account 的签名一般需要每 7 天刷新，并受最多 3 个侧载 App 等限制。
