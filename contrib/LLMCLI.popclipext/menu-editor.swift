import AppKit
import Foundation

// Native drag-and-drop editor for the LLM CLI picker menu (menu.json).
// Usage: menu-editor <path-to-menu.json>
//        menu-editor --dump <path>   (non-GUI: print parsed items, for testing)

// MARK: - Row model

final class Row {
    var label: String
    var provider: String
    var preset: String
    var model: String
    var customPrompt: String
    var action: String
    var separator: Bool
    var enabled: Bool

    init(label: String = "", provider: String = "", preset: String = "", model: String = "",
         customPrompt: String = "", action: String = "", separator: Bool = false, enabled: Bool = true) {
        self.label = label; self.provider = provider; self.preset = preset; self.model = model
        self.customPrompt = customPrompt; self.action = action; self.separator = separator; self.enabled = enabled
    }

    var kind: String {
        if separator { return "separator" }
        if !action.isEmpty { return "action" }
        return "provider"
    }

    var displayTitle: String {
        if separator { return "————————————————" }
        let base = label.isEmpty ? (action.isEmpty ? "(isimsiz)" : action) : label
        return enabled ? base : "⊘ \(base)"
    }
}

// MARK: - Load / save

func loadRows(_ path: String) -> [Row] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let items = obj["items"] as? [[String: Any]] else {
        return defaultRows()
    }
    let rows = items.map { d -> Row in
        Row(label: d["label"] as? String ?? "",
            provider: d["provider"] as? String ?? "",
            preset: d["preset"] as? String ?? "",
            model: d["model"] as? String ?? "",
            customPrompt: d["customPrompt"] as? String ?? "",
            action: d["action"] as? String ?? "",
            separator: d["separator"] as? Bool ?? false,
            enabled: d["enabled"] as? Bool ?? true)
    }
    return rows.isEmpty ? defaultRows() : rows
}

func defaultRows() -> [Row] {
    return [
        Row(label: "Ollama - Düzelt", provider: "ollama", preset: "duzelt"),
        Row(label: "⌥ Ollama - Chat Kurumsal", provider: "ollama", preset: "chat"),
        Row(label: "⇧ Ollama - Mail Kurumsal", provider: "ollama", preset: "mail"),
        Row(label: "⌃ Ollama - Müşteri Tonu", provider: "ollama", preset: "musteri"),
        Row(separator: true),
        Row(label: "⌘ Codex - Düzelt", provider: "codex", preset: "duzelt"),
        Row(label: "⌘⌥ Codex - Chat Kurumsal", provider: "codex", preset: "chat"),
        Row(separator: true),
        Row(label: "🩺 Sağlık / Onar", action: "doctor"),
        Row(label: "Menüyü Düzenle", action: "editMenu"),
        Row(label: "Shortcut Help", action: "help")
    ]
}

func saveRows(_ rows: [Row], to path: String) throws {
    var items: [[String: Any]] = []
    for r in rows {
        var d: [String: Any] = [:]
        if r.separator {
            d["separator"] = true
        } else if !r.action.isEmpty {
            if !r.label.isEmpty { d["label"] = r.label }
            d["action"] = r.action
        } else {
            if !r.label.isEmpty { d["label"] = r.label }
            if !r.provider.isEmpty { d["provider"] = r.provider }
            if !r.preset.isEmpty { d["preset"] = r.preset }
            if !r.model.isEmpty { d["model"] = r.model }
            if !r.customPrompt.isEmpty { d["customPrompt"] = r.customPrompt }
        }
        if !r.enabled { d["enabled"] = false }
        items.append(d)
    }
    let root: [String: Any] = ["items": items]
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: URL(fileURLWithPath: path))
}

func ollamaModels() -> [String] {
    guard let url = URL(string: "http://127.0.0.1:11434/api/tags"),
          let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let models = obj["models"] as? [[String: Any]] else { return [] }
    return models.compactMap { $0["name"] as? String }.sorted()
}

// MARK: - CLI dump mode (for headless verification)

let args = CommandLine.arguments
let configPath = args.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? "\(NSHomeDirectory())/.config/popclip-llm-cli-rewrite/menu.json"

if args.contains("--dump") {
    let rows = loadRows(configPath)
    print("items: \(rows.count)")
    for r in rows { print("- [\(r.kind)] \(r.displayTitle)  provider=\(r.provider) preset=\(r.preset) model=\(r.model)") }
    print("ollama models: \(ollamaModels().joined(separator: ", "))")
    exit(0)
}

// MARK: - Editor window

