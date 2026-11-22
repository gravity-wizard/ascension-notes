#if os(macOS)
import AppKit
import AscensionCore
import SwiftUI

/// Unified macOS NSTextView editor:
/// - Line 1 styled as large bold Title; Cmd+A selects Title + Body together.
/// - Cmd+ / Cmd- grow/shrink ONLY the selected text (or cursor typing size), never folding.
/// - Folding is completely separate (Right-click -> Folding, or Cmd+Option+[ / ]).
/// - Safe against Spacebar autocomplete crashes (never mutates textStorage during marked text).
/// - Bottom overscroll padding lets you scroll text up the screen without blank lines.
/// - Right-click & cursor-aware Quick Actions for Skip Vowels, +ii, +is5, and Learn Spelling.
/// - Drag-and-drop & clipboard image paste saving lossless Retina PNGs + clean ▸[Image: ...] markers.
struct UnifiedNoteTextView: NSViewRepresentable {
    @Bindable var store: NotesStore
    let noteID: UUID
    let text: String
    let defaultFontSize: Double
    let autoCapitalizeNewLines: Bool
    let foldedBlocks: [String: String]
    let fontSpans: [FontSizeSpan]
    let searchSignature: String
    let searchHighlightRanges: [NSRange]
    let activeSearchIndex: Int

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
        textView.delegate = context.coordinator
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
        textView.registerForDraggedTypes([.fileURL, .png, .tiff, .URL])

        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        applyAutoCapBehavior(to: textView, enabled: autoCapitalizeNewLines)

