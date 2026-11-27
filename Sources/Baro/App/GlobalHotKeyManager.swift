import BaroCore
import Carbon.HIToolbox
import Foundation

/// 零辅助功能权限弹窗的全局快捷键管理器（基于 Carbon RegisterEventHotKey）
@MainActor
public final class GlobalHotKeyManager {
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (@MainActor () -> Void)?

    public init() {}

    deinit {
        if let hk = hotKeyRef {
            UnregisterEventHotKey(hk)
        }
        if let eh = eventHandlerRef {
            RemoveEventHandler(eh)
        }
    }

    public func configure(enabled: Bool, preset: GlobalHotKeyPreset, onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
        unregister()
        guard enabled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handlePressed()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard status == noErr else { return }
        self.eventHandlerRef = handlerRef

        let hotKeyID = EventHotKeyID(signature: OSType(0x4241_524F), id: 1) // 'BARO'
        let modifiers: UInt32
        switch preset {
        case .ctrlOptionB:
            modifiers = UInt32(controlKey | optionKey)
        case .ctrlShiftB:
            modifiers = UInt32(controlKey | shiftKey)
        case .optionCommandB:
            modifiers = UInt32(optionKey | cmdKey)
        }

        var hkRef: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hkRef
        )
        if regStatus == noErr {
            self.hotKeyRef = hkRef
        }
    }

    public func unregister() {
        if let hk = hotKeyRef {
            UnregisterEventHotKey(hk)
            hotKeyRef = nil
        }
        if let eh = eventHandlerRef {
            RemoveEventHandler(eh)
            eventHandlerRef = nil
        }
    }

    private func handlePressed() {
        onTrigger?()
    }
}
