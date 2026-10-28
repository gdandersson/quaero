import AppKit
import CompletionCore

final class CompletionSearchField: NSSearchField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "a",
           let editor = currentEditor() {
            editor.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class CompletionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class Picker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let panel = CompletionPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340), styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
    private let search = CompletionSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let font = NSFont.systemFont(ofSize: 15)
    private var all: [String] = []
    private var filtered: [String] = []
    private var monitor: Any?
    private var selection: ((String?) -> Void)?
    private var highlight: ((String?) -> Void)?

    override init() {
        super.init()
        panel.title = "Autocomplete · ↑ ↓ select · Return insert · Esc cancel"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = panel.contentView!
        search.frame = NSRect(x: 16, y: 278, width: 428, height: 30)
        search.autoresizingMask = [.width]
        search.placeholderString = "Filter visible words…"
        search.delegate = self
        content.addSubview(search)
        scroll.frame = NSRect(x: 16, y: 14, width: 428, height: 254)
        scroll.autoresizingMask = [.width]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion")))
        table.headerView = nil
        table.rowHeight = 30
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(accept)
        scroll.documentView = table
        content.addSubview(scroll)
    }

    func show(_ candidates: [String], highlight: @escaping (String?) -> Void, selection: @escaping (String?) -> Void) {
        self.selection = selection
        self.highlight = highlight
        all = candidates
        filtered = candidates
        search.stringValue = ""
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let textWidth = candidates.map { (Self.preview($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let columnWidth = ceil(textWidth) + 24
        let width = min(max(460, columnWidth + 56), screen.visibleFrame.width - 32)
        panel.setContentSize(NSSize(width: width, height: 340))
        // Explicitly size the column: NSTableColumn's default width clips even short words.
        let actualColumnWidth = max(columnWidth, scroll.contentSize.width - 4)
        table.tableColumns[0].width = actualColumnWidth
        table.setFrameSize(NSSize(width: actualColumnWidth + 4, height: table.frame.height))
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.modifierFlags.contains(.command), self.search.performKeyEquivalent(with: event) { return nil }
            switch event.keyCode {
            case 53: self.close(nil); return nil
            case 36, 76: self.accept(); return nil
            case 125, 126:
                guard !self.filtered.isEmpty else { return nil }
                let offset = event.keyCode == 125 ? 1 : -1
                let row = max(0, min(self.filtered.count - 1, self.table.selectedRow + offset))
                self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.table.scrollRowToVisible(row)
                return nil
            default: return event
            }
        }
    }

    func close(_ value: String?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        highlight?(nil)
        highlight = nil
        let callback = selection
        selection = nil
        callback?(value)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close(nil)
        return false // Reuse the panel; cancellation follows exactly the Escape path.
    }

    private static func preview(_ text: String) -> String {
        guard text.count >= 50 else { return text }
        return String(text.prefix(24)) + "…" + String(text.suffix(24))
    }

    @objc private func accept() {
        guard filtered.indices.contains(table.selectedRow) else { return }
        close(filtered[table.selectedRow])
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = Matcher.ignoringPunctuation(search.stringValue)
        filtered = all.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        highlight?(filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow] : nil)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        highlight?(filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow] : nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: Self.preview(filtered[row]))
        label.font = font
        label.lineBreakMode = .byClipping
        label.toolTip = filtered[row]
        return label
    }
}
