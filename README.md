# Baro（晴雨表）

[简体中文](README.md) | [English](README.en.md)

> **Read-only vitals for macOS. Zero intrusion.**
> 一眼读懂 Mac 晴雨，纯只读、零入侵的 macOS 原生系统状态监控工具。
> Repository: https://github.com/seaskyx2/Baro

## 核心理念

Baro（取自 *Barometer* 晴雨表与 *Menu Bar* 菜单栏的双关）坚持**绝对只读（Read-Only by Construction）**：

- **零控制项、零清理、零写操作**：不杀进程、不改风扇转速、不清理磁盘、不修改任何系统设置。
- **零后台残留**：单进程原生 Swift 应用，无 `PrivilegedHelper`、无 `LaunchDaemon`、无 `WidgetsExtension`。卸载只需把 `Baro.app` 移入废纸篓。
- **零权限弹窗**：不请求定位权限、不请求蓝牙权限（通过 `IOKit HID` 免弹窗读取苹果外设电量）、默认不联网（仅在「关于」窗口手动点击检查更新时访问 GitHub）、零埋点。
- **冷热分层采样**：面板收起时仅采集菜单栏可见的极轻指标，隐藏面板零重绘；点开面板才拉起全量硬件与进程采样；息屏与休眠自动停表。
- **Liquid Glass 原生美学**：基于 macOS 26/27 原生 `.glassEffect` 液态玻璃与 Bento 便当盒布局（macOS 15 自动降级 `.ultraThinMaterial`），全量等宽数字防止跳动。

## 主要功能

- **单槽位菜单栏精工仪表**：5 种原生光学比例预设（双行精工 / 单行胶囊 / 脉搏微图 / 精工双柱 / 灵动圆环）与动态负载偏转晴雨表表盘，支持右键秒切与设置内实时比例预览，告别刘海屏遮挡与图标乱序。
- **CPU 分核监测**：Apple Silicon P-Core（性能核）与 E-Core（能效核）分簇负载、点击展开全部核心实时柱状图、System Load Average。
- **统一内存**：与“活动监视器”对齐的已用/活跃/联动/压缩内存口径、Swap 用量与系统内存压力等级。
- **Apple Silicon 功耗、GPU 与温度（免 sudo）**：通过 `libIOReport.dylib` 读取 GPU 利用率与能耗，结合 `PowerTelemetryData` 与只读 `AppleSMC` 读取整机实测功耗、各区域温度（含 M4 休眠核滤波）及风扇 RPM。
- **网络与磁盘空间**：64 位网卡计数器（彻底无 4GB 回绕）实时上下行速率、内网 IP、累计流量；**菜单栏常驻剩余磁盘空间**（支持剩余容量与百分比切换、空间告急变色预警）、主卷/外接卷详情（含 macOS 可清除缓存 Purgeable 识别）、实时读写速率及 **NVMe SSD S.M.A.R.T. 健康度与 TBW**（免 sudo）。
- **防休眠进程只读检测**：调用公开电源管理接口检测阻止息屏/休眠的应用，并在顶部健康摘要与电源卡片中温和提醒。
- **零权限全局快捷键 & 一键脱敏快照**：支持 `⌃⌥B` / `⌃⇧B` / `⌥⌘B` 秒呼出或收起仪表盘（无需辅助功能权限）；一键复制不含 IP/个人路径的纯文本系统快照。
- **双形态电源与电池卡片**：笔记本展示环形电量、实时充放电功率、健康度、循环次数、温度与适配器瓦数；台式机展示交流供电实测功率与苹果蓝牙键鼠/触控板电量，并支持在设置中一键预览笔记本电池 UI。
- **按 App 归并资源榜**：将散落的 Helper / Renderer 子进程自动合并到父级 `.app` 下，一眼定位 CPU 或内存消耗元凶。
- **人话健康摘要**：顶部胶囊用简洁中文提示当前系统状态（如 `系统平静 · 零交换压力`）。

## 设计定位对比

不同系统监控工具各有侧重，Baro 专注于**纯只读、单进程、免权限弹窗**的极简场景：

| 维度 | **Baro** | Stats | AirStats | iStat Menus |
| :--- | :---: | :---: | :---: | :---: |
| 开源协议 | MIT | MIT | 开源 | 商业软件 |
| 定位侧重 | 纯只读单进程 | 模块化全功能（含可选控制与小组件） | 极简状态栏读数 | 专业全维度监控套组 |
| 零定位 / 蓝牙权限弹窗 | ✅ | 视所启模块而定 | ✅ | 视所启模块而定 |
| 单槽位 5 风格（防刘海遮挡） | ✅ | 多槽位独立模块 | 单槽位精简 | ✅ |
| Apple Silicon 免提权功耗 + NVMe TBW + 防休眠提示 | ✅ | 支持功耗与 SMART | 基础硬件读数 | ✅ |
| 隐藏面板自动释放 + 渲染去重 | ✅ | 常驻视图 | ✅ | ✅ |

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

## 文档与使用说明

- **用户指南**：[简体中文使用指南](docs/USER_GUIDE.md) | [English User Guide](docs/USER_GUIDE.en.md)
- **工程设计**：[产品需求文档（PRD）](docs/PRD.md) · [系统架构说明](docs/ARCHITECTURE.md) · [UI / UX 设计规范](docs/DESIGN.md)
