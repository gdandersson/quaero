import AppKit
import ApplicationServices
import CompletionCore

struct TextTarget {
    let app: NSRunningApplication
    let element: AXUIElement?
    let value: String?
    let range: CFRange?
    let prefix: String
    var window: AXUIElement? = nil

    var currentWord: String? {
        guard let value else { return prefix.isEmpty ? nil : prefix }
        return Matcher.wordAtCursor(in: value, selection: range.map { NSRange(location: $0.location, length: $0.length) })
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    static func capture() -> TextTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.05)
        let rawWindow = attribute(root, kAXFocusedWindowAttribute)
        let window: AXUIElement? = rawWindow.flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        }
        guard let focused = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return TextTarget(app: app, element: nil, value: nil, range: nil, prefix: "", window: window)
        }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.05)
        if attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return nil }
        let value = attribute(element, kAXValueAttribute) as? String
        var range: CFRange?
        if let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
            var selection = CFRange()
            if AXValueGetValue(raw as! AXValue, .cfRange, &selection) { range = selection }
        }
        var prefix = ""
        if let value, let range, range.length == 0, range.location >= 0, range.location <= (value as NSString).length {
            prefix = Matcher.prefix(before: (value as NSString).substring(to: range.location))
        }
        return TextTarget(app: app, element: element, value: value, range: range, prefix: prefix, window: window)
    }

    @MainActor func restoreFocus() async {
        guard !app.isTerminated else { return }
        if let window {
            AXUIElementSetMessagingTimeout(window, 0.05)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        app.activate(options: [])
        for _ in 0..<10 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let element else { return }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        // Restore the caret only if the field still contains the captured text.
        if let value, Self.attribute(element, kAXValueAttribute) as? String == value,
           var range, let selection = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection)
        }
    }

    func isUnchanged() -> Bool {
        guard let current = Self.capture(), current.app.processIdentifier == app.processIdentifier else { return false }
        if let element {
            guard let other = current.element, CFEqual(element, other), value == current.value else { return false }
            if let range {
                guard let other = current.range, range.location == other.location, range.length == other.length else { return false }
            }
        }
        return true
    }

    func insert(_ text: String) async -> Bool {
        // Wait for Cmd/Escape (or Return) to be released before emitting text.
        for _ in 0..<100 {
            if CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
              isUnchanged() else { return false }
        let source = CGEventSource(stateID: .privateState)
        // Unicode events leave the user's clipboard intact.
        for character in text {
            let units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
            down.flags = []
            up.flags = []
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress!)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress!)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }
}
