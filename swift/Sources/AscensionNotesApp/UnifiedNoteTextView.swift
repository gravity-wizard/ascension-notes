#if os(macOS)
import AppKit
import SwiftUI

/// Unified macOS NSTextView editor:
/// - Line 1 automatically styled as large bold Title; Cmd+A selects Title + Body together.
/// - Safe against Spacebar autocomplete crashes (never mutates textStorage during marked text).
/// - Respects Auto-Cap OFF completely (disables macOS automatic text completion & autocorrect).
/// - Bottom overscroll padding lets you scroll text up the screen without adding blank lines.
/// - Right-click context menu offers Format & Folding options + Cmd+/Cmd- shrink/expand.
struct UnifiedNoteTextView: NSViewRepresentable {
    @Bindable var store: NotesStore
    let noteID: UUID
    let text: String
    let fontSize: Double
    let autoCapitalizeNewLines: Bool
    let foldedBlocks: [String: String]

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 360, right: 0)

        let textView = AscensionNSTextView()
        textView.coordinator = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.usesFindBar = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 24, height: 10)
        textView.textContainer?.widthTracksTextView = true

        // Keep red-underline continuous spellcheck ON, while controlling auto-cap/autocorrect cleanly
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        applyAutoCapBehavior(to: textView, enabled: autoCapitalizeNewLines)

        textView.string = text
        applyTypography(to: textView, fontSize: fontSize)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastNoteID = noteID
        context.coordinator.lastSyncedText = text
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastAutoCap = autoCapitalizeNewLines
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AscensionNSTextView else { return }
        context.coordinator.store = store

        // Keep generous overscroll so user can always scroll text up without blank lines
        let desiredBottom = CGFloat(max(280.0, Double(scrollView.bounds.height) * 0.65))
        if abs(scrollView.contentInsets.bottom - desiredBottom) > 8 {
            scrollView.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: desiredBottom, right: 0)
        }

        if context.coordinator.lastAutoCap != autoCapitalizeNewLines {
            applyAutoCapBehavior(to: textView, enabled: autoCapitalizeNewLines)
            context.coordinator.lastAutoCap = autoCapitalizeNewLines
        }

        let switchedNote = context.coordinator.lastNoteID != noteID
        let externalTextChanged = text != context.coordinator.lastSyncedText && text != textView.string
        let fontChanged = abs(context.coordinator.lastFontSize - fontSize) > 0.1

        // Never overwrite NSTextView while inline autocomplete/marked text is active
        if (switchedNote || externalTextChanged) && !textView.hasMarkedText() {
            let previousSelection = textView.selectedRange()
            textView.string = text
            context.coordinator.lastNoteID = noteID
            context.coordinator.lastSyncedText = text
            applyTypography(to: textView, fontSize: fontSize)
            context.coordinator.lastFontSize = fontSize

            if !switchedNote {
                let clampedLoc = min(previousSelection.location, (text as NSString).length)
                textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
            }
        } else if fontChanged && !textView.hasMarkedText() {
            applyTypography(to: textView, fontSize: fontSize)
            context.coordinator.lastFontSize = fontSize
        }
    }

    private func applyAutoCapBehavior(to textView: NSTextView, enabled: Bool) {
        textView.isAutomaticSpellingCorrectionEnabled = enabled
        textView.isAutomaticTextCompletionEnabled = enabled
        textView.isAutomaticTextReplacementEnabled = enabled
    }

    private func applyTypography(to textView: NSTextView, fontSize: Double) {
        guard let storage = textView.textStorage else { return }
        let fullStr = storage.string as NSString
        let totalLen = fullStr.length
        guard totalLen > 0 else {
            textView.font = NSFont.systemFont(ofSize: fontSize)
            return
        }

        let bodyFont = NSFont.systemFont(ofSize: fontSize)
        let titleFont = NSFont.systemFont(ofSize: fontSize + 7.0, weight: .bold)
        let foldFont = NSFont.monospacedSystemFont(ofSize: max(11.0, fontSize - 1.5), weight: .semibold)
        let bodyColor = NSColor.labelColor
        let foldBg = NSColor.systemYellow.withAlphaComponent(0.22)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4

        let selectedRanges = textView.selectedRanges
        storage.beginEditing()
        storage.addAttributes(
            [.font: bodyFont, .foregroundColor: bodyColor, .paragraphStyle: paragraph],
            range: NSRange(location: 0, length: totalLen)
        )

        // Line 1 = Bold large Apple Notes Title
        let firstLineRange = fullStr.lineRange(for: NSRange(location: 0, length: 0))
        if firstLineRange.length > 0 {
            storage.addAttribute(.font, value: titleFont, range: firstLineRange)
        }

        // Highlight folded block markers cleanly
        for marker in foldedBlocks.keys {
            var searchStart = 0
            while searchStart < totalLen {
                let found = fullStr.range(
                    of: marker,
                    options: [],
                    range: NSRange(location: searchStart, length: totalLen - searchStart)
                )
                if found.location == NSNotFound { break }
                storage.addAttributes(
                    [.font: foldFont, .backgroundColor: foldBg],
                    range: found
                )
                searchStart = found.location + found.length
            }
        }
        storage.endEditing()
        textView.selectedRanges = selectedRanges
        textView.typingAttributes = [
            .font: bodyFont,
            .foregroundColor: bodyColor,
            .paragraphStyle: paragraph,
        ]
    }

    @MainActor
    final class Coordinator: NSObject {
        var store: NotesStore
        weak var textView: AscensionNSTextView?
        var lastNoteID: UUID?
        var lastSyncedText: String = ""
        var lastFontSize: Double = 15.0
        var lastAutoCap: Bool = false

        init(store: NotesStore) {
            self.store = store
        }

        func handleTextDidChange(on tv: AscensionNSTextView) {
            // Wait until IME / inline predictive autocomplete settles before touching store or attributes
            if tv.hasMarkedText() {
                return
            }
            let updated = tv.string
            if updated != lastSyncedText {
                lastSyncedText = updated
                store.updateSelectedFullText(updated)
            }
            reapplyVisualLine1AndFolds(on: tv)
        }

        func enrichContextMenu(
            _ baseMenu: NSMenu,
            for view: NSTextView,
            at charIndex: Int
        ) -> NSMenu {
            let enriched = (baseMenu.copy() as? NSMenu) ?? NSMenu()
            enriched.insertItem(.separator(), at: 0)

            // Folding submenu
            let foldMenu = NSMenu(title: "Folding")
            let sel = view.selectedRange()
            if sel.length > 0 {
                let foldItem = NSMenuItem(
                    title: "Fold Selection (Shrink Block)",
                    action: #selector(AscensionNSTextView.foldSelectedBlock(_:)),
                    keyEquivalent: ""
                )
                foldItem.target = view
                foldMenu.addItem(foldItem)
            }

            if let marker = markerAt(index: charIndex, in: view.string) {
                let unfoldItem = NSMenuItem(
                    title: "Unfold Block (Expand)",
                    action: #selector(AscensionNSTextView.unfoldHoveredBlock(_:)),
                    keyEquivalent: ""
                )
                unfoldItem.representedObject = marker
                unfoldItem.target = view
                foldMenu.addItem(unfoldItem)
            }

            if !(store.selectedNote?.foldedBlocks.isEmpty ?? true) {
                let unfoldAll = NSMenuItem(
                    title: "Unfold All Blocks",
                    action: #selector(AscensionNSTextView.unfoldAllBlocks(_:)),
                    keyEquivalent: ""
                )
                unfoldAll.target = view
                foldMenu.addItem(unfoldAll)
            }

            foldMenu.addItem(.separator())
            let expandText = NSMenuItem(
                title: "Expand Text Size (Cmd +)",
                action: #selector(AscensionNSTextView.expandTextSize(_:)),
                keyEquivalent: ""
            )
            expandText.target = view
            foldMenu.addItem(expandText)

            let shrinkText = NSMenuItem(
                title: "Shrink Text Size (Cmd -)",
                action: #selector(AscensionNSTextView.shrinkTextSize(_:)),
                keyEquivalent: ""
            )
            shrinkText.target = view
            foldMenu.addItem(shrinkText)

            let foldParent = NSMenuItem(title: "Folding & Size", action: nil, keyEquivalent: "")
            foldParent.submenu = foldMenu
            enriched.insertItem(foldParent, at: 0)

            // Format submenu
            let fmtMenu = NSMenu(title: "Format")
            let fmtItems: [(String, Selector)] = [
                ("Bold (**text**)", #selector(AscensionNSTextView.wrapBold(_:))),
                ("Italic (*text*)", #selector(AscensionNSTextView.wrapItalic(_:))),
                ("Inline Code (`text`)", #selector(AscensionNSTextView.wrapCode(_:))),
                ("Heading (## )", #selector(AscensionNSTextView.prefixHeading(_:))),
                ("Bullet List (• )", #selector(AscensionNSTextView.prefixBullet(_:))),
            ]
            for (title, selAction) in fmtItems {
                let item = NSMenuItem(title: title, action: selAction, keyEquivalent: "")
                item.target = view
                fmtMenu.addItem(item)
            }

            let fmtParent = NSMenuItem(title: "Format Block", action: nil, keyEquivalent: "")
            fmtParent.submenu = fmtMenu
            enriched.insertItem(fmtParent, at: 0)

            return enriched
        }

        private func markerAt(index: Int, in text: String) -> String? {
            guard let markers = store.selectedNote?.foldedBlocks.keys else { return nil }
            let ns = text as NSString
            for marker in markers {
                var search = 0
                while search < ns.length {
                    let r = ns.range(of: marker, range: NSRange(location: search, length: ns.length - search))
                    if r.location == NSNotFound { break }
                    if index >= r.location && index <= r.location + r.length {
                        return marker
                    }
                    search = r.location + r.length
                }
            }
            return nil
        }

        private func reapplyVisualLine1AndFolds(on tv: AscensionNSTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            let len = ns.length
            guard len > 0 else { return }

            let bodyFont = NSFont.systemFont(ofSize: store.editorFontSize)
            let titleFont = NSFont.systemFont(ofSize: store.editorFontSize + 7.0, weight: .bold)
            let foldFont = NSFont.monospacedSystemFont(ofSize: max(11.0, store.editorFontSize - 1.5), weight: .semibold)
            let foldBg = NSColor.systemYellow.withAlphaComponent(0.22)

            let clampedRanges = tv.selectedRanges.compactMap { val -> NSValue? in
                let r = val.rangeValue
                let loc = min(max(0, r.location), len)
                let maxLen = max(0, len - loc)
                return NSValue(range: NSRange(location: loc, length: min(r.length, maxLen)))
            }

            storage.beginEditing()
            storage.addAttribute(.font, value: bodyFont, range: NSRange(location: 0, length: len))
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: len))
            let line1 = ns.lineRange(for: NSRange(location: 0, length: 0))
            if line1.length > 0 {
                storage.addAttribute(.font, value: titleFont, range: line1)
            }
            if let markers = store.selectedNote?.foldedBlocks.keys {
                for marker in markers {
                    var search = 0
                    while search < len {
                        let found = ns.range(of: marker, range: NSRange(location: search, length: len - search))
                        if found.location == NSNotFound { break }
                        storage.addAttributes([.font: foldFont, .backgroundColor: foldBg], range: found)
                        search = found.location + found.length
                    }
                }
            }
            storage.endEditing()
            if !clampedRanges.isEmpty {
                tv.selectedRanges = clampedRanges
            }
        }
    }
}

final class AscensionNSTextView: NSTextView {
    weak var coordinator: UnifiedNoteTextView.Coordinator?

    override func didChangeText() {
        super.didChangeText()
        coordinator?.handleTextDidChange(on: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let baseMenu = super.menu(for: event) ?? NSMenu()
        let pt = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: pt)
        return coordinator?.enrichContextMenu(baseMenu, for: self, at: charIndex) ?? baseMenu
    }

    @objc func wrapBold(_ sender: Any?) { wrapSelection(prefix: "**", suffix: "**") }
    @objc func wrapItalic(_ sender: Any?) { wrapSelection(prefix: "*", suffix: "*") }
    @objc func wrapCode(_ sender: Any?) { wrapSelection(prefix: "`", suffix: "`") }
    @objc func prefixHeading(_ sender: Any?) { prefixSelectedLines(with: "## ") }
    @objc func prefixBullet(_ sender: Any?) { prefixSelectedLines(with: "• ") }

    @objc func expandTextSize(_ sender: Any?) {
        if let marker = markerInsideSelection() {
            unfoldMarkerInPlace(marker)
            return
        }
        coordinator?.store.expandEditorFontSize()
    }

    @objc func shrinkTextSize(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0 {
            foldRangeInPlace(sel)
            return
        }
        coordinator?.store.shrinkEditorFontSize()
    }

    @objc func foldSelectedBlock(_ sender: Any?) {
        foldRangeInPlace(selectedRange())
    }

    @objc func unfoldHoveredBlock(_ sender: NSMenuItem) {
        if let marker = sender.representedObject as? String {
            unfoldMarkerInPlace(marker)
        }
    }

    @objc func unfoldAllBlocks(_ sender: Any?) {
        guard let markers = coordinator?.store.selectedNote?.foldedBlocks.keys else { return }
        for marker in Array(markers) {
            unfoldMarkerInPlace(marker)
        }
    }

    private func foldRangeInPlace(_ sel: NSRange) {
        let ns = string as NSString
        guard sel.location != NSNotFound,
              sel.length > 0,
              sel.location + sel.length <= ns.length else { return }
        let selectedText = ns.substring(with: sel)
        guard let marker = coordinator?.store.registerFold(original: selectedText) else { return }
        if shouldChangeText(in: sel, replacementString: marker) {
            replaceCharacters(in: sel, with: marker)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location, length: (marker as NSString).length))
        }
    }

    private func unfoldMarkerInPlace(_ marker: String) {
        let ns = string as NSString
        let markerRange = ns.range(of: marker)
        guard markerRange.location != NSNotFound,
              let original = coordinator?.store.consumeFoldedOriginal(for: marker) else { return }
        if shouldChangeText(in: markerRange, replacementString: original) {
            replaceCharacters(in: markerRange, with: original)
            didChangeText()
            setSelectedRange(NSRange(location: markerRange.location, length: (original as NSString).length))
        }
    }

    private func markerInsideSelection() -> String? {
        guard let markers = coordinator?.store.selectedNote?.foldedBlocks.keys else { return nil }
        let sel = selectedRange()
        let ns = string as NSString
        for marker in markers {
            let r = ns.range(of: marker)
            if r.location != NSNotFound && sel.location >= r.location && sel.location <= r.location + r.length {
                return marker
            }
        }
        return nil
    }

    private func wrapSelection(prefix: String, suffix: String) {
        let range = selectedRange()
        let ns = string as NSString
        guard range.location != NSNotFound, range.location + range.length <= ns.length else { return }
        let inner = range.length > 0 ? ns.substring(with: range) : "text"
        let replacement = "\(prefix)\(inner)\(suffix)"
        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: range.location + prefix.count, length: (inner as NSString).length))
        }
    }

    private func prefixSelectedLines(with prefix: String) {
        let ns = string as NSString
        let sel = selectedRange()
        guard sel.location != NSNotFound, sel.location + sel.length <= ns.length else { return }
        let lineRange = ns.lineRange(for: sel)
        let block = ns.substring(with: lineRange)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        let updated = lines.map { line in
            line.isEmpty ? "" : "\(prefix)\(line)"
        }.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: updated) {
            replaceCharacters(in: lineRange, with: updated)
            didChangeText()
        }
    }
}
#endif
