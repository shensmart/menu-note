import AppKit
import SwiftUI

/// 非激活面板：可成为 key window 接收键盘输入，但不会把应用带到前台。
final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 悬浮便签面板：无边框、浮动层级、出现在所有空间（含全屏应用上方），
/// 不抢当前应用的焦点；失焦自动隐藏（可在设置中关闭变为置顶常驻）。
final class PanelController {
    private let panel: NonactivatingPanel
    private let settings: SettingsStore
    private let appState: AppState
    private let interaction = InteractionRelay()
    private var autoHideTask: DispatchWorkItem?
    private var keyMonitor: Any?
    private static let frameDefaultsKey = "panelFrame"
    private static let panelSize = NSSize(width: 420, height: 580)

    init(store: NotesStore, settings: SettingsStore, appState: AppState) {
        self.settings = settings
        self.appState = appState

        panel = NonactivatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "MenuNote"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView?.wantsLayer = true

        let rootView = ContentRootView(
            store: store,
            settings: settings,
            appState: appState,
            interaction: interaction
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
        restoreOrPlaceFrame()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleAutoHide()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        }
        installKeyMonitor()
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - 显示/隐藏

    func show() {
        panel.makeKeyAndOrderFront(nil)
        if !panel.isKeyWindow {
            panel.makeKey()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// 快捷键触发：纯切换
    func toggleFromHotKey() {
        panel.isVisible ? hide() : show()
    }

    /// 点击状态栏图标触发：若面板可见但已失焦，先重新聚焦而不是收起
    func toggleFromUser() {
        suppressAutoHide()
        if panel.isVisible, !panel.isKeyWindow {
            show()
        } else {
            panel.isVisible ? hide() : show()
        }
    }

    /// 短暂抑制「失焦自动隐藏」，避免点击状态栏图标/打开下拉菜单时面板被误关
    func suppressAutoHide(seconds: TimeInterval = 3) {
        autoHideTask?.cancel()
        autoHideTask = nil
        interaction.pendingSuppressUntil = Date().addingTimeInterval(seconds)
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        guard settings.autoHideOnFocusLoss else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.panel.isVisible, !self.panel.isKeyWindow else { return }
            guard Date() >= self.interaction.pendingSuppressUntil else { return }
            self.panel.orderOut(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        autoHideTask = task
    }

    // MARK: - 键盘

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.panel.isVisible, self.panel.isKeyWindow else { return event }
            // Esc：隐藏面板
            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            return event
        }
    }

    // MARK: - 位置记忆

    private func restoreOrPlaceFrame() {
        if let raw = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) {
            let frame = NSRectFromString(raw)
            if frame.width > 100, frame.height > 100, frame.intersects(NSScreen.screens.first?.frame ?? .zero) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        // 默认放到屏幕右上角、菜单栏下方
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.panelSize
        let origin = NSPoint(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 8
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func saveFrame() {
        guard panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameDefaultsKey)
    }
}

/// 让 SwiftUI 层通知 PanelController「用户正在与本面板交互」的中转
final class InteractionRelay {
    var pendingSuppressUntil = Date.distantPast

    func suppress(seconds: TimeInterval = 3) {
        pendingSuppressUntil = Date().addingTimeInterval(seconds)
    }
}
