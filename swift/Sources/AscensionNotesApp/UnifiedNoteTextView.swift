#if os(macOS)
import AppKit
import SwiftUI

/// Unified macOS NSTextView editor:
/// - Line 1 styled as large bold Title; Cmd+A selects Title + Body together.
/// - Cmd+ / Cmd- grow/shrink ONLY the selected text (or cursor typing size), never folding.
/// - Folding is completely separate (Right-click -> Folding, or Cmd+Option+[ / ]).
/// - Safe against Spacebar autocomplete crashes (never mutates textStorage during marked text).
/// - Bottom overscroll padding lets you scroll text up the screen without blank lines.
struct UnifiedNoteTextView: NSViewRepresentable {
    @Bindable var store: NotesStore
    let noteID: UUID
    let text: String
    let defaultFontSize: Double
    let autoCapitalizeNewLines: Bool
    let foldedBlocks: [String: String]
    let fontSpans: [FontSizeSpan]

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AscensionNoteScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 360, right: 0)

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = AscensionNSTextView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400),
            textContainer: textContainer
        )
        textView.coordinator = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.usesFindBar = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 400)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 24, height: 10)

        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        applyAutoCapBehavior(to: textView, enabled: autoCapitalizeNewLines)

        textView.string = text
        applyAllTypography(to: textView, defaultSize: defaultFontSize, spans: fontSpans)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastNoteID = noteID
        context.coordinator.lastSyncedText = text
        context.coordinator.lastAutoCap = autoCapitalizeNewLines
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AscensionNSTextView else { return }
        context.coordinator.store = store
        textView.isEditable = true
        textView.isSelectable = true

        let desiredBottom = CGFloat(max(280.0, Double(scrollView.bounds.height) * 0.65))
        if abs(scrollView.contentInsets.bottom - desiredBottom) > 8 {
            scrollView.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: desiredBottom, right: 0)
        }

        let contentSize = scrollView.contentSize
        var geometryChanged = false
        if contentSize.width > 0, abs(textView.frame.width - contentSize.width) > 1 {
            var frame = textView.frame
            frame.size.width = contentSize.width
            textView.frame = frame
            geometryChanged = true
        }

        let minHeight = max(200.0, contentSize.height)
        if abs(textView.minSize.height - minHeight) > 4 {
            textView.minSize = NSSize(width: 0, height: minHeight)
            geometryChanged = true
        }
        if geometryChanged {
            textView.ensureFullLayoutAndFrame()
        }

        if context.coordinator.lastAutoCap != autoCapitalizeNewLines {
            applyAutoCapBehavior(to: textView, enabled: autoCapitalizeNewLines)
            context.coordinator.lastAutoCap = autoCapitalizeNewLines
        }

        let switchedNote = context.coordinator.lastNoteID != noteID
        let externalTextChanged = text != context.coordinator.lastSyncedText && text != textView.string

        if (switchedNote || externalTextChanged) && !textView.hasMarkedText() {
            let previousSelection = textView.selectedRange()
            textView.string = text
            context.coordinator.lastNoteID = noteID
            context.coordinator.lastSyncedText = text
            applyAllTypography(to: textView, defaultSize: defaultFontSize, spans: fontSpans)

            if !switchedNote {
                let clampedLoc = min(previousSelection.location, (text as NSString).length)
                textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
            }
        }
    }

    private func applyAutoCapBehavior(to textView: NSTextView, enabled: Bool) {
        textView.isAutomaticSpellingCorrectionEnabled = enabled
        textView.isAutomaticTextCompletionEnabled = enabled
        textView.isAutomaticTextReplacementEnabled = enabled
    }

    private func applyAllTypography(to textView: AscensionNSTextView, defaultSize: Double, spans: [FontSizeSpan]) {
        let bodyFont = NSFont.systemFont(ofSize: defaultSize)
        let titleFont = NSFont.systemFont(ofSize: defaultSize + 7.0, weight: .bold)
        let foldFont = NSFont.monospacedSystemFont(ofSize: max(11.0, defaultSize - 1.5), weight: .semibold)
        let bodyColor = NSColor.labelColor
        let foldBg = NSColor.systemYellow.withAlphaComponent(0.22)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4

        guard let storage = textView.textStorage else { return }
        let fullStr = storage.string as NSString
        let totalLen = fullStr.length
        guard totalLen > 0 else {
            textView.font = titleFont
            textView.typingAttributes = [
                .font: titleFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: paragraph,
            ]
            textView.ensureFullLayoutAndFrame()
            return
        }

        let selectedRanges = textView.selectedRanges
        storage.beginEditing()
        storage.addAttributes(
            [.font: bodyFont, .foregroundColor: bodyColor, .paragraphStyle: paragraph],
            range: NSRange(location: 0, length: totalLen)
        )
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: totalLen))

        let firstLineRange = fullStr.lineRange(for: NSRange(location: 0, length: 0))
        if firstLineRange.length > 0 {
            storage.addAttribute(.font, value: titleFont, range: firstLineRange)
        }

        for span in spans {
            let loc = max(0, min(span.location, totalLen))
            let len = max(0, min(span.length, totalLen - loc))
            guard len > 0 else { continue }
            let isTitle = loc < firstLineRange.upperBound
            let font = isTitle
                ? NSFont.systemFont(ofSize: span.size, weight: .bold)
                : NSFont.systemFont(ofSize: span.size)
            storage.addAttribute(.font, value: font, range: NSRange(location: loc, length: len))
        }

        for marker in foldedBlocks.keys {
            var searchStart = 0
            while searchStart < totalLen {
                let found = fullStr.range(
                    of: marker,
                    options: [],
                    range: NSRange(location: searchStart, length: totalLen - searchStart)
                )
                if found.location == NSNotFound { break }
                storage.addAttributes([.font: foldFont, .backgroundColor: foldBg], range: found)
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
        textView.ensureFullLayoutAndFrame()
    }

    @MainActor
    final class Coordinator: NSObject {
        var store: NotesStore
        weak var textView: AscensionNSTextView?
        var lastNoteID: UUID?
        var lastSyncedText: String = ""
        var lastAutoCap: Bool = false

        init(store: NotesStore) {
            self.store = store
        }

        func handleTextDidChange(on tv: AscensionNSTextView) {
            if tv.hasMarkedText() {
                return
            }
            let updated = tv.string
            let spans = extractFontSpans(from: tv)
            if updated != lastSyncedText {
                lastSyncedText = updated
                store.updateSelectedFullText(updated, fontSpans: spans)
            } else {
                store.updateSelectedFontSpans(spans)
            }
            DispatchQueue.main.async { [weak self, weak tv] in
                guard let self, let tv, !tv.hasMarkedText() else { return }
                self.reapplyVisualLine1AndFoldsPreservingSpans(on: tv)
            }
        }

        func persistCurrentSpans(from tv: AscensionNSTextView) {
            store.updateSelectedFontSpans(extractFontSpans(from: tv))
        }

        func extractFontSpans(from tv: AscensionNSTextView) -> [FontSizeSpan] {
            guard let storage = tv.textStorage else { return [] }
            let ns = storage.string as NSString
            let len = ns.length
            guard len > 0 else { return [] }
            let line1End = ns.lineRange(for: NSRange(location: 0, length: 0)).upperBound
            let defaultBodySize = store.editorFontSize
            let defaultTitleSize = defaultBodySize + 7.0

            var spans: [FontSizeSpan] = []
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: len)) { val, range, _ in
                guard let font = val as? NSFont else { return }
                let size = Double(font.pointSize)
                let expected = (range.location < line1End) ? defaultTitleSize : defaultBodySize
                if abs(size - expected) > 0.25 {
                    spans.append(FontSizeSpan(location: range.location, length: range.length, size: size))
                }
            }
            return spans
        }

        func enrichContextMenu(
            _ baseMenu: NSMenu,
            for view: NSTextView,
            at charIndex: Int
        ) -> NSMenu {
            let enriched = (baseMenu.copy() as? NSMenu) ?? NSMenu()
            enriched.insertItem(.separator(), at: 0)

            // Separate Text Size submenu (Only selected text grows/shrinks)
            let sizeMenu = NSMenu(title: "Text Size")
            let growItem = NSMenuItem(
                title: "Grow Selected Text (Cmd +)",
                action: #selector(AscensionNSTextView.growSelectedText(_:)),
                keyEquivalent: ""
            )
            growItem.target = view
            sizeMenu.addItem(growItem)

            let shrinkItem = NSMenuItem(
                title: "Shrink Selected Text (Cmd -)",
                action: #selector(AscensionNSTextView.shrinkSelectedText(_:)),
                keyEquivalent: ""
            )
            shrinkItem.target = view
            sizeMenu.addItem(shrinkItem)

            let resetItem = NSMenuItem(
                title: "Reset Selected Size (Cmd 0)",
                action: #selector(AscensionNSTextView.resetSelectedTextSize(_:)),
                keyEquivalent: ""
            )
            resetItem.target = view
            sizeMenu.addItem(resetItem)

            let sizeParent = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
            sizeParent.submenu = sizeMenu
            enriched.insertItem(sizeParent, at: 0)

            // Separate Folding submenu (Does NOT mix with + / -)
            let foldMenu = NSMenu(title: "Folding")
            let sel = view.selectedRange()
            if sel.length > 0 {
                let foldItem = NSMenuItem(
                    title: "Fold Selection (Cmd+Opt+[)",
                    action: #selector(AscensionNSTextView.foldSelectedBlock(_:)),
                    keyEquivalent: ""
                )
                foldItem.target = view
                foldMenu.addItem(foldItem)
            }

            if let marker = markerAt(index: charIndex, in: view.string) {
                let unfoldItem = NSMenuItem(
                    title: "Unfold Block (Cmd+Opt+])",
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

            if !foldMenu.items.isEmpty {
                let foldParent = NSMenuItem(title: "Folding", action: nil, keyEquivalent: "")
                foldParent.submenu = foldMenu
                enriched.insertItem(foldParent, at: 0)
            }

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

        private func reapplyVisualLine1AndFoldsPreservingSpans(on tv: AscensionNSTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            let len = ns.length
            guard len > 0 else {
                tv.ensureFullLayoutAndFrame()
                return
            }

            let foldFont = NSFont.monospacedSystemFont(ofSize: max(11.0, store.editorFontSize - 1.5), weight: .semibold)
            let foldBg = NSColor.systemYellow.withAlphaComponent(0.22)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4

            let savedSelections = tv.selectedRanges
            let savedTyping = tv.typingAttributes

            let line1 = ns.lineRange(for: NSRange(location: 0, length: 0))
            storage.beginEditing()
            storage.addAttributes(
                [.foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph],
                range: NSRange(location: 0, length: len)
            )
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: len))

            // Keep existing per-character font sizes, updating only Line 1 bold weight
            if line1.length > 0 {
                storage.enumerateAttribute(.font, in: line1) { val, subRange, _ in
                    let currentSize = (val as? NSFont)?.pointSize ?? CGFloat(store.editorFontSize + 7.0)
                    let targetSize = max(currentSize, CGFloat(store.editorFontSize + 7.0))
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: targetSize, weight: .bold), range: subRange)
                }
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

            let clampedSelections: [NSValue] = savedSelections.map { val in
                let r = val.rangeValue
                let loc = max(0, min(r.location, len))
                let rLen = max(0, min(r.length, len - loc))
                return NSValue(range: NSRange(location: loc, length: rLen))
            }
            if !clampedSelections.isEmpty {
                tv.selectedRanges = clampedSelections
            }
            var restoredTyping = savedTyping
            restoredTyping[.paragraphStyle] = paragraph
            if restoredTyping[.foregroundColor] == nil {
                restoredTyping[.foregroundColor] = NSColor.labelColor
            }
            tv.typingAttributes = restoredTyping
            tv.ensureFullLayoutAndFrame()
        }
    }
}