final class EditorController: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate,
                              NSTextFieldDelegate, NSComboBoxDelegate, NSTextViewDelegate {
    let path: String
    var rows: [Row]
    let models: [String]

    var window: NSWindow!
    var table: NSTableView!
    // detail controls
    var kindPopup: NSPopUpButton!
    var labelField: NSTextField!
    var providerPopup: NSPopUpButton!
    var presetPopup: NSPopUpButton!
    var modelCombo: NSComboBox!
    var actionPopup: NSPopUpButton!
    var promptView: NSTextView!
    var enabledCheck: NSButton!
    var detailBox: NSBox!
    var statusLabel: NSTextField!

    let dragType = NSPasteboard.PasteboardType("com.pestly.llmcli.row")
    let providers = ["ollama", "codex", "claude", "gemini", "opencode"]
    let presets = ["duzelt", "chat", "mail", "musteri", "custom"]
    let actions = ["doctor", "editMenu", "help"]
    let actionLabels = ["Sağlık / Onar", "Menüyü Düzenle", "Yardım"]

    init(path: String) {
        self.path = path
        self.rows = loadRows(path)
        self.models = ollamaModels()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        if !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        syncDetail()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "LLM CLI — Menü Editörü"
        w.center()
        window = w

        let content = NSView(frame: w.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        // Left: table + row buttons
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 92, width: 320, height: 416))
        scroll.autoresizingMask = [.height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTableView()
        tv.headerView = nil
        tv.rowHeight = 26
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.width = 300
        tv.addTableColumn(col)
        tv.dataSource = self
        tv.delegate = self
        tv.registerForDraggedTypes([dragType])
        tv.draggingDestinationFeedbackStyle = .gap
        scroll.documentView = tv
        table = tv
        content.addSubview(scroll)

        var bx: CGFloat = 12
        func button(_ title: String, _ sel: Selector, width: CGFloat = 58) -> NSButton {
            let b = NSButton(frame: NSRect(x: bx, y: 56, width: width, height: 28))
            b.title = title; b.bezelStyle = .rounded; b.target = self; b.action = sel
            bx += width + 6
            return b
        }
        content.addSubview(button("+ Öğe", #selector(addItem), width: 66))
        content.addSubview(button("+ Çizgi", #selector(addSeparator), width: 68))
        content.addSubview(button("Kopyala", #selector(duplicateItem), width: 72))
        content.addSubview(button("Sil", #selector(removeItem), width: 46))

        let hint = NSTextField(labelWithString: "Sıralamak için satırları sürükle-bırak.")
        hint.frame = NSRect(x: 12, y: 30, width: 320, height: 18)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)

        // Right: detail box
        let box = NSBox(frame: NSRect(x: 344, y: 56, width: 404, height: 452))
        box.autoresizingMask = [.width, .height]
        box.title = "Öğe Ayrıntısı"
        detailBox = box
        content.addSubview(box)
        buildDetail(in: box)

        // Bottom: save/close + status
        let save = NSButton(frame: NSRect(x: 648, y: 12, width: 100, height: 30))
        save.title = "Kaydet"; save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        save.target = self; save.action = #selector(saveAndNotify)
        save.autoresizingMask = [.minXMargin]
        content.addSubview(save)

        let close = NSButton(frame: NSRect(x: 544, y: 12, width: 100, height: 30))
        close.title = "Kapat"; close.bezelStyle = .rounded
        close.target = self; close.action = #selector(closeWindow)
        close.autoresizingMask = [.minXMargin]
        content.addSubview(close)

        let status = NSTextField(labelWithString: models.isEmpty ? "Ollama modelleri okunamadı (sunucu kapalı olabilir)." : "\(models.count) Ollama modeli yüklendi.")
        status.frame = NSRect(x: 12, y: 16, width: 500, height: 18)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        statusLabel = status
        content.addSubview(status)

        w.contentView = content
        w.makeKeyAndOrderFront(nil)
    }

    func buildDetail(in box: NSBox) {
        // macOS HIG form: right-aligned label column + control column, one row each,
        // baseline-aligned. Hints live inside the fields as placeholders — no more
        // ambiguous labels floating between controls.
        let cv = box.contentView!
        let margin: CGFloat = 18
        let labelW: CGFloat = 78
        let gutter: CGFloat = 10
        let ctrlX = margin + labelW + gutter
        let ctrlW = cv.bounds.width - ctrlX - margin
        let rowH: CGFloat = 25
        let rowGap: CGFloat = 13
        var y = cv.bounds.height - 22

        func rowLabel(_ s: String, top: Bool = false, controlHeight h: CGFloat = 25) {
            let l = NSTextField(labelWithString: s)
            let ly = top ? (y - 16) : (y - h + (h - 14) / 2)
            l.frame = NSRect(x: margin, y: ly, width: labelW, height: 14)
            l.alignment = .right
            l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            l.textColor = .secondaryLabelColor
            cv.addSubview(l)
        }
        func ctrlRect(_ h: CGFloat = rowH) -> NSRect { NSRect(x: ctrlX, y: y - h, width: ctrlW, height: h) }
        func next(_ h: CGFloat = rowH) { y -= (h + rowGap) }

        rowLabel("Tür")
        kindPopup = NSPopUpButton(frame: ctrlRect(), pullsDown: false)
        kindPopup.addItems(withTitles: ["Sağlayıcı Öğesi", "Ayırıcı Çizgi", "Aksiyon"])
        kindPopup.target = self; kindPopup.action = #selector(kindChanged)
        cv.addSubview(kindPopup); next()

        rowLabel("Etiket")
        labelField = NSTextField(frame: ctrlRect())
        labelField.delegate = self
        labelField.placeholderString = "menüde görünen metin"
        cv.addSubview(labelField); next()

        rowLabel("Sağlayıcı")
        providerPopup = NSPopUpButton(frame: ctrlRect(), pullsDown: false)
        providerPopup.addItems(withTitles: providers)
        providerPopup.target = self; providerPopup.action = #selector(fieldEdited)
        cv.addSubview(providerPopup); next()

        rowLabel("Stil")
        presetPopup = NSPopUpButton(frame: ctrlRect(), pullsDown: false)
        presetPopup.addItems(withTitles: presets)
        presetPopup.target = self; presetPopup.action = #selector(fieldEdited)
        cv.addSubview(presetPopup); next()

        rowLabel("Model")
        modelCombo = NSComboBox(frame: ctrlRect())
        modelCombo.addItems(withObjectValues: models)
        modelCombo.completes = true
        modelCombo.placeholderString = "boş = stilin varsayılan modeli"
        modelCombo.delegate = self
        cv.addSubview(modelCombo); next()

        rowLabel("Aksiyon")
        actionPopup = NSPopUpButton(frame: ctrlRect(), pullsDown: false)
        actionPopup.addItems(withTitles: actionLabels)
        actionPopup.target = self; actionPopup.action = #selector(fieldEdited)
        cv.addSubview(actionPopup); next()

        let promptH: CGFloat = 92
        rowLabel("Prompt", top: true)
        let ps = NSScrollView(frame: NSRect(x: ctrlX, y: y - promptH, width: ctrlW, height: promptH))
        ps.borderType = .bezelBorder; ps.hasVerticalScroller = true
        let tvp = NSTextView(frame: ps.bounds)
        tvp.isRichText = false; tvp.font = .systemFont(ofSize: 12)
        tvp.textContainerInset = NSSize(width: 4, height: 6)
        tvp.delegate = self
        ps.documentView = tvp
        promptView = tvp
        cv.addSubview(ps); next(promptH)

        enabledCheck = NSButton(checkboxWithTitle: "Etkin (kapalıysa menüde gizli)", target: self, action: #selector(fieldEdited))
        enabledCheck.frame = NSRect(x: ctrlX, y: y - 18, width: ctrlW, height: 20)
        cv.addSubview(enabledCheck)
    }

    // MARK: table data

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (t.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            let tf = NSTextField(labelWithString: "")
            tf.frame = NSRect(x: 6, y: 4, width: 288, height: 18)
            tf.autoresizingMask = [.width]
            c.addSubview(tf); c.textField = tf; c.identifier = id
            return c
        }()
        cell.textField?.stringValue = rows[row].displayTitle
        cell.textField?.textColor = rows[row].separator ? .tertiaryLabelColor : .labelColor
        return cell
    }

    func tableViewSelectionDidChange(_ n: Notification) { syncDetail() }

    // MARK: drag reorder

    func tableView(_ t: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: dragType)
        return item
    }

    func tableView(_ t: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        return op == .above ? .move : []
    }

    func tableView(_ t: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
        guard let s = info.draggingPasteboard.pasteboardItems?.first?.string(forType: dragType),
              let from = Int(s) else { return false }
        var to = row
        let moved = rows.remove(at: from)
        if from < to { to -= 1 }
        rows.insert(moved, at: to)
        t.reloadData()
        t.selectRowIndexes(IndexSet(integer: to), byExtendingSelection: false)
        return true
    }

    // MARK: detail sync

    var selected: Row? { let i = table.selectedRow; return (i >= 0 && i < rows.count) ? rows[i] : nil }

    func syncDetail() {
        guard let r = selected else { detailBox.contentView?.subviews.forEach { $0.isHidden = false }; return }
        kindPopup.selectItem(at: r.separator ? 1 : (!r.action.isEmpty ? 2 : 0))
        labelField.stringValue = r.label
        if let idx = providers.firstIndex(of: r.provider) { providerPopup.selectItem(at: idx) }
        if let idx = presets.firstIndex(of: r.preset) { presetPopup.selectItem(at: idx) }
        modelCombo.stringValue = r.model
        if let idx = actions.firstIndex(of: r.action) { actionPopup.selectItem(at: idx) }
        promptView.string = r.customPrompt
        enabledCheck.state = r.enabled ? .on : .off
        applyKindVisibility()
    }

    func applyKindVisibility() {
        let k = kindPopup.indexOfSelectedItem  // 0 provider, 1 separator, 2 action
        let isProvider = k == 0, isSeparator = k == 1, isAction = k == 2
        labelField.isEnabled = !isSeparator
        providerPopup.isEnabled = isProvider
        presetPopup.isEnabled = isProvider
        modelCombo.isEnabled = isProvider
        promptView.isEditable = isProvider
        actionPopup.isEnabled = isAction
    }

    @objc func kindChanged() {
        guard let r = selected else { return }
        switch kindPopup.indexOfSelectedItem {
        case 1: r.separator = true; r.action = ""
        case 2: r.separator = false; r.action = actions[actionPopup.indexOfSelectedItem]
        default: r.separator = false; r.action = ""
            if r.provider.isEmpty { r.provider = providers[providerPopup.indexOfSelectedItem] }
            if r.preset.isEmpty { r.preset = presets[presetPopup.indexOfSelectedItem] }
        }
        applyKindVisibility()
        table.reloadData()
    }

    @objc func fieldEdited() { commitDetail() }
    func controlTextDidChange(_ n: Notification) { commitDetail() }
    func textDidChange(_ n: Notification) { commitDetail() }
    func comboBoxSelectionDidChange(_ n: Notification) {
        DispatchQueue.main.async { self.commitDetail() }
    }

    func commitDetail() {
        guard let r = selected else { return }
        r.label = labelField.stringValue
        r.provider = providers[providerPopup.indexOfSelectedItem]
        r.preset = presets[presetPopup.indexOfSelectedItem]
        r.model = modelCombo.stringValue
        r.action = kindPopup.indexOfSelectedItem == 2 ? actions[actionPopup.indexOfSelectedItem] : ""
        r.customPrompt = promptView.string
        r.enabled = enabledCheck.state == .on
        r.separator = kindPopup.indexOfSelectedItem == 1
        let sel = table.selectedRow
        table.reloadData()
        if sel >= 0 { table.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false) }
    }

    // MARK: row buttons

    @objc func addItem() { insertRow(Row(label: "Yeni Öğe", provider: "ollama", preset: "duzelt")) }
    @objc func addSeparator() { insertRow(Row(separator: true)) }
    @objc func duplicateItem() {
        guard let r = selected else { return }
        insertRow(Row(label: r.label, provider: r.provider, preset: r.preset, model: r.model,
                      customPrompt: r.customPrompt, action: r.action, separator: r.separator, enabled: r.enabled))
    }
    @objc func removeItem() {
        let i = table.selectedRow
        guard i >= 0 && i < rows.count else { return }
        rows.remove(at: i)
        table.reloadData()
        let ni = min(i, rows.count - 1)
        if ni >= 0 { table.selectRowIndexes(IndexSet(integer: ni), byExtendingSelection: false) }
        syncDetail()
    }
    func insertRow(_ r: Row) {
        let i = table.selectedRow
        let at = (i >= 0 && i < rows.count) ? i + 1 : rows.count
        rows.insert(r, at: at)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: at), byExtendingSelection: false)
        syncDetail()
    }

    // MARK: save / close

    @objc func saveAndNotify() {
        commitDetail()
        do {
            try saveRows(rows, to: path)
            statusLabel.stringValue = "Kaydedildi ✓  (\(rows.count) öğe) — menü anında güncel."
            statusLabel.textColor = .systemGreen
        } catch {
            statusLabel.stringValue = "Kaydedilemedi: \(error.localizedDescription)"
            statusLabel.textColor = .systemRed
        }
    }
    @objc func closeWindow() { window.close() }
}

// ensure menu.json dir/file exists so the editor always has a target
let dir = (configPath as NSString).deletingLastPathComponent
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
if !FileManager.default.fileExists(atPath: configPath) {
    try? saveRows(defaultRows(), to: configPath)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = EditorController(path: configPath)
app.delegate = controller
app.run()
