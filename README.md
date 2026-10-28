# Quaero - autocomplete for the whole of macOS

A small native menu-bar utility. Press **⌘ Esc** while typing to complete a word using text visible anywhere on your connected displays. Runs locally using ScreenCaptureKit and Apple Vision; no server, API key, screenshot files, or clipboard changes.

## Build and run

Requires macOS 14 or newer and the Xcode command-line tools (Swift 5.9+).

```sh
./scripts/build-app.sh
open dist/Autocomplete.app
```

Keep the app in a stable location (you can move it to Applications before first launch). Allow **Accessibility** and **Screen & System Audio Recording** in System Settings → Privacy & Security, then relaunch. The menu-bar item has **Permission Status…**, which reports access for the running build, shows its exact path, and links to Settings. Screen Recording is requested only when OCR is needed. Rebuilding an ad-hoc signed app can require granting permissions again.

## Usage

1. Put the cursor in a text field and type a prefix, such as `app`.
2. Press **⌘ Esc**. The app searches nearby text first and expands only when no matches are found.
3. One matching word: its missing suffix is inserted automatically.
4. Several matches: use **↑ / ↓** and **Return**, or double-click a row. Type in the search field to filter; **⌘A** selects all search text. **Esc** cancels.

Search order:

1. Text already available from the focused editor, then accessible text in its active window.
2. OCR of the active window.
3. OCR of the display containing the largest part of that window.
4. OCR of the remaining displays.

The first scope with matching words wins: later scopes are never captured or recognized. One match in that scope inserts automatically even if wider scopes might contain other matches. Accessible editor text requires no screenshot or OCR. The active-window accessibility traversal runs off the main thread with a 150 ms budget (plus at most one 20 ms in-flight request) and a 200-element limit. If the active window cannot be identified, window OCR is skipped; the pointer's display is the fallback active display. Capture discovery is shared between OCR stages. Screenshots use their native backing scale.

Matching ignores case, deduplicates words within the chosen scope, excludes already-complete words, splits paths at forward/backslashes, and removes Unicode punctuation throughout each token. Thus `Text` matches `Sources/Autocomplete/TextTarget.swift`, producing `TextTargetswift` under the punctuation-free output rule. Punctuation is also ignored in the typed prefix and picker filter. For example, `co-operate` is offered as `cooperate`. Already-typed text is left intact; only the missing punctuation-free suffix is inserted. Your typed casing is preserved. Results are ordered shortest first, then alphabetically. Each suggestion is a whitespace-delimited token; this version does not generate text or suggest whole sentences.

The app checks that the original app, focused element, text, and selection have not changed before inserting. Moving the cursor or typing while recognition runs cancels the result when the target app exposes these accessibility attributes. Password fields exposed as secure accessibility fields are excluded. Dismissing the no-results dialog restores the original app/window and focused field; the saved caret is restored if the field text is unchanged and the app supports setting its accessibility selection.

## Compatibility

Some editors, terminals, and custom text controls do not expose their text or caret through Accessibility. In that case, the list contains all words in the first nonempty scope and selection inserts the entire word at the current cursor. Automatic insertion still applies if there is only one result. Cursor-change detection is limited by the accessibility data an app provides. Unicode keyboard events work with standard macOS text controls, but some apps may ignore them. OCR can misread very small or stylized text. Accessibility may expose editor text outside the visible viewport; window OCR captures the window itself, while display OCR captures what is visible on that display.

The picker does not activate a different app. If you switch apps before choosing, insertion is canceled. A conflicting global shortcut is reported at startup.

## Development

```sh
swift test
```

`CompletionCore` contains prefix matching and lazy staged search logic. `Autocomplete` contains the native menu-bar app, global shortcut, capture/OCR, accessibility target tracking, picker, and Unicode insertion.

Screen capture follows Apple's [ScreenCaptureKit APIs](https://developer.apple.com/documentation/screencapturekit/sccontentfilter).

## Permissions after rebuilding

Ad-hoc signing ties the app identity to a binary hash. An enabled Settings switch can refer to an older build. Quit Autocomplete, remove the stale entry in the affected Privacy & Security panel, add the exact app shown in Permission Status, and relaunch. Keep only one installed copy to avoid confusion.

To preserve a certificate-based identity across builds, supply a valid code-signing certificate already installed in your keychain:

```sh
AUTOCOMPLETE_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

Switching signing identity can itself require a one-time permission re-grant. The default remains ad-hoc signing when no identity is supplied. The app does not request Input Monitoring, Full Disk Access, microphone, or camera access, and does not capture audio.

## Source highlights

A unique match highlights its source and fades over 0.5 seconds while the completion is inserted. In the picker, the selected word's source stays highlighted as you navigate with arrows or the mouse; accepting or canceling clears it. The overlay does not intercept typing or clicks.

OCR matches retain word-level screen bounds. Accessibility matches use text-range bounds; if an app cannot supply them, one cached window OCR pass locates the source. This fallback may add latency and requires Screen Recording. If neither method yields a location (for example, off-screen editor text), the completion remains available without a highlight. Locations reflect the captured layout, so moving or scrolling the source while the picker is open can make the highlight stale.
