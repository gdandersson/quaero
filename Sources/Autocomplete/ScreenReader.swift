import AppKit
import ScreenCaptureKit
import Vision
import CompletionCore

struct ScreenReader {
    @MainActor static func candidates(for target: TextTarget) async throws -> CompletionResult {
        let pid = target.app.processIdentifier
        let value = target.value
        let focusedSources = value.map { [SourceText(text: $0, element: target.element)] } ?? []
        let surrounding = Matcher.candidates(lines: focusedSources.map(\.text), prefix: target.prefix, excluding: target.currentWord)
        if !surrounding.isEmpty {
            return CompletionResult(words: surrounding, sources: focusedSources) {
                let nearby = await Task.detached { WindowText.read(pid: pid, focusedValue: value) }.value
                return try await CaptureSession(pid: pid, nearby: nearby).windowText()
            }
        }
        let nearby = await Task.detached(priority: .userInitiated) {
            WindowText.read(pid: pid, focusedValue: value)
        }.value
        let capture = CaptureSession(pid: pid, nearby: nearby)
        var sources = focusedSources + nearby.sources
        let words = try await StagedSearch.candidates(prefix: target.prefix, excluding: target.currentWord, stages: [
            { sources.map(\.text) },
            { sources = try await capture.windowText(); return sources.map(\.text) },
            { sources = try await capture.activeDisplayText(); return sources.map(\.text) },
            { sources = try await capture.otherDisplaysText(); return sources.map(\.text) }
        ])
        return CompletionResult(words: words, sources: sources) { try await capture.windowText() }
    }
}

/// One invocation shares discovery between OCR stages, but never starts discovery on an AX hit.
private final class CaptureSession {
    let pid: pid_t
    let nearby: WindowText
    private var content: SCShareableContent?
    private var window: SCWindow?
    private var activeDisplay: SCDisplay?

    init(pid: pid_t, nearby: WindowText) {
        self.pid = pid
        self.nearby = nearby
    }

    private func discover() async throws -> SCShareableContent {
        if let content { return content }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
        if let frame = nearby.frame {
            // AX and ScreenCaptureKit both use global top-left screen coordinates.
            window = windows.filter {
                abs($0.frame.minX - frame.minX) < 3 && abs($0.frame.minY - frame.minY) < 3 &&
                abs($0.frame.width - frame.width) < 3 && abs($0.frame.height - frame.height) < 3
            }.first(where: { $0.title == nearby.title }) ?? windows.first(where: {
                abs($0.frame.minX - frame.minX) < 3 && abs($0.frame.minY - frame.minY) < 3 &&
                abs($0.frame.width - frame.width) < 3 && abs($0.frame.height - frame.height) < 3
            })
        } else if let title = nearby.title, !title.isEmpty {
            window = windows.first(where: { $0.title == title })
        }
        if window == nil && nearby.frame == nil {
            // CGWindowList is front-to-back; do not assume SCShareableContent has that order.
            let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            for item in ordered where item[kCGWindowOwnerPID as String] as? Int == Int(pid) {
                if let id = item[kCGWindowNumber as String] as? UInt32,
                   let match = windows.first(where: { $0.windowID == id }) {
                    window = match
                    break
                }
            }
        }
        if let frame = nearby.frame ?? window?.frame {
            activeDisplay = content.displays.max {
                Self.overlap($0.frame, frame) < Self.overlap($1.frame, frame)
            }
        }
        if activeDisplay == nil {
            let pointer = CGEvent(source: nil)?.location ?? .zero
            activeDisplay = content.displays.first(where: { $0.frame.contains(pointer) })
                ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first
        }
        self.content = content
        return content
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    func windowText() async throws -> [SourceText] {
        _ = try await discover()
        guard let window else { return [] }
        return try await recognize(SCContentFilter(desktopIndependentWindow: window), frame: window.frame)
    }

    func activeDisplayText() async throws -> [SourceText] {
        let content = try await discover()
        guard let activeDisplay else { return [] }
        return try await recognize(displayFilter(activeDisplay, content: content), frame: activeDisplay.frame)
    }

    func otherDisplaysText() async throws -> [SourceText] {
        let content = try await discover()
        var lines: [SourceText] = []
        var firstError: Error?
        for display in content.displays where display.displayID != activeDisplay?.displayID {
            do { lines += try await recognize(displayFilter(display, content: content), frame: display.frame) }
            catch { if firstError == nil { firstError = error } }
        }
        if lines.isEmpty, let firstError { throw firstError }
        return lines
    }

    private func displayFilter(_ display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        return SCContentFilter(display: display, excludingWindows: ownWindows)
    }

    private func recognize(_ filter: SCContentFilter, frame: CGRect) async throws -> [SourceText] {
        try Task.checkCancellation()
        let config = SCStreamConfiguration()
        // Use actual backing scale rather than unconditionally doubling display dimensions.
        config.width = max(1, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        config.height = max(1, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).flatMap { observation -> [SourceText] in
                guard let recognized = observation.topCandidates(1).first else { return [] }
                return Matcher.tokenRanges(in: recognized.string).compactMap { range in
                    guard let box = try? recognized.boundingBox(for: range)?.boundingBox else {
                        return SourceText(text: String(recognized.string[range]))
                    }
                    let rect = SourceGeometry.screenRect(normalized: box, captureFrame: frame)
                    return SourceText(text: String(recognized.string[range]), rectangle: rect)
                }
            }
        }.value
    }
}
