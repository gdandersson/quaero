import AppKit
import ApplicationServices
import CompletionCore

struct SourceText {
    let text: String
    var element: AXUIElement? = nil
    var rectangle: CGRect? = nil // Global top-left coordinates, in points.

    func bounds(for word: String) -> CGRect? {
        for range in Matcher.tokenRanges(in: text) where Matcher.ignoringPunctuation(String(text[range])).lowercased() == word.lowercased() {
            if let rectangle { return rectangle }
            guard let element else { continue }
            AXUIElementSetMessagingTimeout(element, 0.02)
            let nsRange = NSRange(range, in: text)
            var axRange = CFRange(location: nsRange.location, length: nsRange.length)
            guard let parameter = AXValueCreate(.cfRange, &axRange) else { continue }
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
               let result, CFGetTypeID(result) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 { return rect }
            }
        }
        return nil
    }
}

@MainActor final class CompletionResult {
    let words: [String]
    let sources: [SourceText]
    private let fallback: () async throws -> [SourceText]
    private var fallbackTask: Task<[SourceText], Error>?

    init(words: [String], sources: [SourceText], fallback: @escaping () async throws -> [SourceText]) {
        self.words = words
        self.sources = sources
        self.fallback = fallback
    }

    func bounds(for word: String) async -> CGRect? {
        let sources = sources
        let found = await Task.detached(priority: .userInitiated) {
            sources.lazy.compactMap { $0.bounds(for: word) }.first
        }.value
        if let found { return found }
        // Some custom editors expose text but no text-range geometry. Locate the word
        // with one lazy window OCR pass, shared by subsequent arrow-key selections.
        if fallbackTask == nil { fallbackTask = Task { try await fallback() } }
        let recognized = (try? await fallbackTask?.value) ?? []
        return recognized.lazy.compactMap { $0.bounds(for: word) }.first
    }
}

final class SourceHighlight {
    private var panel: NSPanel?
    private var request: Task<Void, Never>?
    private var generation = 0

    @discardableResult func show(_ word: String, in result: CompletionResult, fading: Bool) -> Task<Void, Never> {
        clear()
        let generation = generation
        request = Task { @MainActor [weak self] in
            guard let rect = await result.bounds(for: word), !Task.isCancelled,
                  let self, self.generation == generation else { return }
            let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
            let frame = CGRect(x: rect.minX - 3, y: mainTop - rect.maxY - 3, width: rect.width + 6, height: rect.height + 6)
            guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return }
            let overlay = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.hasShadow = false
            overlay.ignoresMouseEvents = true
            overlay.level = .statusBar
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            overlay.hidesOnDeactivate = false
            let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.3).cgColor
            view.layer?.borderColor = NSColor.systemOrange.cgColor
            view.layer?.borderWidth = 2
            view.layer?.cornerRadius = 4
            overlay.contentView = view
            self.panel = overlay
            overlay.orderFrontRegardless()
            if fading {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    overlay.animator().alphaValue = 0
                } completionHandler: {
                    overlay.orderOut(nil)
                }
            }
        }
        return request!
    }

    func clear() {
        generation += 1
        request?.cancel()
        request = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
