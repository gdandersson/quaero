import AppKit
import Carbon
import ApplicationServices
import CompletionCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let picker = Picker()
    private let highlight = SourceHighlight()
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "↹"
        status.button?.toolTip = "Autocomplete · ⌘ Esc"
        let menu = NSMenu()
        let title = NSMenuItem(title: "Autocomplete · ⌘ Esc", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Permission Status…", action: #selector(setup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Autocomplete", action: #selector(quit), keyEquivalent: "q").target = self
        status.menu = menu
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { delegate.activate() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let registered = RegisterEventHotKey(UInt32(kVK_Escape), UInt32(cmdKey), EventHotKeyID(signature: 0x4155544F, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if installed != noErr || registered != noErr {
            message("Could not register ⌘ Esc", "Another app may already use this shortcut. Quit that app or change its shortcut, then relaunch Autocomplete.")
        }
        // ScreenCaptureKit requests capture permission only if the OCR fallback is needed.
        // Do not treat a legacy screen-capture preflight result as a startup failure.
        if !AXIsProcessTrusted() { requestAccessibility() }
    }

    @objc private func setup() {
        let accessibility = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "Autocomplete Permission Status"
        alert.informativeText = "Accessibility: \(accessibility ? "allowed" : "not granted to this running build")\nScreen Recording preflight: \(screen ? "allowed" : "not confirmed; actual capture is checked when OCR runs")\n\nRunning app: \(Bundle.main.bundleURL.path)\n\nThese are the only permissions used. No microphone or system audio is captured.\n\nIf Settings shows an enabled switch but this build is not trusted, quit Autocomplete, remove its old entry with the minus button, then add this exact app with the plus button and relaunch. Local ad-hoc builds can lose permission after rebuilding."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Accessibility Settings")
        alert.addButton(withTitle: "Screen Recording Settings")
        alert.addButton(withTitle: "Reveal Running App")
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 3):
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default: break
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !AXIsProcessTrusted() { setup() }
    }

    private func activate() {
        if busy { picker.close(nil); return }
        guard AXIsProcessTrusted() else { requestAccessibility(); return }
        guard let target = TextTarget.capture() else {
            message("Choose a text field", "Place the cursor in a normal text field in another app, then press ⌘ Esc. Password fields are excluded.")
            return
        }
        highlight.clear()
        busy = true
        status.button?.title = "…"
        Task { @MainActor [self] in
            do {
                let result = try await ScreenReader.candidates(for: target)
                let candidates = result.words
                guard target.isUnchanged() else { finish(); return }
                if candidates.isEmpty {
                    message("No completions found", target.prefix.isEmpty ? "No readable words were found on your displays." : "No visible words extend “\(target.prefix)”.")
                    await target.restoreFocus()
                    finish()
                } else if candidates.count == 1 {
                    await highlight.show(candidates[0], in: result, fading: true).value
                    await insert(candidates[0], into: target)
                } else {
                    status.button?.title = "↹"
                    picker.show(candidates, highlight: { [weak self] word in
                        guard let self else { return }
                        if let word { self.highlight.show(word, in: result, fading: false) }
                        else { self.highlight.clear() }
                    }) { [weak self] choice in
                        guard let self else { return }
                        guard let choice else { self.finish(); return }
                        Task { @MainActor in await self.insert(choice, into: target, returningFromPicker: true) }
                    }
                }
            } catch {
                finish()
                let detail = error as NSError
                message("Could not read the screen", "\(error.localizedDescription)\n\nError: \(detail.domain) (\(detail.code))\nRunning app: \(Bundle.main.bundleURL.path)\n\nUse Permission Status in the menu bar to check this build's access. Screen Recording is needed only for OCR; accessible-text matching does not require it.")
            }
        }
    }

    @MainActor private func insert(_ candidate: String, into target: TextTarget, returningFromPicker: Bool = false) async {
        // Closing a nonactivating panel returns keyboard focus to the original app.
        if returningFromPicker { try? await Task.sleep(nanoseconds: 30_000_000) }
        let inserted = await target.insert(Matcher.suffix(of: candidate, after: target.prefix))
        finish()
        if !inserted { NSSound.beep() }
    }

    private func finish() {
        busy = false
        status.button?.title = "↹"
    }

    private func message(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
        alert.window.orderOut(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
