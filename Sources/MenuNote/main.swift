import AppKit

// 入口：菜单栏应用（无 Dock 图标）
// .app 包内通过 Info.plist 的 LSUIElement=true 同样生效，这里再兜底一次，
// 使得 `swift run` 直接跑二进制时也不占用 Dock。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
