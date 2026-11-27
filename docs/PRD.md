# Baro（晴雨表）产品需求文档（PRD）

## 1. 产品愿景与核心定位
- **名称**：Baro（晴雨表）
- **Bundle Identifier**：`com.baro.monitor`
- **Slogan**：`Read-only vitals for macOS. Zero intrusion.`
- **目标平台**：macOS 15.0+（原生针对 Apple Silicon M1–M5 与 macOS 26/27 Liquid Glass 优化）。

## 2. 绝对设计红线（Zero-Intrusion Contract）
1. **纯只读架构**：不提供任何清理垃圾、释放内存、强杀进程、调节风扇转速或修改系统参数的交互与底层实现。
2. **零特权与零残留**：单进程模型，无独立特权 Helper、无 `LaunchDaemon`、无 `WidgetsExtension`。开机自启仅采用苹果官方 `SMAppService.mainApp`。
3. **零权限弹窗与零联网**：不访问网络、不埋点、不弹出赞助弹窗；不引入定位（SSID）与蓝牙（CoreBluetooth）权限弹窗，苹果外设电量仅通过 `IOKit HID` 只读获取。
4. **零磁盘持续写入**：所有历史趋势图仅保留在固定容量的内存环形缓冲区（`RingBuffer`）中；仅偏好设置通过 `UserDefaults` 存储。

## 3. 核心功能规格
- **单槽位菜单栏**：仅注册 1 个 `NSStatusItem`，支持紧凑双行、微图表、静默呼吸点 3 种模式及指标自由组合。
- **Bento 仪表盘下拉面板（364pt 宽）**：
  - Header：机型/芯片识别、开机时长、人话健康状态摘要、设置入口。
  - 核心 2×2 卡片：CPU（支持展开全核心柱状图）、统一内存（三段堆叠条与明细）、芯片功耗/GPU/风扇（支持展开传感器清单）、双向网络吞吐。
  - 硬件扩展双卡：磁盘存储（本地去重卷 + 读写速率）、电源与电池（完整双形态：笔记本电池全指标 + 台式机 AC/外设电量 + 预览模式）。
  - 资源归并排行：仅热态采集，按父级 `.app` 归并子进程，提供 CPU 与内存 Top 5 只读视图。
- **可选轻量本地只读提醒**（默认关闭）：支持针对温度、内存压力、低电量触发带冷却期的系统通知。