final class AscensionNoteScrollView: NSScrollView {
    override func mouseDown(with event: NSEvent) {
        if let tv = documentView as? NSTextView {
            window?.makeFirstResponder(tv)
            let endLoc = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: endLoc, length: 0))
            return
        }
        super.mouseDown(with: event)
    }
}

final class AscensionNSTextView: NSTextView {
    weak var coordinator: UnifiedNoteTextView.Coordinator?

    func ensureFullLayoutAndFrame() {
        guard let tc = textContainer, let lm = layoutManager else { return }
        lm.ensureLayout(for: tc)
        sizeToFit()
        needsLayout = true
        needsDisplay = true
    }

    override func paste(_ sender: Any?) {
        performNormalizedPlainTextPaste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        performNormalizedPlainTextPaste(sender)
    }

    private func performNormalizedPlainTextPaste(_ sender: Any?) {
        guard let rawPaste = NSPasteboard.general.string(forType: .string) else {
            super.pasteAsPlainText(sender)
            ensureFullLayoutAndFrame()
            return
        }

        let clean = rawPaste
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FFFC}", with: "")

        let currentNS = string as NSString
        let rawSel = selectedRange()
        guard rawSel.location != NSNotFound else {
            super.pasteAsPlainText(sender)
            ensureFullLayoutAndFrame()
            return
        }
        let clampedLoc = max(0, min(rawSel.location, currentNS.length))
        let clampedLen = max(0, min(rawSel.length, currentNS.length - clampedLoc))
        let sel = NSRange(location: clampedLoc, length: clampedLen)

