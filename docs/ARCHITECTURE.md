# Baro 系统架构说明（Architecture）

## 1. 模块分层
- **BaroCore（纯逻辑与系统采集层，可独立测试）**：
  - `Models/`：`SystemSnapshot`（全不可变 `Sendable` 快照）与 `BaroSettings`。
  - `Storage/`：`RingBuffer<T>` 固定容量环形内存缓冲，O(1) 插入，零历史落盘。
  - `Formatting/`：`ByteFormatter` 提供等宽紧凑格式（菜单栏）与详细格式（面板）。
  - `Diagnostics/`：`HealthAnalyzer` 纯函数评估系统状态并生成人话摘要。
  - `Collectors/`：8 个完全解耦的只读硬件与进程采集器。
  - `Scheduler/`：`SamplingCoordinator` 管理冷热状态机、息屏/休眠监听、定时器容差与可选通知。
- **Baro（macOS 原生表现层）**：
  - `App/`：`BaroMain`（支持 `--probe` 硬件自检）与 `AppDelegate`（单 `NSStatusItem`、无边框悬浮 `NSPanel`、多屏定位、设置窗）。
  - `UI/`：基于 SwiftUI 的 Liquid Glass 主题、可悬停读取游标的折线图、Bento 卡片与设置界面。

## 2. 冷热分层采样状态机
| 状态 | 触发条件 | 采集范围 | 默认频率 | 特殊策略 |
| :--- | :--- | :--- | :--- | :--- |
| **冷态 (Cold)** | 面板收起（约 99% 时间） | 仅采样菜单栏当前勾选显示且需呈现的轻量模块 | 2.0s（低电量自动翻倍） | 不触碰进程树、传感器全表、磁盘卷枚举；Timer 设 25% tolerance 合并内核唤醒 |
| **热态 (Hot)** | 面板展开瞬间及持续打开期间 | 全量 8 个采集器（含按 App 归并 Top 5 进程） | 1.5s | 打开立即触发一次全量刷新；关闭立即销毁热态周期任务 |
| **休眠 (Paused)** | `screensDidSleep` / `willSleep` | 全部暂停 | 0 | 唤醒时调用各差分采集器 `resetBaseline()`，防止时间跨度导致的速率跳变 |

## 3. 底层只读接口清单
- **CPU**：`sysctlbyname`（P/E 核拓扑）+ Mach `host_processor_info`（精确释放 `vm_deallocate`）+ `getloadavg`。
- **内存**：Mach `host_statistics64` + `vm.swapusage` + `kern.memorystatus_vm_pressure_level`。
- **网络**：`getifaddrs`（物理网卡 `en*` 过滤与 `AF_INET` IP 读取）。
- **磁盘**：`FileManager.mountedVolumeURLs` + IOKit `IOBlockStorageDriver` 读写字节统计。
- **电源与外设**：IOKit `AppleSmartBattery` + `AppleDeviceManagementHIDEventService`。
- **功耗与 GPU**：动态加载 `libIOReport.dylib` 订阅 `Energy Model` 与 `GPU Stats`。
- **温度与风扇**：动态加载 `IOKit` `IOHIDEventSystemClient`（复用客户端并过滤 M4 休眠核异常值）+ 只读 `AppleSMC`（`FNum`/`F*Ac` 与温度键兜底）。
- **进程归并**：`libproc`（`proc_listallpids`, `proc_pidinfo`, `proc_pid_rusage`, `proc_pidpath`）+ `mach_timebase_info` 纳秒换算 + 最外层 `.app` 归属合并。
