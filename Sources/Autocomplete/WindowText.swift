import AppKit
import ApplicationServices

struct WindowText {
    let sources: [SourceText]
    var lines: [String] { sources.map(\.text) }
    let frame: CGRect?
    let title: String?

    static func read(pid: pid_t, focusedValue: String?) -> WindowText {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.02)
            return TextTarget.attribute(element, name)
        }
        let root = AXUIElementCreateApplication(pid)
        var sources: [SourceText] = []
        guard let raw = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return WindowText(sources: sources, frame: nil, title: nil)
        }
        let window = raw as! AXUIElement
        var frame: CGRect?
        if let p = attribute(window, kAXPositionAttribute), let s = attribute(window, kAXSizeAttribute),
           CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() {
            var position = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(p as! AXValue, .cgPoint, &position), AXValueGetValue(s as! AXValue, .cgSize, &size) {
                frame = CGRect(origin: position, size: size)
            }
        }
        let title = attribute(window, kAXTitleAttribute) as? String
        var queue = [window]
        var index = 0
        var seen = Set<AXUIElement>()
        // Bound both IPC time and tree size so slow/huge accessibility trees fall back to OCR.
        while index < queue.count && index < 200 && ProcessInfo.processInfo.systemUptime < deadline {
            let element = queue[index]
            index += 1
            guard seen.insert(element).inserted else { continue }
            guard attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { continue }
            for name in [kAXValueAttribute, kAXTitleAttribute] {
                if let text = attribute(element, name) as? String, !text.isEmpty { sources.append(SourceText(text: text, element: name == kAXValueAttribute ? element : nil)) }
            }
            if let children = attribute(element, kAXVisibleChildrenAttribute) as? [AXUIElement]
                ?? attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 200 - queue.count)))
            }
        }
        return WindowText(sources: sources, frame: frame, title: title)
    }
}
