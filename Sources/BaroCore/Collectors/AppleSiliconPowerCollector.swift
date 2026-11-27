import Darwin
import Foundation

/// 免 root 通过系统动态库 libIOReport 读取 Apple Silicon CPU/GPU/ANE/整机功耗与 GPU 利用率
public final class AppleSiliconPowerCollector: @unchecked Sendable {
    private typealias CopyChannelsInGroupFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias MergeChannelsFn = @convention(c) (CFMutableDictionary, CFDictionary, CFTypeRef?) -> Void
    private typealias CreateSubscriptionFn = @convention(c) (
        UnsafeMutableRawPointer?,
        CFMutableDictionary,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
        UInt64,
        CFTypeRef?
    ) -> UnsafeMutableRawPointer?
    private typealias CreateSamplesFn = @convention(c) (UnsafeMutableRawPointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDeltaFn = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IterateFn = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
    private typealias GetChannelStringFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleGetIntValueFn = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias StateGetCountFn = @convention(c) (CFDictionary) -> Int32
    private typealias StateGetNameFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias StateGetResidencyFn = @convention(c) (CFDictionary, Int32) -> Int64

    private let lock = NSLock()
    private var dylibHandle: UnsafeMutableRawPointer?
    private var subscription: UnsafeMutableRawPointer?
    private var subscribedChannels: CFMutableDictionary?
    private var previousSample: (dict: CFDictionary, timestamp: Date)?

    private var copyChannelsInGroup: CopyChannelsInGroupFn?
    private var mergeChannels: MergeChannelsFn?
    private var createSubscription: CreateSubscriptionFn?
    private var createSamples: CreateSamplesFn?
    private var createSamplesDelta: CreateSamplesDeltaFn?
    private var iterate: IterateFn?
    private var channelGetGroup: GetChannelStringFn?
    private var channelGetSubGroup: GetChannelStringFn?
    private var channelGetName: GetChannelStringFn?
    private var channelGetUnitLabel: GetChannelStringFn?
    private var simpleGetIntValue: SimpleGetIntValueFn?
    private var stateGetCount: StateGetCountFn?
    private var stateGetNameForIndex: StateGetNameFn?
    private var stateGetResidency: StateGetResidencyFn?

    public init() {
        setupIOReport()
    }

    deinit {
        if let sub = subscription {
            Unmanaged<AnyObject>.fromOpaque(sub).release()
        }
        if let handle = dylibHandle {
            dlclose(handle)
        }
    }

    public func resetBaseline() {
        lock.lock()
        previousSample = nil
        lock.unlock()
    }

    public func sample() -> AppleSiliconPowerSnapshot {
        lock.lock()
        defer { lock.unlock() }

        guard let subscription,
              let subscribedChannels,
              let createSamples,
              let createSamplesDelta,
              let iterate else {
            return .empty
        }

        guard let currentSample = createSamples(subscription, subscribedChannels, nil)?.takeRetainedValue() else {
            return .empty
        }

        let now = Date()
        guard let prev = previousSample else {
            previousSample = (currentSample, now)
            return AppleSiliconPowerSnapshot(
                isAvailable: true,
                packageWatts: 0,
                cpuWatts: 0,
                gpuWatts: 0,
                aneWatts: 0,
                dramWatts: 0,
                gpuUsagePercent: 0
            )
        }

        let dt = now.timeIntervalSince(prev.timestamp)
        previousSample = (currentSample, now)

        guard dt > 0.05 && dt < 30.0,
              let delta = createSamplesDelta(prev.dict, currentSample, nil)?.takeRetainedValue() else {
            return AppleSiliconPowerSnapshot(
                isAvailable: true,
                packageWatts: 0,
                cpuWatts: 0,
                gpuWatts: 0,
                aneWatts: 0,
                dramWatts: 0,
                gpuUsagePercent: 0
            )
        }

        var cpuWatts = 0.0
        var gpuWatts = 0.0
        var aneWatts = 0.0
        var dramWatts = 0.0
        var packageWattsDirect: Double?
        var gpuUsagePercent = 0.0

        iterate(delta) { channel -> Int32 in
            let group = self.channelGetGroup?(channel)?.takeUnretainedValue() as String? ?? ""
            let subGroup = self.channelGetSubGroup?(channel)?.takeUnretainedValue() as String? ?? ""
            let name = self.channelGetName?(channel)?.takeUnretainedValue() as String? ?? ""
            let unit = self.channelGetUnitLabel?(channel)?.takeUnretainedValue() as String? ?? ""

            if group == "Energy Model" {
                let rawVal = Double(self.simpleGetIntValue?(channel, 0) ?? 0)
                if rawVal > 0 {
                    let watts = Self.convertEnergyToWatts(value: rawVal, unitLabel: unit, durationSeconds: dt)
                    let upper = name.uppercased()
                    if upper == "CPU ENERGY" {
                        cpuWatts += watts
                    } else if upper == "GPU ENERGY" {
                        gpuWatts += watts
                    } else if upper.hasPrefix("ANE") && upper.contains("ENERGY") {
                        aneWatts += watts
                    } else if upper == "DRAM" || upper == "DRAM ENERGY" {
                        dramWatts += watts
                    } else if upper.contains("PACKAGE") || upper == "ALL" {
                        packageWattsDirect = watts
                    }
                }
            } else if group == "GPU Stats", subGroup == "GPU Performance States" {
                let count = Int(self.stateGetCount?(channel) ?? 0)
                if count > 0 {
                    var totalResidency: Int64 = 0
                    var activeResidency: Int64 = 0
                    for idx in 0..<count {
                        let stateName = (self.stateGetNameForIndex?(channel, Int32(idx))?.takeUnretainedValue() as String? ?? "").uppercased()
                        let residency = max(0, self.stateGetResidency?(channel, Int32(idx)) ?? 0)
                        totalResidency += residency
                        if stateName != "IDLE" && stateName != "OFF" && stateName != "DOWN" && !stateName.isEmpty {
                            activeResidency += residency
                        }
                    }
                    if totalResidency > 0 {
                        gpuUsagePercent = min(100.0, max(0.0, Double(activeResidency) / Double(totalResidency) * 100.0))
                    }
                }
            }
            return 0
        }

        let computedSum = cpuWatts + gpuWatts + aneWatts + dramWatts
        let packageWatts = packageWattsDirect ?? computedSum

        return AppleSiliconPowerSnapshot(
            isAvailable: true,
            packageWatts: max(0, packageWatts),
            cpuWatts: max(0, cpuWatts),
            gpuWatts: max(0, gpuWatts),
            aneWatts: max(0, aneWatts),
            dramWatts: max(0, dramWatts),
            gpuUsagePercent: gpuUsagePercent
        )
    }

    public static func convertEnergyToWatts(value: Double, unitLabel: String, durationSeconds: Double) -> Double {
        guard durationSeconds > 0 else { return 0 }
        let normalized = unitLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let joules: Double
        if normalized == "nJ" {
            joules = value / 1_000_000_000.0
        } else if normalized == "uJ" || normalized == "µJ" {
            joules = value / 1_000_000.0
        } else if normalized == "mJ" {
            joules = value / 1_000.0
        } else if normalized == "J" {
            joules = value
        } else {
            // 默认 Energy Model 多数为 mJ 或 nJ；若为未知标签回退按 nJ 处理
            joules = value / 1_000_000_000.0
        }
        return joules / durationSeconds
    }

    private func setupIOReport() {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW | RTLD_LOCAL) else {
            return
        }
        self.dylibHandle = handle

        func resolve<T>(_ symbol: String, as type: T.Type) -> T? {
            guard let sym = dlsym(handle, symbol) else { return nil }
            return unsafeBitCast(sym, to: type)
        }

        copyChannelsInGroup = resolve("IOReportCopyChannelsInGroup", as: CopyChannelsInGroupFn.self)
        mergeChannels = resolve("IOReportMergeChannels", as: MergeChannelsFn.self)
        createSubscription = resolve("IOReportCreateSubscription", as: CreateSubscriptionFn.self)
        createSamples = resolve("IOReportCreateSamples", as: CreateSamplesFn.self)
        createSamplesDelta = resolve("IOReportCreateSamplesDelta", as: CreateSamplesDeltaFn.self)
        iterate = resolve("IOReportIterate", as: IterateFn.self)
        channelGetGroup = resolve("IOReportChannelGetGroup", as: GetChannelStringFn.self)
        channelGetSubGroup = resolve("IOReportChannelGetSubGroup", as: GetChannelStringFn.self)
        channelGetName = resolve("IOReportChannelGetChannelName", as: GetChannelStringFn.self)
        channelGetUnitLabel = resolve("IOReportChannelGetUnitLabel", as: GetChannelStringFn.self)
        simpleGetIntValue = resolve("IOReportSimpleGetIntegerValue", as: SimpleGetIntValueFn.self)
        stateGetCount = resolve("IOReportStateGetCount", as: StateGetCountFn.self)
        stateGetNameForIndex = resolve("IOReportStateGetNameForIndex", as: StateGetNameFn.self)
        stateGetResidency = resolve("IOReportStateGetResidency", as: StateGetResidencyFn.self)

        guard let copyChannelsInGroup,
              let mergeChannels,
              let createSubscription else {
            return
        }

        let energyDict = copyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        let gpuDict = copyChannelsInGroup("GPU Stats" as CFString, "GPU Performance States" as CFString, 0, 0, 0)?.takeRetainedValue()

        guard let baseDict = energyDict ?? gpuDict else { return }
        guard let mutableChannels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, baseDict) else {
            return
        }
        if energyDict != nil, let gpuDict {
            mergeChannels(mutableChannels, gpuDict, nil)
        }

        var subbedChannels: Unmanaged<CFMutableDictionary>?
        guard let sub = createSubscription(nil, mutableChannels, &subbedChannels, 0, nil),
              let finalChannels = subbedChannels?.takeRetainedValue() else {
            return
        }

        self.subscription = sub
        self.subscribedChannels = finalChannels
    }
}
