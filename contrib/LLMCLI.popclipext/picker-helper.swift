import AppKit
import Foundation

struct MenuConfig: Decodable {
    let items: [MenuItem]
}

struct MenuItem: Codable {
    let label: String?
    let provider: String?
    let preset: String?
    let model: String?
    let customPrompt: String?
    let action: String?
    let enabled: Bool?
    let separator: Bool?

    var isEnabledItem: Bool {
        if separator == true { return true }
        if enabled == false { return false }
        return label?.isEmpty == false
    }
}

let fallbackItems = [
    MenuItem(label: "Ollama - Düzelt", provider: "ollama", preset: "duzelt", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: "⌥ Ollama - Chat Kurumsal", provider: "ollama", preset: "chat", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: "⇧ Ollama - Mail Kurumsal", provider: "ollama", preset: "mail", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: "⌃ Ollama - Müşteri Tonu", provider: "ollama", preset: "musteri", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: nil, provider: nil, preset: nil, model: nil, customPrompt: nil, action: nil, enabled: nil, separator: true),
    MenuItem(label: "⌘ Codex - Düzelt", provider: "codex", preset: "duzelt", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: "⌘⌥ Codex - Chat Kurumsal", provider: "codex", preset: "chat", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: "⌘⇧ Codex - Mail Kurumsal", provider: "codex", preset: "mail", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: "Codex - Müşteri Tonu", provider: "codex", preset: "musteri", model: nil, customPrompt: nil, action: nil, enabled: nil, separator: nil),
    MenuItem(label: nil, provider: nil, preset: nil, model: nil, customPrompt: nil, action: nil, enabled: nil, separator: true),
    MenuItem(label: "Menüyü Düzenle", provider: nil, preset: nil, model: nil, customPrompt: nil, action: "editMenu", enabled: nil, separator: nil),
    MenuItem(label: "Shortcut Help", provider: nil, preset: nil, model: nil, customPrompt: nil, action: "help", enabled: nil, separator: nil)
]

func loadItems(from path: String?) -> [MenuItem] {
    guard let path, !path.isEmpty else {
        return fallbackItems
    }

    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let config = try JSONDecoder().decode(MenuConfig.self, from: data)
        let items = config.items.filter(\.isEnabledItem)
        return items.isEmpty ? fallbackItems : items
    } catch {
        return fallbackItems
    }
}

let configPath = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") })
let menuItems = loadItems(from: configPath)
let firstChoice = menuItems.first(where: { $0.separator != true && $0.label?.isEmpty == false })?.label ?? "Ollama - Düzelt"

if CommandLine.arguments.contains("--self-test") {
    print(firstChoice)
    exit(0)
}

if CommandLine.arguments.contains("--dump-labels") {
    for item in menuItems where item.separator != true {
        if let label = item.label, !label.isEmpty {
            print(label)
        }
    }
    exit(0)
}

final class PickerController: NSObject {
    private let items: [MenuItem]
    private var selectedChoice: String?
    private var anchorWindow: NSWindow?

    init(items: [MenuItem]) {
        self.items = items
    }

    func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()

        let menu = makeMenu()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // PopClip shows its own progress spinner at the clicked action while
        // this helper is waiting. Offset the menu slightly so the spinner
        // stays beside the menu instead of covering the first item.
        let preferredAnchor = NSPoint(x: mouse.x + 44, y: mouse.y - 8)
        let anchorPoint = NSPoint(
            x: min(max(preferredAnchor.x, visible.minX + 6), visible.maxX - 6),
            y: min(max(preferredAnchor.y, visible.minY + 6), visible.maxY - 6)
        )

        let window = NSWindow(
            contentRect: NSRect(x: anchorPoint.x, y: anchorPoint.y, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        anchorWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        _ = menu.popUp(positioning: nil, at: .zero, in: window.contentView)
        window.close()

        guard let selectedChoice else {
            return 1
        }

        print(selectedChoice)
        fflush(stdout)
        return 0
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "LLM CLI")
        menu.autoenablesItems = false
        menu.minimumWidth = 285

        for itemConfig in items {
            if itemConfig.separator == true {
                menu.addItem(.separator())
                continue
            }

            guard let title = itemConfig.label, !title.isEmpty else {
                continue
            }

            guard let payload = try? String(data: JSONEncoder().encode(itemConfig), encoding: .utf8) else {
                continue
            }

            let item = NSMenuItem(title: title, action: #selector(selectChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = payload
            item.isEnabled = true
            menu.addItem(item)
        }

        return menu
    }

    @objc private func selectChoice(_ sender: NSMenuItem) {
        selectedChoice = sender.representedObject as? String
    }
}

let controller = PickerController(items: menuItems)
exit(controller.run())
