import Carbon.HIToolbox
import Combine
import ServiceManagement

/// 编辑区的行操作快捷键
struct LineActionHotKey: Codable, Equatable {
    static let defaultMakeTask = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey))

    var copyLine: HotKey
    var deleteLine: HotKey
    var makeTask: HotKey

    init(copyLine: HotKey, deleteLine: HotKey, makeTask: HotKey = Self.defaultMakeTask) {
        self.copyLine = copyLine
        self.deleteLine = deleteLine
        self.makeTask = makeTask
    }

    private enum CodingKeys: String, CodingKey {
        case copyLine
        case deleteLine
        case makeTask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        copyLine = try container.decode(HotKey.self, forKey: .copyLine)
        deleteLine = try container.decode(HotKey.self, forKey: .deleteLine)
        // 兼容增加该功能前保存的快捷键配置。
        makeTask = try container.decodeIfPresent(HotKey.self, forKey: .makeTask) ?? Self.defaultMakeTask
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(copyLine, forKey: .copyLine)
        try container.encode(deleteLine, forKey: .deleteLine)
        try container.encode(makeTask, forKey: .makeTask)
    }
}

/// 用户设置，持久化到 UserDefaults
final class SettingsStore: ObservableObject {
    static let taskFontSizeRange: ClosedRange<CGFloat> = 10...32
    static let headingFontSizeRange: ClosedRange<CGFloat> = 14...40

    private let defaults: UserDefaults
    private var isSyncing = false

    /// 目前有效的全局快捷键。只在 Carbon 注册成功后才更新和持久化。
    @Published private(set) var hotKey: HotKey
    @Published private(set) var hotKeyError: String?

    /// 复制当前行快捷键
    @Published var copyLineHotKey: HotKey {
        didSet {
            guard !isSyncing else { return }
            persistLineAction()
        }
    }

    /// 删除当前行快捷键
    @Published var deleteLineHotKey: HotKey {
        didSet {
            guard !isSyncing else { return }
            persistLineAction()
        }
    }

    /// 将当前行转换为任务的快捷键
    @Published var makeTaskHotKey: HotKey {
        didSet {
            guard !isSyncing else { return }
            persistLineAction()
        }
    }

    /// 任务标题字体大小
    @Published var taskFontSize: CGFloat {
        didSet {
            guard !isSyncing else { return }
            defaults.set(Double(taskFontSize), forKey: Keys.taskFontSize)
        }
    }

    /// Markdown 标题字体大小（一级标题基准）
    @Published var headingFontSize: CGFloat {
        didSet {
            guard !isSyncing else { return }
            defaults.set(Double(headingFontSize), forKey: Keys.headingFontSize)
        }
    }

    /// 面板失去焦点后自动隐藏（关闭则变为置顶常驻）
    @Published var autoHideOnFocusLoss: Bool {
        didSet {
            guard !isSyncing else { return }
            defaults.set(autoHideOnFocusLoss, forKey: Keys.autoHide)
        }
    }

    /// 固定后失焦不隐藏；面板本身始终处于浮动层级。
    var isWindowPinned: Bool {
        get { !autoHideOnFocusLoss }
        set { autoHideOnFocusLoss = !newValue }
    }

