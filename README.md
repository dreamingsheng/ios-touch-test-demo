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

## 浏览器直接使用（推荐）

公开地址：<https://dreamingsheng.github.io/ios-touch-test-demo/>

在 iPhone Safari 中打开后，点击“共享”→“添加到主屏幕”。PWA 版无需 Apple 签名、证书验证或每 7 天续签，并支持离线使用。

PWA 版目前包含 21 类独立场景：原始多点轨迹、自由绘画、引导划线、鬼点监测、自动跟随、12 × 24 网格、边缘扫描、图片与地图手势、阅读翻页、短视频上下刷、MOBA 轮盘、射击瞄准、常用控件、多级设置菜单、键盘输入、双区十字轴、点击精度、长按漂移、纯色和标准色条。

轨迹直接使用浏览器原生 `PointerEvent`，优先按时间顺序读取 `getCoalescedEvents()` 中的完整采样点，并显示浏览器实际提供的压力和接触宽高；不使用预测点修饰结果。设计原则参考：

- [W3C Pointer Events](https://www.w3.org/TR/pointerevents3/)：触点身份、压力、接触面积及合并事件
- [Google Android CTS Verifier](https://android.googlesource.com/platform/cts/+/master/apps/CtsVerifier/)：手工硬件验证与多点触控可视化
- [Web Platform Tests: Pointer Events](https://wpt.fyi/pointerevents/)：浏览器 Pointer Events 一致性测试

顶部使用 iOS 透明状态栏，背景可以延伸到刘海/灵动岛区域，但标题、按钮和测试内容始终保留在安全区内。网页不能读取或拦截 iPhone 的硬件音量键，因此沉浸模式通过页面按钮切换。

## 免费构建

每次推送到 `main` 后，GitHub Actions 会在 macOS runner 上生成未签名的 `TouchTestApp-unsigned.ipa`。

下载路径：仓库的 **Releases** → **Latest test build** → `TouchTestApp-unsigned.ipa`。

## 安装

IPA 没有 Apple 签名，不能直接从 Safari 安装。请用 SideStore、AltStore 或其他本地签名工具，以测试者自己的 Apple Account 签名后安装。

免费 Apple Account 的签名一般需要每 7 天刷新，并受最多 3 个侧载 App 等限制。