        let defaultBody = CGFloat(coordinator?.store.editorFontSize ?? 15.0)
        let titleFont = NSFont.systemFont(ofSize: defaultBody + 7.0, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: defaultBody)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]

        guard shouldChangeText(in: sel, replacementString: clean) else { return }

        replaceCharacters(in: sel, with: clean)
        let insertedLen = (clean as NSString).length
        let insertedRange = NSRange(location: sel.location, length: insertedLen)

        if let storage = textStorage, insertedLen > 0 {
            let fullNS = storage.string as NSString
            let safeLen = min(insertedRange.length, max(0, fullNS.length - insertedRange.location))
            let safeInserted = NSRange(location: insertedRange.location, length: safeLen)
            if safeInserted.length > 0 {
                let line1 = fullNS.lineRange(for: NSRange(location: 0, length: 0))
                storage.beginEditing()
                storage.setAttributes(bodyAttrs, range: safeInserted)
                let titleOverlap = NSIntersectionRange(safeInserted, line1)
                if titleOverlap.length > 0 {
                    storage.addAttribute(.font, value: titleFont, range: titleOverlap)
                }
                storage.endEditing()
            }
        }

        didChangeText()

        let updatedLen = (string as NSString).length
        let endLoc = min(sel.location + insertedLen, updatedLen)
        let cursorRange = NSRange(location: endLoc, length: 0)
        setSelectedRange(cursorRange)

        let afterLine1 = (string as NSString).lineRange(for: NSRange(location: 0, length: 0))
        let cursorInTitle = endLoc < afterLine1.upperBound && (string as NSString).length > 0
        typingAttributes = [
            .font: cursorInTitle ? titleFont : bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        ensureFullLayoutAndFrame()
        scrollRangeToVisible(cursorRange)
    }

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

    // MARK: - Selection-Only Font Grow / Shrink (Never mixes with Folding!)

    @objc func growSelectedText(_ sender: Any?) {
        adjustSelectedFontSize(delta: 2.0)
    }

    @objc func shrinkSelectedText(_ sender: Any?) {
        adjustSelectedFontSize(delta: -2.0)
    }

    @objc func resetSelectedTextSize(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let defaultBody = CGFloat(coordinator?.store.editorFontSize ?? 15.0)
        let sel = selectedRange()
        let ns = storage.string as NSString
        guard sel.location != NSNotFound, sel.location + sel.length <= ns.length else { return }
        let targetRange = sel.length > 0 ? sel : NSRange(location: 0, length: ns.length)
        let line1End = ns.lineRange(for: NSRange(location: 0, length: 0)).upperBound

        storage.beginEditing()
        if targetRange.length > 0 {
            let line1Hit = NSIntersectionRange(targetRange, NSRange(location: 0, length: line1End))
            if line1Hit.length > 0 {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: defaultBody + 7.0, weight: .bold), range: line1Hit)
            }
            let bodyStart = max(targetRange.location, line1End)
            let bodyEnd = targetRange.location + targetRange.length
            if bodyEnd > bodyStart {
                storage.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: defaultBody),
                    range: NSRange(location: bodyStart, length: bodyEnd - bodyStart)
                )
            }
        }
        storage.endEditing()
        typingAttributes[.font] = NSFont.systemFont(ofSize: defaultBody)
        coordinator?.persistCurrentSpans(from: self)
    }

    private func adjustSelectedFontSize(delta: CGFloat) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let defaultBody = CGFloat(coordinator?.store.editorFontSize ?? 15.0)

        if sel.length == 0 {
            let current = (typingAttributes[.font] as? NSFont)?.pointSize ?? defaultBody
            let nextSize = min(48.0, max(9.0, current + delta))
            typingAttributes[.font] = NSFont.systemFont(ofSize: nextSize)
            return
        }

        let ns = storage.string as NSString
        guard sel.location != NSNotFound, sel.location + sel.length <= ns.length else { return }
        let line1End = ns.lineRange(for: NSRange(location: 0, length: 0)).upperBound

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: sel) { val, subRange, _ in
            let oldFont = (val as? NSFont) ?? NSFont.systemFont(ofSize: defaultBody)
            let newSize = min(48.0, max(9.0, oldFont.pointSize + delta))
            let weight: NSFont.Weight = (subRange.location < line1End) ? .bold : .regular
            let newFont = NSFont.systemFont(ofSize: newSize, weight: weight)
            storage.addAttribute(.font, value: newFont, range: subRange)
        }
        storage.endEditing()
        coordinator?.persistCurrentSpans(from: self)
    }

    // MARK: - Separate Folding Actions

    @objc func foldSelectedBlock(_ sender: Any?) {
        foldRangeInPlace(selectedRange())
    }

    @objc func unfoldHoveredBlock(_ sender: NSMenuItem) {
        if let marker = sender.representedObject as? String {
            unfoldMarkerInPlace(marker)
        }
    }

    @objc func unfoldBlockAtCursor(_ sender: Any?) {
        if let marker = markerInsideSelection() {
            unfoldMarkerInPlace(marker)
        } else {
            unfoldAllBlocks(sender)
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
