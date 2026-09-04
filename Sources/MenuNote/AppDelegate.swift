import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = NotesStore()
    let settings = SettingsStore()
    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()

        settings.onHotKeyChange = { [weak self] _ in
            self?.updateStatusTooltip()
        }
        HotKeyManager.onToggle = { [weak self] in
            self?.panelController?.toggleFromHotKey()
        }
        settings.registerInitialHotKey()

        let controller = PanelController(store: store, settings: settings, appState: appState)
        panelController = controller

        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushSave()
    }

    // MARK: - 状态栏图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "MenuNote 便签")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "MenuNote 便签（\(settings.hotKey.displayString) 呼出，右键打开菜单）"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
        statusItem = item
    }

    /// 左键：呼出/隐藏面板；右键：菜单
    @objc private func statusItemClicked(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            panelController?.toggleFromUser()
        }
    }

    // MARK: - 右键菜单（点击时动态构建）

    private func showStatusMenu() {
        panelController?.suppressAutoHide()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggle = NSMenuItem(
            title: (panelController?.isVisible ?? false) ? "隐藏便签面板" : "显示便签面板",
            action: #selector(menuTogglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let newNote = NSMenuItem(title: "新建便签", action: #selector(menuNewNote), keyEquivalent: "")
        newNote.target = self
        menu.addItem(newNote)

        menu.addItem(.separator())

        let hotkeyHeader = NSMenuItem(title: "当前快捷键：\(settings.hotKey.displayString)", action: nil, keyEquivalent: "")
        hotkeyHeader.isEnabled = false
        menu.addItem(hotkeyHeader)

        let hotkeySettings = NSMenuItem(title: "设置自定义快捷键…", action: #selector(menuOpenHotKeySettings), keyEquivalent: "")
        hotkeySettings.target = self
        menu.addItem(hotkeySettings)

        let pin = NSMenuItem(title: "固定窗口", action: #selector(menuTogglePin), keyEquivalent: "")
        pin.target = self
        pin.state = settings.isWindowPinned ? .on : .off
        menu.addItem(pin)

        let launch = NSMenuItem(title: "登录时自动启动", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())

        let reveal = NSMenuItem(title: "在 Finder 中显示便签文件夹", action: #selector(menuReveal), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let quit = NSMenuItem(title: "退出 MenuNote", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        // 临时挂上菜单再模拟点击，既保留左键的 toggle 行为，又能右键弹菜单
        statusItem?.menu = menu
        statusItem?.button?.performClick(self)
        statusItem?.menu = nil
    }

    // MARK: - 菜单动作

    @objc private func menuTogglePanel() {
        panelController?.toggleFromUser()
    }

    @objc private func menuNewNote() {
        _ = store.createNote()
        appState.contentMode = .formattedEditing
        panelController?.show()
    }

    @objc private func menuOpenHotKeySettings() {
        appState.isSettingsVisible = true
        panelController?.show()
    }

    @objc private func menuTogglePin() {
        settings.isWindowPinned.toggle()
    }

    @objc private func menuToggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
    }

    @objc private func menuReveal() {
        store.revealInFinder()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    private func updateStatusTooltip() {
        statusItem?.button?.toolTip = "MenuNote 便签（\(settings.hotKey.displayString) 呼出，右键打开菜单）"
    }
}
