import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 原生快捷键录制控件。成为 first responder 后只在当前面板捕获按键，
/// 不使用全局事件监控，因此不会影响其他应用的键盘输入。
struct HotKeyRecorderView: NSViewRepresentable {
    let hotKey: HotKey
    let onRecord: (HotKey) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> HotKeyRecorderControl {
        let control = HotKeyRecorderControl()
        control.onRecord = onRecord
        control.onCancel = onCancel
        control.hotKey = hotKey
        return control
    }

    func updateNSView(_ control: HotKeyRecorderControl, context: Context) {
        control.onRecord = onRecord
        control.onCancel = onCancel
        if !control.isRecording {
            control.hotKey = hotKey
        }
    }
}

final class HotKeyRecorderControl: NSControl {
    var hotKey: HotKey = .default {
        didSet { needsDisplay = true }
    }
    var onRecord: ((HotKey) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 142, height: 28) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        isRecording = true
        window.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            onCancel?()
            window?.makeFirstResponder(nil)
            return
        }
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        let candidate = HotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        isRecording = false
        onRecord?(candidate)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor
        let border: NSColor
        let text: NSColor
        if isRecording {
            fill = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.28 : 0.14)
            border = NSColor.controlAccentColor
            text = NSColor.controlAccentColor
        } else {
            fill = isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)
            border = isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.15)
            text = NSColor.labelColor
        }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        fill.setFill()
        shape.fill()
        border.setStroke()
        shape.lineWidth = isRecording ? 1.5 : 1
        shape.stroke()

        let label = isRecording ? "请按快捷键…" : hotKey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: text,
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (label as NSString).draw(at: point, withAttributes: attributes)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}