        textView.string = text
        applyAllTypography(to: textView, defaultSize: defaultFontSize, spans: fontSpans)
        context.coordinator.applySearchHighlights(
            to: textView,
            ranges: searchHighlightRanges,
            activeIndex: activeSearchIndex
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastNoteID = noteID
        context.coordinator.lastSyncedText = text
        context.coordinator.lastAutoCap = autoCapitalizeNewLines
        context.coordinator.lastSearchSignature = searchSignature
        context.coordinator.lastActiveSearchIndex = activeSearchIndex
        context.coordinator.installTextViewActionHandler()

        if let firstTarget = context.coordinator.targetRange(from: searchHighlightRanges, activeIndex: activeSearchIndex) {
            Task { @MainActor [weak textView] in
                await Task.yield()
                guard let textView else { return }
                textView.ensureFullLayoutAndFrame()
                textView.scrollRangeToVisible(firstTarget)
                textView.showFindIndicator(for: firstTarget)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AscensionNSTextView else { return }
        context.coordinator.store = store
        context.coordinator.textView = textView
        context.coordinator.installTextViewActionHandler()
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
        let searchChanged = context.coordinator.lastSearchSignature != searchSignature
        let activeIndexChanged = context.coordinator.lastActiveSearchIndex != activeSearchIndex

        if (switchedNote || externalTextChanged) && !textView.hasMarkedText() {
            let previousSelection = textView.selectedRange()
            textView.string = text
            context.coordinator.lastNoteID = noteID
            context.coordinator.lastSyncedText = text
            applyAllTypography(to: textView, defaultSize: defaultFontSize, spans: fontSpans)

            if switchedNote {
                context.coordinator.clearPublishedSpellTargetAsync()
            } else {
                let clampedLoc = min(previousSelection.location, (text as NSString).length)
                textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
            }
        }

        context.coordinator.lastSearchSignature = searchSignature
        context.coordinator.lastActiveSearchIndex = activeSearchIndex
        context.coordinator.applySearchHighlights(
            to: textView,
            ranges: searchHighlightRanges,
            activeIndex: activeSearchIndex
        )

        if (switchedNote || searchChanged || activeIndexChanged),
           let target = context.coordinator.targetRange(from: searchHighlightRanges, activeIndex: activeSearchIndex) {
            let pulse = switchedNote || activeIndexChanged
            Task { @MainActor [weak textView] in
                await Task.yield()
                guard let textView else { return }
                textView.ensureFullLayoutAndFrame()
                textView.scrollRangeToVisible(target)
                if pulse {
                    textView.showFindIndicator(for: target)
                }
            }
        }
    }

    private func applyAutoCapBehavior(to textView: NSTextView, enabled: Bool) {
        textView.isAutomaticSpellingCorrectionEnabled = enabled
        textView.isAutomaticTextCompletionEnabled = enabled
        textView.isAutomaticTextReplacementEnabled = enabled
    }
    static let imageMarkerRegex = try? NSRegularExpression(pattern: #"▸\[Image:[^\n\]]*\]"#)
    static let strikethroughRegex = try? NSRegularExpression(pattern: #"~~([^\n~]+?)~~"#)

    static func createStandardParagraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.defaultTabInterval = 48.0
        var tabs: [NSTextTab] = []
        for i in 1...32 {
            tabs.append(NSTextTab(textAlignment: .left, location: CGFloat(i) * 48.0, options: [:]))
        }
        paragraph.tabStops = tabs
        return paragraph
    }

    private func applyAllTypography(to textView: AscensionNSTextView, defaultSize: Double, spans: [FontSizeSpan]) {
        let bodyFont = NSFont.systemFont(ofSize: defaultSize)
        let titleFont = NSFont.systemFont(ofSize: defaultSize + 7.0, weight: .bold)
        let foldFont = NSFont.monospacedSystemFont(ofSize: max(11.0, defaultSize - 1.5), weight: .semibold)
        let imageMarkerFont = NSFont.monospacedSystemFont(ofSize: max(11.0, defaultSize - 1.5), weight: .medium)
        let bodyColor = NSColor.labelColor
        let foldBg = NSColor.systemYellow.withAlphaComponent(0.22)
        let imageBg = NSColor.systemBlue.withAlphaComponent(0.14)

        let paragraph = Self.createStandardParagraphStyle()

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
        storage.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: totalLen))

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

        if let strikeRegex = Self.strikethroughRegex {
            let matches = strikeRegex.matches(in: storage.string, range: NSRange(location: 0, length: totalLen))
            for match in matches {
                let innerRange = match.range(at: 1)
                if innerRange.location != NSNotFound && innerRange.length > 0 {
                    storage.addAttributes(
                        [
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: NSColor.secondaryLabelColor,
                        ],
                        range: innerRange
                    )
                }
            }
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

        if let imgRegex = Self.imageMarkerRegex {
            let matches = imgRegex.matches(in: storage.string, range: NSRange(location: 0, length: totalLen))
            for match in matches {
                storage.addAttributes([.font: imageMarkerFont, .backgroundColor: imageBg], range: match.range)
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
    final class Coordinator: NSObject, NSTextViewDelegate {
        var store: NotesStore
        weak var textView: AscensionNSTextView?
        var lastNoteID: UUID?
        var lastSyncedText: String = ""
        var lastAutoCap: Bool = false
        var lastSearchSignature: String = ""
        var lastActiveSearchIndex: Int = -1
        var hasActiveSearchHighlights: Bool = false
        var lastPublishedSpellTarget: CursorSpellTarget? = nil

        init(store: NotesStore) {
            self.store = store
        }

        func targetRange(from ranges: [NSRange], activeIndex: Int) -> NSRange? {
            guard !ranges.isEmpty else { return nil }
            let idx = ((activeIndex % ranges.count) + ranges.count) % ranges.count
            return ranges[idx]
        }

        func applySearchHighlights(
            to tv: AscensionNSTextView,
            ranges: [NSRange],
            activeIndex: Int
        ) {
            guard let layoutManager = tv.layoutManager else { return }
            let totalLen = (tv.string as NSString).length
            guard totalLen > 0 else {
                hasActiveSearchHighlights = false
                return
            }

            if hasActiveSearchHighlights || !ranges.isEmpty {
                layoutManager.removeTemporaryAttribute(
                    .backgroundColor,
                    forCharacterRange: NSRange(location: 0, length: totalLen)
                )
            }

            guard !ranges.isEmpty else {
                hasActiveSearchHighlights = false
                return
            }

            let clampedActive = ((activeIndex % ranges.count) + ranges.count) % ranges.count
            let baseColor = NSColor(calibratedRed: 0.94, green: 0.78, blue: 0.22, alpha: 0.36)
            let activeColor = NSColor(calibratedRed: 0.96, green: 0.60, blue: 0.10, alpha: 0.56)

            for (idx, range) in ranges.enumerated() {
                let loc = max(0, min(range.location, totalLen))
                let len = max(0, min(range.length, totalLen - loc))
                guard len > 0 else { continue }
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: idx == clampedActive ? activeColor : baseColor,
                    forCharacterRange: NSRange(location: loc, length: len)
                )
            }
            hasActiveSearchHighlights = true
        }

        func installTextViewActionHandler() {
            store.activeTextViewActionHandler = { [weak self] action in
                guard let self, let tv = self.textView else { return false }
                switch action {
                case .replaceRange(let location, let length, let replacement, let learnWord):
                    tv.window?.makeFirstResponder(tv)
                    let ns = tv.string as NSString
                    guard location >= 0, length >= 0, location + length <= ns.length else {
                        return false
                    }
                    let range = NSRange(location: location, length: length)
                    if tv.shouldChangeText(in: range, replacementString: replacement) {
                        tv.replaceCharacters(in: range, with: replacement)
                        tv.didChangeText()
                    } else {
                        tv.insertText(replacement, replacementRange: range)
                    }
                    let newLen = (replacement as NSString).length
                    if let learnWord, !learnWord.isEmpty {
                        NSSpellChecker.shared.learnWord(learnWord)
                    }
                    let newRange = NSRange(location: location, length: newLen)
                    tv.layoutManager?.removeTemporaryAttribute(.spellingState, forCharacterRange: newRange)
                    let cursorPos = min(location + newLen, (tv.string as NSString).length)
                    tv.setSelectedRange(NSRange(location: cursorPos, length: 0))
                    tv.window?.makeFirstResponder(tv)
                    tv.checkTextInDocument(nil)
                    self.refreshCursorSpellTarget(on: tv)
                    return true

                case .learnOnly(let word):
                    NSSpellChecker.shared.learnWord(word)
                    tv.clearSpellingUnderlines(for: word)
                    tv.checkTextInDocument(nil)
                    self.refreshCursorSpellTarget(on: tv)
                    return true

                case .insertText(let snippet):
                    tv.window?.makeFirstResponder(tv)
                    let actualSnippet = NotesStore.normalizeDitto(snippet)
                    let sel = tv.selectedRange()
                    let currentNS = tv.string as NSString
                    let safeLoc = sel.location == NSNotFound ? currentNS.length : min(sel.location, currentNS.length)
                    let safeLen = sel.location == NSNotFound ? 0 : min(sel.length, currentNS.length - safeLoc)
                    let targetRange = NSRange(location: safeLoc, length: safeLen)
                    if tv.shouldChangeText(in: targetRange, replacementString: actualSnippet) {
                        tv.replaceCharacters(in: targetRange, with: actualSnippet)
                        tv.didChangeText()
                    } else {
                        tv.insertText(actualSnippet, replacementRange: targetRange)
                    }
                    self.store.recordEmojiInsertion(location: safeLoc, emoji: actualSnippet)
                    let newPos = safeLoc + (actualSnippet as NSString).length
                    tv.setSelectedRange(NSRange(location: newPos, length: 0))
                    tv.window?.makeFirstResponder(tv)
                    return true

                case .revealRange(let range):
                    let totalLen = (tv.string as NSString).length
                    guard totalLen > 0 else { return false }
                    let loc = max(0, min(range.location, totalLen))
                    let len = max(0, min(range.length, totalLen - loc))
                    let safeRange = NSRange(location: loc, length: len)
                    if let note = self.store.selectedNote {
                        let ranges = self.store.searchHighlightNSRanges(for: note)
                        self.applySearchHighlights(
                            to: tv,
                            ranges: ranges,
                            activeIndex: self.store.activeSearchMatchIndex
                        )
                    }
                    tv.ensureFullLayoutAndFrame()
                    tv.scrollRangeToVisible(safeRange)
                    if safeRange.length > 0 {
                        tv.showFindIndicator(for: safeRange)
                    }
                    return true

                case .flushAndSave:
                    self.flushPendingEdits(on: tv)
                    return true
                }
            }
        }

        func flushPendingEdits(on tv: AscensionNSTextView) {
            if tv.hasMarkedText() {
                tv.unmarkText()
            }
            let updated = tv.string
            let spans = extractFontSpans(from: tv)
            if updated != lastSyncedText {
                lastSyncedText = updated
                store.updateSelectedFullText(updated, fontSpans: spans)
            } else {
                store.updateSelectedFontSpans(spans)
            }
        }

        func clearPublishedSpellTargetAsync() {
            lastPublishedSpellTarget = nil
            DispatchQueue.main.async { [weak self] in
                self?.store.cursorSpellTarget = nil
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let tv = notification.object as? AscensionNSTextView else { return }
            flushPendingEdits(on: tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? AscensionNSTextView,
                  !tv.hasMarkedText() else {
                return
            }
            refreshCursorSpellTarget(on: tv)
            checkForCursorPreemptEmoji(on: tv)
        }

        func checkForCursorPreemptEmoji(on tv: AscensionNSTextView) {
            let sel = tv.selectedRange()
            guard sel.location != NSNotFound, sel.location > 0 else { return }
            let text = tv.string as NSString
            guard sel.location <= text.length else { return }

            if sel.location >= 4 {
                let fourRange = NSRange(location: sel.location - 4, length: 4)
                let sub4 = text.substring(with: fourRange)
                if sub4 == "🔻🔻" {
                    store.preemptRecentEmoji("🔻🔻")
                    return
                }
                if sub4 == "🔺🔺" {
                    store.preemptRecentEmoji("🔺🔺")
                    return
                }
            }

            let charRange = text.rangeOfComposedCharacterSequence(at: sel.location - 1)
            let snippet = text.substring(with: charRange)
            let cleanSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanSnippet == "🔺" {
                store.preemptRecentEmoji("🔺🔺")
                return
            }
            if cleanSnippet == "🔻" {
                store.preemptRecentEmoji("🔻🔻")
                return
            }
            if Self.isEmojiString(cleanSnippet) {
                store.preemptRecentEmoji(cleanSnippet)
                return
            }

            if sel.location < text.length {
                if sel.location + 4 <= text.length {
                    let forwardFour = NSRange(location: sel.location, length: 4)
                    let fsub4 = text.substring(with: forwardFour)
                    if fsub4 == "🔻🔻" {
                        store.preemptRecentEmoji("🔻🔻")
                        return
                    }
                    if fsub4 == "🔺🔺" {
                        store.preemptRecentEmoji("🔺🔺")
                        return
                    }
                }
                let forwardRange = text.rangeOfComposedCharacterSequence(at: sel.location)
                let forwardSnippet = text.substring(with: forwardRange)
                let cleanForward = forwardSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanForward == "🔺" {
                    store.preemptRecentEmoji("🔺🔺")
                    return
                }
                if cleanForward == "🔻" {
                    store.preemptRecentEmoji("🔻🔻")
                    return
                }
                if Self.isEmojiString(cleanForward) {
                    store.preemptRecentEmoji(cleanForward)
                }
            }
        }

        static func isEmojiString(_ s: String) -> Bool {
            let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return false }
            var hasEmoji = false
            for scalar in clean.unicodeScalars {
                // Skip variation selectors (U+FE00...U+FE0F) and zero-width joiners (U+200D)
                if (0xFE00...0xFE0F).contains(scalar.value) || scalar.value == 0x200D {
                    continue
                }
                if scalar.value < 0x00A0 {
                    return false
                }
                if scalar.properties.isEmoji {
                    hasEmoji = true
                }
            }
            return hasEmoji
        }

        func refreshCursorSpellTarget(on tv: AscensionNSTextView) {
            guard let noteID = lastNoteID else { return }
            let sel = tv.selectedRange()
            guard sel.location != NSNotFound, sel.length <= 24 else {
                publishSpellTargetIfNeeded(nil)
                return
            }

            guard let inspection = SpellcheckHelper.inspectWord(
                at: sel.location,
                in: tv.string,
                spellDocumentTag: tv.spellCheckerDocumentTag
            ) else {
                publishSpellTargetIfNeeded(nil)
                return
            }

            let suggestion = store.suggestSkipVowels(for: inspection.word)
            let target = CursorSpellTarget(
                noteID: noteID,
                word: inspection.word,
                rangeLocation: inspection.rangeLocation,
                rangeLength: inspection.rangeLength,
                isMisspelled: inspection.isMisspelled,
                isGrammarIs: inspection.isGrammarIs,
                guesses: inspection.guesses,
                skipVowelsSuggestion: suggestion?.normalized,
                skipVowelsIsExact: suggestion?.isExactMatch ?? false
            )
            publishSpellTargetIfNeeded(target)
        }

        private func publishSpellTargetIfNeeded(_ target: CursorSpellTarget?) {
            guard target != lastPublishedSpellTarget else { return }
            lastPublishedSpellTarget = target
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.store.cursorSpellTarget = target
            }
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
            checkForCursorPreemptEmoji(on: tv)
            DispatchQueue.main.async { [weak self, weak tv] in
                guard let self, let tv, !tv.hasMarkedText() else { return }
                self.reapplyVisualLine1AndFoldsPreservingSpans(on: tv)
                if let note = self.store.selectedNote {
                    let ranges = self.store.searchHighlightNSRanges(for: note)
                    self.applySearchHighlights(
                        to: tv,
                        ranges: ranges,
                        activeIndex: self.store.activeSearchMatchIndex
                    )
                }
                self.refreshCursorSpellTarget(on: tv)
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
            for view: AscensionNSTextView,
            at charIndex: Int
        ) -> NSMenu {
            let enriched = (baseMenu.copy() as? NSMenu) ?? NSMenu()
            enriched.insertItem(.separator(), at: 0)

            let wrapDittosItem = NSMenuItem(
                title: "Wrap in Directional Dittos (Equal Width Banner)",
                action: #selector(AscensionNSTextView.wrapInDirectionalDittos(_:)),
                keyEquivalent: ""
            )
            wrapDittosItem.target = view
            enriched.insertItem(wrapDittosItem, at: 0)

            let copyForAppleNotesItem = NSMenuItem(
                title: "Copy for Apple Notes (Clean Plain Text)",
                action: #selector(AscensionNSTextView.copyForAppleNotes(_:)),
                keyEquivalent: ""
            )
            copyForAppleNotesItem.target = view
            enriched.insertItem(copyForAppleNotesItem, at: 0)

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
                ("Cross-Out (~~text~~)", #selector(AscensionNSTextView.wrapStrikethrough(_:))),
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

            // Red-underlined token & standalone "is" Quick Actions at the very top
            if let inspection = SpellcheckHelper.inspectWord(
                at: charIndex,
                in: view.string,
                spellDocumentTag: view.spellCheckerDocumentTag
            ) {
                var quickItems: [NSMenuItem] = []
                let tokenRange = NSRange(location: inspection.rangeLocation, length: inspection.rangeLength)

                let header = NSMenuItem(
                    title: inspection.isGrammarIs
                        ? "Grammar Tag: \"\(inspection.word)\""
                        : "Ascension Quick Fix: \"\(inspection.word)\"",
                    action: nil,
                    keyEquivalent: ""
                )
                header.isEnabled = false
                quickItems.append(header)

                if inspection.isGrammarIs {
                    let is5Item = NSMenuItem(
                        title: "Replace \"\(inspection.word)\" with \"is5\" (No Grammar Squiggle)",
                        action: #selector(AscensionNSTextView.quickReplaceWithIS5(_:)),
                        keyEquivalent: ""
                    )
                    is5Item.target = view
                    is5Item.representedObject = SpellMenuPayload(
                        word: inspection.word,
                        range: tokenRange,
                        replacement: "is5"
                    )
                    quickItems.append(is5Item)

                    let iiTarget = VerificationTagHelper.appendII(to: inspection.word)
                    let iiItem = NSMenuItem(
                        title: "Append \"ii\" (\"\(inspection.word)\" → \"\(iiTarget)\") & Verify",
                        action: #selector(AscensionNSTextView.quickAppendII(_:)),
                        keyEquivalent: ""
                    )
                    iiItem.target = view
                    iiItem.representedObject = SpellMenuPayload(
                        word: inspection.word,
                        range: tokenRange,
                        replacement: iiTarget
                    )
                    quickItems.append(iiItem)
                } else {
                    let suggestion = store.suggestSkipVowels(for: inspection.word)
                    if let suggestion, suggestion.isExactMatch {
                        let oneClick = NSMenuItem(
                            title: "1-Click Skip Vowels: \"\(inspection.word)\" → \"\(suggestion.normalized)\"",
                            action: #selector(AscensionNSTextView.quickApplyExactSkipVowels(_:)),
                            keyEquivalent: ""
                        )
                        oneClick.target = view
                        oneClick.representedObject = SpellMenuPayload(
                            word: inspection.word,
                            range: tokenRange,
                            replacement: suggestion.normalized
                        )
                        quickItems.append(oneClick)
                    }

                    let promptTitle: String
                    if let sug = suggestion {
                        promptTitle = "Verify & Add \"Skip Vowels\" Rule (\"\(sug.normalized)\")..."
                    } else {
                        promptTitle = "Verify & Add \"Skip Vowels\" Rule..."
                    }
                    let skipItem = NSMenuItem(
                        title: promptTitle,
                        action: #selector(AscensionNSTextView.quickPromptSkipVowels(_:)),
                        keyEquivalent: ""
                    )
                    skipItem.target = view
                    skipItem.representedObject = SpellMenuPayload(
                        word: inspection.word,
                        range: tokenRange,
                        replacement: suggestion?.normalized
                    )
                    quickItems.append(skipItem)

                    let iiTarget = VerificationTagHelper.appendII(to: inspection.word)
                    let iiTitle = iiTarget == inspection.word
                        ? "Verify \"\(inspection.word)\" (ILS ATSS ii)"
                        : "Append \"ii\" (\"\(inspection.word)\" → \"\(iiTarget)\") & Verify"
                    let iiItem = NSMenuItem(
                        title: iiTitle,
                        action: #selector(AscensionNSTextView.quickAppendII(_:)),
                        keyEquivalent: ""
                    )
                    iiItem.target = view
                    iiItem.representedObject = SpellMenuPayload(
                        word: inspection.word,
                        range: tokenRange,
                        replacement: iiTarget
                    )
                    quickItems.append(iiItem)

                    let is5Target = VerificationTagHelper.appendIS5(to: inspection.word)
                    let is5Item = NSMenuItem(
                        title: "Append \"is5\" (\"\(inspection.word)\" → \"\(is5Target)\") — Hierarchy Tag",
                        action: #selector(AscensionNSTextView.quickAppendIS5(_:)),
                        keyEquivalent: ""
                    )
                    is5Item.target = view
                    is5Item.representedObject = SpellMenuPayload(
                        word: inspection.word,
                        range: tokenRange,
                        replacement: is5Target
                    )
                    quickItems.append(is5Item)

                    let learnItem = NSMenuItem(
                        title: "Learn Spelling (\"\(inspection.word)\")",
                        action: #selector(AscensionNSTextView.quickLearnSpelling(_:)),
                        keyEquivalent: ""
                    )
                    learnItem.target = view
                    learnItem.representedObject = SpellMenuPayload(
                        word: inspection.word,
                        range: tokenRange,
                        replacement: nil
                    )
                    quickItems.append(learnItem)
                }

                quickItems.append(.separator())
                for item in quickItems.reversed() {
                    enriched.insertItem(item, at: 0)
                }
            }

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
            let imageMarkerFont = NSFont.monospacedSystemFont(ofSize: max(11.0, store.editorFontSize - 1.5), weight: .medium)
            let foldBg = NSColor.systemYellow.withAlphaComponent(0.22)
            let imageBg = NSColor.systemBlue.withAlphaComponent(0.14)
            let paragraph = UnifiedNoteTextView.createStandardParagraphStyle()

            let savedSelections = tv.selectedRanges
            let savedTyping = tv.typingAttributes

            let line1 = ns.lineRange(for: NSRange(location: 0, length: 0))
            storage.beginEditing()
            storage.addAttributes(
                [.foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph],
                range: NSRange(location: 0, length: len)
            )
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: len))
            storage.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: len))

            // Keep existing per-character font sizes, updating only Line 1 bold weight
            if line1.length > 0 {
                storage.enumerateAttribute(.font, in: line1) { val, subRange, _ in
                    let currentSize = (val as? NSFont)?.pointSize ?? CGFloat(store.editorFontSize + 7.0)
                    let targetSize = max(currentSize, CGFloat(store.editorFontSize + 7.0))
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: targetSize, weight: .bold), range: subRange)
                }
            }

            if let strikeRegex = UnifiedNoteTextView.strikethroughRegex {
                let matches = strikeRegex.matches(in: storage.string, range: NSRange(location: 0, length: len))
                for match in matches {
                    let innerRange = match.range(at: 1)
                    if innerRange.location != NSNotFound && innerRange.length > 0 {
                        storage.addAttributes(
                            [
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                .foregroundColor: NSColor.secondaryLabelColor,
                            ],
                            range: innerRange
                        )
                    }
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

            if let imgRegex = UnifiedNoteTextView.imageMarkerRegex {
                let matches = imgRegex.matches(in: storage.string, range: NSRange(location: 0, length: len))
                for match in matches {
                    storage.addAttributes([.font: imageMarkerFont, .backgroundColor: imageBg], range: match.range)
                }
            }

            storage.endEditing()

            let clampedSelections: [NSValue] = savedSelections.map { val in
                let r = val.rangeValue
                let loc = max(0, min(r.location, len))
                let rLen = max(0, min(r.length, len - loc))
                return NSValue(range: NSRange(location: loc, length: rLen))
            }
            if NSEvent.pressedMouseButtons == 0 && !clampedSelections.isEmpty {
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

@MainActor
final class SpellMenuPayload: NSObject {
    let word: String
    let range: NSRange
    let replacement: String?

    init(word: String, range: NSRange, replacement: String?) {
        self.word = word
        self.range = range
        self.replacement = replacement
    }
}

final class AscensionNoteScrollView: NSScrollView {
    override func mouseDown(with event: NSEvent) {
        if let tv = documentView as? NSTextView {
            window?.makeFirstResponder(tv)
            tv.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }
}

final class AscensionNSTextView: NSTextView {
    weak var coordinator: UnifiedNoteTextView.Coordinator?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL, .png, .tiff, .URL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .png, .tiff, .URL])
    }

    // MARK: - Ditto Pairs ("Click once, get second one free")
    override func insertText(_ string: Any, replacementRange: NSRange) {
        var strToInsert: Any = string
        if let s = string as? String {
            if s == "🔺" {
                strToInsert = "🔺🔺"
            } else if s == "🔻" {
                strToInsert = "🔻🔻"
            }
        } else if let attr = string as? NSAttributedString {
            if attr.string == "🔺" {
                strToInsert = "🔺🔺"
            } else if attr.string == "🔻" {
                strToInsert = "🔻🔻"
            }
        }
        super.insertText(strToInsert, replacementRange: replacementRange)
    }

    // MARK: - Tab Key ("Using Tab Key gives nice separation ❗️")
    override func insertTab(_ sender: Any?) {
        // Insert 3 spaces instead of raw ASCII 9 tab so dittos maintain uniform separation and equal width across all apps
        let targetRange = selectedRange()
        if shouldChangeText(in: targetRange, replacementString: "   ") {
            replaceCharacters(in: targetRange, with: "   ")
            didChangeText()
        } else {
            insertText("   ", replacementRange: targetRange)
        }
    }

    // MARK: - DirectionaL1a Dittos Equal Width Banner
    @objc func wrapInDirectionalDittos(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        guard ns.length > 0 else { return }
        let lineRange = ns.lineRange(for: NSRange(location: max(0, min(sel.location, ns.length - 1)), length: 0))
        let lineText = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard !lineText.isEmpty else { return }

        let activeFont = font ?? NSFont.systemFont(ofSize: CGFloat(coordinator?.store.editorFontSize ?? 15.0))
        let targetWidth = (lineText as NSString).size(withAttributes: [.font: activeFont]).width

        // Measure actual font pixel width to find the exact pair count that balances the line
        var bestCount = 2
        var bestDiff = Double.infinity
        for count in 2...32 {
            let candidate = Array(repeating: "🔻🔻", count: count).joined(separator: "   ")
            let candidateWidth = (candidate as NSString).size(withAttributes: [.font: activeFont]).width
            let diff = abs(candidateWidth - targetWidth)
            if diff < bestDiff {
                bestDiff = diff
                bestCount = count
            }
        }

        let top = Array(repeating: "🔻🔻", count: bestCount).joined(separator: "   ")
        let bottom = Array(repeating: "🔺🔺", count: bestCount).joined(separator: "   ")
        let replacement = "\(top)\n\(lineText)\n\(bottom)\n"

        if shouldChangeText(in: lineRange, replacementString: replacement) {
            replaceCharacters(in: lineRange, with: replacement)
            didChangeText()
            let newEnd = lineRange.location + (replacement as NSString).length
            setSelectedRange(NSRange(location: newEnd, length: 0))
        }
    }

    // MARK: - Copy for Apple Notes & 1-Step Copy with Images
    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        guard sel.location != NSNotFound, sel.length > 0, sel.location + sel.length <= ns.length else {
            super.copy(sender)
            return
        }
        let copiedSlice = ns.substring(with: sel)
        let isSelectAll = sel.length >= max(1, ns.length - 1)
        if coordinator?.store.requestCopyWithImages(text: copiedSlice, isSelectAll: isSelectAll) == true {
            return
        }
        super.copy(sender)
    }

    @objc func copyForAppleNotes(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        let textToCopy: String
        let isSelectAll: Bool
        if sel.location != NSNotFound && sel.length > 0 && sel.location + sel.length <= ns.length {
            textToCopy = ns.substring(with: sel)
            isSelectAll = sel.length >= max(1, ns.length - 1)
        } else {
            textToCopy = string
            isSelectAll = true
        }
        if coordinator?.store.requestCopyWithImages(text: textToCopy, isSelectAll: isSelectAll) == true {
            return
        }
        // Expand any raw tabs to 3 spaces so Apple Notes never collapses tabs into 🔻🔻🔻🔻
        let cleanText = textToCopy.replacingOccurrences(of: "\t", with: "   ")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([cleanText as NSString])
    }

    func ensureFullLayoutAndFrame() {
        isEditable = true
        isSelectable = true
        guard let tc = textContainer, let lm = layoutManager else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let scrollContentSize = enclosingScrollView?.contentSize ?? .zero
        let minH = max(minSize.height, max(used.height + 40, scrollContentSize.height))
        var fr = frame
        var changed = false
        if scrollContentSize.width > 0 && abs(fr.size.width - scrollContentSize.width) > 1 {
            fr.size.width = scrollContentSize.width
            changed = true
        }
        if fr.size.height < minH {
            fr.size.height = minH
            changed = true
        }
        if changed {
            frame = fr
        }
        needsLayout = true
        needsDisplay = true
    }

    func clearSpellingUnderlines(for word: String) {
        let ns = string as NSString
        let len = ns.length
        guard len > 0, let lm = layoutManager else { return }
        var search = 0
        while search < len {
            let found = ns.range(of: word, options: [], range: NSRange(location: search, length: len - search))
            if found.location == NSNotFound { break }
            lm.removeTemporaryAttribute(.spellingState, forCharacterRange: found)
            search = found.location + max(1, found.length)
        }
    }

    // MARK: - Drag-and-Drop Screenshots & Images

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if RetinaImageSupport.pasteboardHasImage(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if RetinaImageSupport.pasteboardHasImage(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let images = RetinaImageSupport.extractImages(from: sender.draggingPasteboard)
        if !images.isEmpty {
            let pt = convert(sender.draggingLocation, from: nil)
            let dropIndex = max(0, min(characterIndexForInsertion(at: pt), (string as NSString).length))
            return insertPreparedImages(images, replacing: NSRange(location: dropIndex, length: 0))
        }
        return super.performDragOperation(sender)
    }

    // MARK: - Normalized Paste & Clipboard Image Paste

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) || item.action == #selector(pasteAsPlainText(_:)) {
            if RetinaImageSupport.pasteboardHasImage(NSPasteboard.general) {
                return true
            }
        }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any?) {
        performNormalizedPlainTextPaste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        performNormalizedPlainTextPaste(sender)
    }

    private func performNormalizedPlainTextPaste(_ sender: Any?) {
        let rawPaste = NSPasteboard.general.string(forType: .string)
        let hasPlainText = !(rawPaste ?? "").isEmpty
        let hasCopiedImageFile = ((NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []).contains(where: { RetinaImageSupport.isImageFileURL($0) })

        if (!hasPlainText || hasCopiedImageFile) && RetinaImageSupport.pasteboardHasImage(NSPasteboard.general) {
            let images = RetinaImageSupport.extractImages(from: NSPasteboard.general)
            if !images.isEmpty {
                let currentNS = string as NSString
                let rawSel = selectedRange()
                let clampedLoc = rawSel.location == NSNotFound
                    ? currentNS.length
                    : max(0, min(rawSel.location, currentNS.length))
                let clampedLen = rawSel.location == NSNotFound
                    ? 0
                    : max(0, min(rawSel.length, currentNS.length - clampedLoc))
                _ = insertPreparedImages(images, replacing: NSRange(location: clampedLoc, length: clampedLen))
                return
            }
        }

        guard let rawPaste else {
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
        let paragraph = UnifiedNoteTextView.createStandardParagraphStyle()

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

    private func insertPreparedImages(_ images: [RetinaImageSupport.PreparedPNG], replacing sel: NSRange) -> Bool {
        guard let store = coordinator?.store else { return false }
        var markers: [String] = []
        for item in images {
            if let saved = store.saveImageAttachment(
                pngData: item.pngData,
                filename: item.filename,
                pixelWidth: item.pixelWidth,
                pixelHeight: item.pixelHeight,
                exactUnixTimestamp: item.exactUnixTimestamp,
                base38TimestampTag: item.base38Tag
            ) {
                markers.append(saved.markerText)
            }
        }
        guard !markers.isEmpty else { return false }
        let insertion = markers.joined(separator: "\n")

        let currentNS = string as NSString
        let clampedLoc = max(0, min(sel.location, currentNS.length))
        let clampedLen = max(0, min(sel.length, currentNS.length - clampedLoc))
        let safeRange = NSRange(location: clampedLoc, length: clampedLen)

        guard shouldChangeText(in: safeRange, replacementString: insertion) else { return false }
        replaceCharacters(in: safeRange, with: insertion)
        didChangeText()

        let endLoc = min(safeRange.location + (insertion as NSString).length, (string as NSString).length)
        let cursorRange = NSRange(location: endLoc, length: 0)
        setSelectedRange(cursorRange)
        window?.makeFirstResponder(self)
        ensureFullLayoutAndFrame()
        scrollRangeToVisible(cursorRange)
        return true
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

    // MARK: - Red-Underlined & Grammar Quick Actions

    @objc func quickApplyExactSkipVowels(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellMenuPayload,
              let target = payload.replacement else { return }
        _ = coordinator?.store.addSkipVowelsRule(token: payload.word, normalized: target)
        clearSpellingUnderlines(for: payload.word)
        checkTextInDocument(nil)
        coordinator?.refreshCursorSpellTarget(on: self)
    }

    @objc func quickPromptSkipVowels(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellMenuPayload else { return }
        coordinator?.store.openSkipVowelsPrompt(
            token: payload.word,
            rangeLocation: payload.range.location,
            rangeLength: payload.range.length
        )
    }

    @objc func quickAppendII(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellMenuPayload else { return }
        applyTokenReplacement(payload: payload, newWord: payload.replacement ?? VerificationTagHelper.appendII(to: payload.word))
    }

    @objc func quickAppendIS5(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellMenuPayload else { return }
        applyTokenReplacement(payload: payload, newWord: payload.replacement ?? VerificationTagHelper.appendIS5(to: payload.word))
    }

    @objc func quickReplaceWithIS5(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellMenuPayload else { return }
        applyTokenReplacement(payload: payload, newWord: "is5")
    }

    @objc func quickLearnSpelling(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SpellMenuPayload else { return }
        coordinator?.store.applyLearnWord(token: payload.word)
        clearSpellingUnderlines(for: payload.word)
        checkTextInDocument(nil)
        coordinator?.refreshCursorSpellTarget(on: self)
    }

    private func applyTokenReplacement(payload: SpellMenuPayload, newWord: String) {
        let ns = string as NSString
        guard payload.range.location != NSNotFound,
              payload.range.location + payload.range.length <= ns.length,
              ns.substring(with: payload.range) == payload.word else {
            return
        }
        NSSpellChecker.shared.learnWord(newWord)
        if payload.word != newWord {
            guard shouldChangeText(in: payload.range, replacementString: newWord) else { return }
            replaceCharacters(in: payload.range, with: newWord)
            didChangeText()
        }
        let newRange = NSRange(location: payload.range.location, length: (newWord as NSString).length)
        layoutManager?.removeTemporaryAttribute(.spellingState, forCharacterRange: newRange)
        let cursorPos = min(payload.range.location + (newWord as NSString).length, (string as NSString).length)
        setSelectedRange(NSRange(location: cursorPos, length: 0))
        checkTextInDocument(nil)
        coordinator?.refreshCursorSpellTarget(on: self)
    }

    @objc func wrapBold(_ sender: Any?) { wrapSelection(prefix: "**", suffix: "**") }
    @objc func wrapItalic(_ sender: Any?) { wrapSelection(prefix: "*", suffix: "*") }
    @objc func wrapStrikethrough(_ sender: Any?) {
        let range = selectedRange()
        let ns = string as NSString
        if range.location != NSNotFound && range.length >= 4 && range.location + range.length <= ns.length {
            let current = ns.substring(with: range)
            if current.hasPrefix("~~") && current.hasSuffix("~~") {
                let unwrapped = String(current.dropFirst(2).dropLast(2))
                if shouldChangeText(in: range, replacementString: unwrapped) {
                    replaceCharacters(in: range, with: unwrapped)
                    didChangeText()
                    setSelectedRange(NSRange(location: range.location, length: (unwrapped as NSString).length))
                }
                return
            }
        }
        wrapSelection(prefix: "~~", suffix: "~~")
    }
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
