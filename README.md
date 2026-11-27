# Baro（晴雨表）

> **Read-only vitals for macOS. Zero intrusion.**
> 一眼读懂 Mac 晴雨，纯只读、零入侵的 macOS 原生系统状态监控工具。
> Repository: https://github.com/seaskyx2/Baro

## 核心理念

Baro（取自 *Barometer* 晴雨表与 *Menu Bar* 菜单栏的双关）坚持**绝对只读（Read-Only by Construction）**：

- **零控制项、零清理、零写操作**：不杀进程、不改风扇转速、不清理磁盘、不修改任何系统设置。
- **零后台残留**：单进程原生 Swift 应用，无 `PrivilegedHelper`、无 `LaunchDaemon`、无 `WidgetsExtension`。卸载只需把 `Baro.app` 移入废纸篓。
- **零权限弹窗**：不请求定位权限、不请求蓝牙权限（通过 `IOKit HID` 免弹窗读取苹果外设电量）、不联网、零埋点。
- **冷热分层采样**：面板收起时仅采集菜单栏可见的极轻指标，隐藏面板零重绘；点开面板才拉起全量硬件与进程采样；息屏与休眠自动停表。
- **Liquid Glass 原生美学**：基于 macOS 26/27 原生 `.glassEffect` 液态玻璃与 Bento 便当盒布局（macOS 15 自动降级 `.ultraThinMaterial`），全量等宽数字防止跳动。

## 主要功能

- **单槽位菜单栏精工胶囊**：3 种风格（双行精工 / 微图表 / 静默呼吸点），告别刘海屏遮挡与图标乱序。
- **CPU 分核监测**：Apple Silicon P-Core（性能核）与 E-Core（能效核）分簇负载、点击展开全部核心实时柱状图、System Load Average。
- **统一内存**：与“活动监视器”对齐的已用/活跃/联动/压缩内存口径、Swap 用量与系统内存压力等级。
- **Apple Silicon 功耗、GPU 与温度（免 sudo）**：通过 `libIOReport.dylib` 读取 GPU 利用率与能耗，结合 `PowerTelemetryData` 与只读 `AppleSMC` 读取整机实测功耗、各区域温度（含 M4 休眠核滤波）及风扇 RPM。
- **网络与磁盘**：物理网卡实时上下行速率、内网 IP、会话累计流量；本地卷容量与物理磁盘读写吞吐。
- **双形态电源与电池卡片**：笔记本展示环形电量、实时充放电功率、健康度、循环次数、温度与适配器瓦数；台式机展示交流供电实测功率与苹果蓝牙键鼠/触控板电量，并支持在设置中一键预览笔记本电池 UI。
- **按 App 归并资源榜**：将散落的 Helper / Renderer 子进程自动合并到父级 `.app` 下，一眼定位 CPU 或内存消耗元凶。
- **人话健康摘要**：顶部胶囊用简洁中文提示当前系统状态（如 `系统平静 · 零交换压力`）。

## 下载与安装（成品包）

1. 前往 [GitHub Releases](https://github.com/seaskyx2/Baro/releases) 下载最新的 `Baro-v*-macOS-arm64.zip` 并解压。
2. 将 `Baro.app` 拖入 `/Applications`（应用程序）文件夹即可。
3. 由于本项目为开源自签（ad-hoc 签名，未购买 Apple 付费公证），首次双击如遇到系统安全提示，可在终端运行以下命令解除下载隔离属性后正常打开：

```bash
xattr -cr /Applications/Baro.app
open /Applications/Baro.app
```

## 从源码构建与运行

```bash
# 运行单元测试
swift test

# 命令行硬件探针自检（无 GUI 输出全部采集读数）
swift run Baro --probe

# 构建独立 macOS .app 包（输出至 dist/Baro.app）
./scripts/build_app.sh
open dist/Baro.app
```

## 文档

- [产品需求文档（PRD）](docs/PRD.md)
- [系统架构说明](docs/ARCHITECTURE.md)
- [UI / UX 设计规范](docs/DESIGN.md)
