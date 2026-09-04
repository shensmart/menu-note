import Carbon.HIToolbox
import Foundation

/// 用户定义的全局快捷键。keyCode 是 Carbon 虚拟键码，modifiers 使用 Carbon 修饰键掩码。
struct HotKey: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    var displayString: String {
        modifierString + keyDisplayName
    }

    /// 只有修饰键不能注册为全局快捷键。
    var isValid: Bool {
        !modifierString.isEmpty && keyDisplayName != ""
    }

    private var modifierString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    private var keyDisplayName: String {
        HotKey.displayName(for: keyCode)
    }

    static func displayName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Space): "空格",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "↖",
            UInt32(kVK_End): "↘",
            UInt32(kVK_PageUp): "⇞",
            UInt32(kVK_PageDown): "⇟",
            UInt32(kVK_Help): "⌦",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
            UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
            UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
        ]
        if let name = names[keyCode] { return name }

        let letters: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Grave): "`",
        ]
        return letters[keyCode] ?? "键\(keyCode)"
    }

    /// 旧版三个预设的向后兼容迁移。
    static func legacyPreset(named value: String) -> HotKey? {
        switch value {
        case "optionSpace": return .default
        case "cmdOptionM": return HotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey))
        case "ctrlOptionM": return HotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
        default: return nil
        }
    }
}

/// C 回调可达的文件级回调（C 函数指针不能捕获上下文）
private var menuNoteHotKeyCallback: (() -> Void)?

private func menuNoteHotKeyEventHandler(
    _ handlerCallRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return noErr }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if hotKeyID.id == 1 {
        DispatchQueue.main.async { menuNoteHotKeyCallback?() }
    }
    return noErr
}

/// Carbon 全局快捷键注册器，无需辅助功能权限。
final class HotKeyManager {
    static var onToggle: (() -> Void)? {
        get { menuNoteHotKeyCallback }
        set { menuNoteHotKeyCallback = newValue }
    }

    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerInstalled = false
    private static let signature = OSType(0x4D4E5445) // 'MNTE'

    /// 注册首个快捷键。失败时不保存 ref。
    @discardableResult
    static func registerInitial(_ hotKey: HotKey) -> Bool {
        installHandlerIfNeeded()
        guard hotKey.isValid else { return false }
        guard let ref = registerReference(for: hotKey) else { return false }
        hotKeyRef = ref
        return true
    }

    /// 原子替换：新组合键先注册成功，才注销旧组合键。冲突时原快捷键保留可用。
    @discardableResult
    static func replace(with hotKey: HotKey) -> Bool {
        installHandlerIfNeeded()
        guard hotKey.isValid, let replacement = registerReference(for: hotKey) else { return false }
        if let old = hotKeyRef {
            UnregisterEventHotKey(old)
        }
        hotKeyRef = replacement
        return true
    }

    static func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private static func registerReference(for hotKey: HotKey) -> EventHotKeyRef? {
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        return status == noErr ? ref : nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            menuNoteHotKeyEventHandler,
            1,
            &eventType,
            nil,
            nil
        )
    }
}