    /// 登录时自动启动
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncing else { return }
            setLaunchAtLogin(launchAtLogin)
        }
    }

    /// 快捷键变更成功时通知 AppDelegate 刷新菜单栏 tooltip。
    var onHotKeyChange: ((HotKey) -> Void)?

    private enum Keys {
        static let hotKey = "hotKey"
        static let legacyHotKeyPreset = "hotKeyPreset"
        static let autoHide = "autoHideOnFocusLoss"
        static let lineAction = "lineActionHotKeys"
        static let taskFontSize = "taskFontSize"
        static let headingFontSize = "headingFontSize"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSyncing = true
        hotKey = Self.loadHotKey(from: defaults)
        hotKeyError = nil
        autoHideOnFocusLoss = defaults.object(forKey: Keys.autoHide) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let lineAction = Self.loadLineAction(from: defaults)
        copyLineHotKey = lineAction.copyLine
        deleteLineHotKey = lineAction.deleteLine
        makeTaskHotKey = lineAction.makeTask
        taskFontSize = Self.loadFontSize(
            from: defaults,
            key: Keys.taskFontSize,
            fallback: MarkdownDocumentCodec.defaultTaskFontSize,
            range: Self.taskFontSizeRange
        )
        headingFontSize = Self.loadFontSize(
            from: defaults,
            key: Keys.headingFontSize,
            fallback: MarkdownDocumentCodec.defaultHeadingFontSize,
            range: Self.headingFontSizeRange
        )
        isSyncing = false

        // 一次性迁移旧 hotKeyPreset；没有旧值时也写入默认值，之后只读取新格式。
        if defaults.data(forKey: Keys.hotKey) == nil {
            persist(hotKey)
        }
    }

    func clearHotKeyError() {
        hotKeyError = nil
    }

    /// 尝试应用录制的新快捷键。失败时保留既有注册和保存的快捷键。
    @discardableResult
    func setHotKey(_ candidate: HotKey) -> Bool {
        guard candidate.isValid else {
            hotKeyError = "请同时按住至少一个修饰键，例如 ⌥ 或 ⌘"
            return false
        }
        guard candidate != hotKey else {
            hotKeyError = nil
            return true
        }
        guard HotKeyManager.replace(with: candidate) else {
            hotKeyError = "这个快捷键可能已被其他应用或系统占用，原快捷键仍可使用"
            return false
        }
        hotKey = candidate
        persist(candidate)
        hotKeyError = nil
        onHotKeyChange?(candidate)
        return true
    }

    /// App 启动时注册已保存快捷键；保存键若被其他应用抢占则回退默认值。
    func registerInitialHotKey() {
        if HotKeyManager.registerInitial(hotKey) {
            hotKeyError = nil
            return
        }
        let fallback = HotKey.default
        guard hotKey != fallback, HotKeyManager.registerInitial(fallback) else {
            hotKeyError = "当前快捷键无法注册，请在设置中录制新的组合键"
            return
        }
        hotKey = fallback
        persist(fallback)
        hotKeyError = "原快捷键已被占用，已恢复为默认 ⌥空格"
        onHotKeyChange?(fallback)
    }

    private func persist(_ hotKey: HotKey) {
        guard let data = try? JSONEncoder().encode(hotKey) else { return }
        defaults.set(data, forKey: Keys.hotKey)
        defaults.removeObject(forKey: Keys.legacyHotKeyPreset)
    }

    private static func loadHotKey(from defaults: UserDefaults) -> HotKey {
        if let data = defaults.data(forKey: Keys.hotKey),
           let decoded = try? JSONDecoder().decode(HotKey.self, from: data),
           decoded.isValid {
            return decoded
        }
        if let raw = defaults.string(forKey: Keys.legacyHotKeyPreset),
           let legacy = HotKey.legacyPreset(named: raw) {
            return legacy
        }
        return .default
    }

    private func persistLineAction() {
        let action = LineActionHotKey(
            copyLine: copyLineHotKey,
            deleteLine: deleteLineHotKey,
            makeTask: makeTaskHotKey
        )
        guard let data = try? JSONEncoder().encode(action) else { return }
        defaults.set(data, forKey: Keys.lineAction)
    }

    private static func loadLineAction(from defaults: UserDefaults) -> LineActionHotKey {
        let fallback = LineActionHotKey(
            copyLine: HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey)),
            deleteLine: HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
        )
        guard let data = defaults.data(forKey: Keys.lineAction),
              let decoded = try? JSONDecoder().decode(LineActionHotKey.self, from: data),
              decoded.copyLine.isValid, decoded.deleteLine.isValid, decoded.makeTask.isValid else {
            return fallback
        }
        return decoded
    }

    private static func loadFontSize(
        from defaults: UserDefaults,
        key: String,
        fallback: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGFloat {
        let value = defaults.object(forKey: key) as? NSNumber
        let size = value.map { CGFloat($0.doubleValue) } ?? fallback
        return min(max(size, range.lowerBound), range.upperBound)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 注册失败（例如 swift run 裸二进制时），回读真实状态回滚 UI
            isSyncing = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isSyncing = false
        }
    }
}
