import Foundation
import IOKit.pwr_mgt

/// 纯只读检测当前正在阻止 Mac 休眠或息屏的用户态进程（调用公开 IOPMCopyAssertionsByProcess，零权限弹窗）
public final class SleepAssertionCollector: @unchecked Sendable {
    private static let ignoredSystemProcesses: Set<String> = [
        "powerd",
        "bluetoothd",
        "apsd",
        "coreaudiod",
        "windowserver",
        "hidd",
        "mds",
        "mds_stores",
        "backupd",
        "cloudd",
        "sharingd",
        "useractivityd",
        "loginwindow",
        "dasd",
        "nsurlsessiond",
        "cfprefsd"
    ]

    public init() {}

    public func sample() -> [SleepBlocker] {
        var dictUnmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dictUnmanaged) == kIOReturnSuccess,
              let rawDict = dictUnmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return []
        }

        return Self.parseAssertions(rawDict)
    }

    public static func parseAssertions(_ rawDict: [NSNumber: [[String: Any]]]) -> [SleepBlocker] {
        var blockers: [SleepBlocker] = []
        var seenNames = Set<String>()

        for (pidNum, assertions) in rawDict {
            let pid = pidNum.int32Value
            for entry in assertions {
                let assertType = (entry["AssertType"] as? String) ?? ""
                let preventsDisplay = assertType == "PreventUserIdleDisplaySleep" || assertType == "NoDisplaySleepAssertion"
                let preventsSystem = assertType == "PreventUserIdleSystemSleep" || assertType == "NoIdleSleepAssertion"
                guard preventsDisplay || preventsSystem else { continue }

                let rawName = (entry["Process Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !rawName.isEmpty else { continue }
                if ignoredSystemProcesses.contains(rawName.lowercased()) {
                    continue
                }

                if !seenNames.contains(rawName) {
                    seenNames.insert(rawName)
                    blockers.append(
                        SleepBlocker(
                            pid: pid,
                            processName: rawName,
                            assertionType: assertType,
                            preventsDisplaySleep: preventsDisplay
                        )
                    )
                }
            }
        }

        return blockers.sorted { lhs, rhs in
            if lhs.preventsDisplaySleep != rhs.preventsDisplaySleep {
                return lhs.preventsDisplaySleep && !rhs.preventsDisplaySleep
            }
            return lhs.processName.localizedCaseInsensitiveCompare(rhs.processName) == .orderedAscending
        }
    }
}
