import AppKit

let choices = [
    "Ollama - Düzelt",
    "⌥ Ollama - Chat Kurumsal",
    "⇧ Ollama - Mail Kurumsal",
    "⌃ Ollama - Müşteri Tonu",
    "⌘ Codex - Düzelt",
    "⌘⌥ Codex - Chat Kurumsal",
    "⌘⇧ Codex - Mail Kurumsal",
    "Codex - Müşteri Tonu",
    "OpenCode - Düzelt",
    "OpenCode - Chat Kurumsal",
    "Claude - Düzelt",
    "Gemini - Düzelt",
    "Shortcut Help"
]

if CommandLine.arguments.contains("--self-test") {
    print(choices[0])
    exit(0)
}

final class PickerController: NSObject {
    private var panel: NSPanel!

    func run() {
        NSApplication.shared.setActivationPolicy(.accessory)

        let width: CGFloat = 310
        let rowHeight: CGFloat = 30
        let padding: CGFloat = 8
        let height = CGFloat(choices.count) * rowHeight + padding * 2

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = mouse.x - 22
        var y = mouse.y - height - 12
        if y < visible.minY + 8 {
            y = mouse.y + 12
        }
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - height - 8)

        panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let stack = NSStackView(frame: NSRect(x: padding, y: padding, width: width - padding * 2, height: height - padding * 2))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fillEqually
        stack.spacing = 0

        for (index, title) in choices.enumerated() {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: width - padding * 2, height: rowHeight))
            button.title = title
            button.tag = index
            button.target = self
            button.action = #selector(selectChoice(_:))
            button.isBordered = false
            button.alignment = .left
            button.font = .systemFont(ofSize: 14, weight: .regular)
            button.contentTintColor = .labelColor
            button.setButtonType(.momentaryPushIn)
            stack.addArrangedSubview(button)
        }

        effect.addSubview(stack)
        panel.contentView = effect

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        NSApp.run()
    }

    @objc private func selectChoice(_ sender: NSButton) {
        print(choices[sender.tag])
        fflush(stdout)
        NSApp.terminate(nil)
    }
}

let controller = PickerController()
controller.run()
