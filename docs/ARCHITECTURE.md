# Baro 系统架构说明（Architecture）

## 1. 模块分层（Swift 6 Package）
- **`CNVMeSmart`（C 只读硬件桥接层）**：
  - 通过 `IOKit` `IONVMeSMARTInterface` 免 root 读取 NVMe SSD S.M.A.R.T. 健康度、累计读写单元（TBW）与通电时长。
- **`BaroCore`（纯系统采集与核心模型层，零 AppKit / 零 GUI 依赖）**：
  - `Models/`：`SystemSnapshot`（全值类型 `Sendable` 快照）、`BaroSettings`、`BaroBuildInfo`。
  - `Storage/`：`RingBuffer<T>` 固定容量环形内存缓冲，O(1) 插入，零历史落盘。
  - `Formatting/` & `Localization/`：`ByteFormatter` 等宽格式化与 `BaroL10n` 双语资源。
  - `Diagnostics/`：`HealthAnalyzer` 状态诊断与 `SnapshotExporter` 隐私脱敏纯文本快照导出。
  - `Collectors/`：9 个只读硬件与系统采集器（CPU、统一内存、64 位网络、磁盘与 NVMe、自适应电池与 HID、Apple Silicon 功耗、温度与 SMC 风扇、防休眠断言、父级 `.app` 进程归并）。
  - `Scheduler/CollectorEngine.swift`：无头冷热节流采集引擎，可在 CLI（`--probe`）与测试中脱离桌面环境独立运行。
- **`BaroKit`（macOS 原生桌面与 UI 表现层，可直接单元测试）**：
  - `Scheduler/SamplingCoordinator.swift`：管理冷热切换、息屏/休眠停表与可选只读通知提醒。
  - `App/`：`AppDelegate`（单实例唤醒保护、原生 `isTemplate` 状态栏位图、悬浮面板空闲 20 秒自动释放）与 `GlobalHotKeyManager`（免辅助功能权限的 Carbon 全局热键及冲突检测）。
  - `UI/MenuBar/`：拆分为 `MenuBarImageRenderer`（签名去重与 0.5pt 几何宽度）、`MenuBarStylePainters`（5 种精工风格绘制）与 `MenuBarVectorSymbols`（动态负载偏转表盘与微缩硬件矢量符号）。
  - `UI/Dashboard/` & `UI/Settings/`：Liquid Glass Bento 仪表盘、可展开二级抽屉、实时菜单栏比例预览与偏好设置。
- **`Baro`（极薄可执行入口）**：
  - `BaroMain.swift`：支持 `--probe` 命令行硬件探针自检与标准 GUI 应用启动。

## 2. 冷热分层采样状态机
| 状态 | 触发条件 | 采集范围 | 默认频率 | 特殊策略 |
| :--- | :--- | :--- | :--- | :--- |
| **冷态 (Cold)** | 面板收起（约 99% 时间） | 仅采样菜单栏当前可见指标；默认清空旧进程榜（仅灵动圆环高压态按需节流采样） | 2.0s（低电量翻倍） | 隐藏面板 20 秒后释放 SwiftUI 视图树；`renderSignature` 位图去重；Timer 设 25% tolerance |
| **热态 (Hot)** | 面板展开期间 | 全量采集器（磁盘 4s、防休眠 6s、电池 8s、进程 3s 分级节流） | 1.5s | 打开立即刷新；关闭立即重置热态进程节流基线 |
| **休眠 (Paused)** | `screensDidSleep` / `willSleep` | 全部暂停 | 0 | 唤醒时调用 `resetAllBaselines()` 重置差分基线，杜绝假尖峰 |

## 3. 底层只读接口与稳健性设计
- **CPU**：IORegistry `IOPlatformDevice` 动态读取每核 `cluster-type`（回退 `sysctl`）+ Mach `host_processor_info`（严格 `vm_deallocate`）+ `getloadavg`。
- **内存**：Mach `host_statistics64`（对齐活动监视器口径）+ `vm.swapusage` + `kern.memorystatus_vm_pressure_level`。
- **网络**：`sysctl(NET_RT_IFLIST2)` 真 64 位 `if_data64` 计数器（无 4GB 回绕）+ `getifaddrs` 物理网卡与内网 IPv4 提取。
- **磁盘**：`FileManager.mountedVolumeURLs` + `IOBlockStorageDriver` 吞吐差分 + `IONVMeSMARTInterface`（60s 节流）。
- **电源与外设**：`AppleSmartBattery`（区分台式机 `BatteryInstalled=false` 并提取 `SystemPowerIn`）+ `AppleDeviceManagementHIDEventService` 免蓝牙权限读取键鼠触控板电量。
- **功耗与 GPU**：动态加载 `libIOReport.dylib` 订阅 `Energy Model` 与 `GPU Stats`，结合只读 SMC 与电源遥测补全整机瓦数。
- **温度与风扇**：`IOHIDEventSystemClient`（过滤 M4 休眠核异常值）+ 80 字节对齐只读 `AppleSMC`（含不存在键的负向缓存，消除重复内核调用）。
- **进程归并**：`proc_listallpids`（按真实 PID 数量遍历）+ `(pid, ri_proc_start_abstime)` 复合身份键防 PID 复用串号 + 最外层 `.app` 归并缓存。
