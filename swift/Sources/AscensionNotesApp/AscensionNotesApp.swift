import AscensionCore
import Foundation

#if canImport(SwiftUI)
import Combine
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private let notesGold = Color(red: 0.90, green: 0.64, blue: 0.08)

#if os(macOS)
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    var onWillTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        onWillTerminate?()
    }
}
#endif

@main
struct AscensionNotesApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var store = NotesStore()

    var body: some Scene {
        WindowGroup("Ascension Notes") {
            AscensionNotesRootView(store: store)
                #if os(macOS)
                .frame(minWidth: 920, minHeight: 580)
                .onAppear {
                    let currentStore = store
                    appDelegate.onWillTerminate = { [weak currentStore] in
                        currentStore?.save()
                    }
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 700)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    store.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .textFormatting) {
                Button("Expand / Zoom In") {
                    #if os(macOS)
                    if !NSApp.sendAction(#selector(AscensionNSTextView.expandTextSize(_:)), to: nil, from: nil) {
                        store.expandEditorFontSize()
                    }
                    #else
                    store.expandEditorFontSize()
                    #endif
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Expand (=)") {
                    #if os(macOS)
                    if !NSApp.sendAction(#selector(AscensionNSTextView.expandTextSize(_:)), to: nil, from: nil) {
                        store.expandEditorFontSize()
                    }
                    #else
                    store.expandEditorFontSize()
                    #endif
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Shrink / Fold Block") {
                    #if os(macOS)
                    if !NSApp.sendAction(#selector(AscensionNSTextView.shrinkTextSize(_:)), to: nil, from: nil) {
                        store.shrinkEditorFontSize()
                    }
                    #else
                    store.shrinkEditorFontSize()
                    #endif
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Text Size") {
                    store.resetEditorFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Ascension Notes Help") {
                    #if os(macOS)
                    openWindow(id: "help")
                    #else
                    store.showHelp = true
                    #endif
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        #if os(macOS)
        Window("Ascension Notes Help", id: "help") {
            HelpGuideView()
        }
        .defaultSize(width: 640, height: 540)
        #endif
    }
}

struct AscensionNotesRootView: View {
    @Bindable var store: NotesStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showCopiedToast: Bool = false
    @FocusState private var isFindFieldFocused: Bool
    @FocusState private var isInlineFindFocused: Bool
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isEditorFocused: Bool
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            foldersSidebar
        } content: {
            notesListColumn
        } detail: {
            noteCanvasDetail
        }
        .tint(notesGold)
        .inspector(isPresented: $store.showInspector) {
            axifInspectorDrawer
                .inspectorColumnWidth(min: 270, ideal: 310, max: 380)
        }
        .sheet(isPresented: $store.showHelp) {
            NavigationStack {
                HelpGuideView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { store.showHelp = false }
                        }
                    }
            }
        }
        .onReceive(clockTimer) { _ in
            store.refreshClock()
        }
        .onChange(of: store.sidebarFilter) { _, _ in
            store.selectedNoteID = store.filteredNotes.first?.id
        }
        .onChange(of: store.selectedNoteID) { _, _ in
            showCopiedToast = false
        }
    }

    // MARK: - Column 1: Folders Sidebar (Apple Notes Style)

    private var foldersSidebar: some View {
        List(selection: $store.sidebarFilter) {
            Section("Library") {
                sidebarRow(.all)
                sidebarRow(.pinned)
            }

            Section("Folders") {
                ForEach(NoteFolder.allCases) { folder in
                    sidebarRow(.folder(folder))
                }
            }

            Section("Jesus Clock (Base-38)") {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(notesGold)
                    Text(store.liveClockText)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Spacer()
                    Text("T0")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle("Auto-Cap / Autocorrect", isOn: $store.autoCapitalizeNewLines)
                    Divider()
                    Button("Ascension Notes Help") {
                        #if os(macOS)
                        openWindow(id: "help")
                        #else
                        store.showHelp = true
                        #endif
                    }
                    Button("Reset Sample Notes") {
                        store.resetSampleNotes()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func sidebarRow(_ filter: SidebarFilter) -> some View {
        HStack {
            Label(filter.title, systemImage: filter.systemImage)
            Spacer()
            Text("\(store.count(for: filter))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .tag(filter as SidebarFilter?)
    }

    // MARK: - Column 2: Searchable Notes List

    private var notesListColumn: some View {
        VStack(spacing: 0) {
            listSearchHeader
            Divider()

            if store.filteredNotes.isEmpty {
                ContentUnavailableView(
                    store.query.isEmpty ? "No Notes" : "No Matches",
                    systemImage: store.query.isEmpty ? "note.text" : "magnifyingglass",
                    description: Text(
                        store.query.isEmpty
                            ? "Click + to start a new Ascension Note."
                            : "No notes matched \"\(store.query)\" with current search options."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $store.selectedNoteID) {
                    ForEach(store.filteredNotes) { note in
                        noteRowCard(note)
                            .tag(note.id as UUID?)
                            .contextMenu {
                                Button {
                                    store.togglePin(note.id)
                                } label: {
                                    Label(
                                        note.isPinned ? "Unpin Note" : "Pin Note",
                                        systemImage: note.isPinned ? "pin.slash" : "pin"
                                    )
                                }
                                Divider()
                                Button(role: .destructive) {
                                    store.deleteNote(note.id)
                                } label: {
                                    Label("Delete Note", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: store.deleteNotes)
                }
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.insetGrouped)
                #endif
            }
        }
        .navigationTitle((store.sidebarFilter ?? .all).title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.createNewNote()
                    isTitleFocused = true
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Note (Cmd+N)")
            }
        }
    }

    private var listSearchHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes & hidden MUNSCs...", text: $store.query)
                    .textFieldStyle(.plain)
                    .focused($isFindFieldFocused)
                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                searchOptionPill(title: "Aa", help: "Case-Sensitive (like Xcode)", isOn: $store.caseSensitive)
                searchOptionPill(title: "W", help: "Whole Word", isOn: $store.wholeWord)
                searchOptionPill(title: ".*", help: "Regular Expression", isOn: $store.useRegex)

                Spacer()

                Picker("Scope", selection: $store.searchLayer) {
                    Text("Dual AXIF").tag(SearchLayer.dual)
                    Text("Clean").tag(SearchLayer.normalized)
                    Text("Raw").tag(SearchLayer.raw)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            if let errorMsg = store.searchErrorMessage {
                Text(errorMsg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func searchOptionPill(title: String, help: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isOn.wrappedValue ? notesGold.opacity(0.24) : Color.secondary.opacity(0.12))
                .foregroundStyle(isOn.wrappedValue ? notesGold : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn.wrappedValue ? notesGold.opacity(0.7) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func noteRowCard(_ note: StoredNote) -> some View {
        let hits = store.searchMatches(for: note)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(notesGold)
                }
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if !store.query.isEmpty && !hits.isEmpty {
                    Text("\(hits.count)")
                        .font(.caption2.monospacedDigit().bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(notesGold.opacity(0.22))
                        .foregroundStyle(notesGold)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                Text(note.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(note.previewBody(normalized: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(note.ownerAcode9)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let doc = note.compiledDocument(), doc.axif.munscCount > 0 {
                    Text("• \(doc.axif.munscCount) AXIF")
                        .font(.caption2)
                        .foregroundStyle(notesGold)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Column 3: Apple Notes Writing & Clean View Canvas

    @ViewBuilder
    private var noteCanvasDetail: some View {
        if let note = store.selectedNote {
            VStack(spacing: 0) {
                if store.showFindBar {
                    inlineNoteFindStrip
                    Divider()
                }

                // Centered Apple Notes-style date banner
                HStack {
                    Spacer()
                    Text(note.updatedAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.bottom, 4)

                if store.viewMode == .edit {
                    #if os(macOS)
                    UnifiedNoteTextView(
                        store: store,
                        noteID: note.id,
                        text: note.rawText,
                        fontSize: store.editorFontSize,
                        autoCapitalizeNewLines: store.autoCapitalizeNewLines,
                        foldedBlocks: note.foldedBlocks
                    )
                    #else
                    let titleBinding = Binding(
                        get: { store.selectedNote?.derivedTitle ?? "" },
                        set: { store.updateSelectedTitle($0) }
                    )
                    TextField("Title", text: titleBinding)
                        .font(.system(size: store.editorFontSize + 7, weight: .bold))
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .autocorrectionDisabled(!store.autoCapitalizeNewLines)
                        .textInputAutocapitalization(store.autoCapitalizeNewLines ? .sentences : .never)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    let bodyBinding = Binding(
                        get: { store.selectedNote?.derivedBody ?? "" },
                        set: { store.updateSelectedBody($0) }
                    )
                    TextEditor(text: bodyBinding)
                        .font(.system(size: store.editorFontSize))
                        .lineSpacing(5)
                        .autocorrectionDisabled(!store.autoCapitalizeNewLines)
                        .textInputAutocapitalization(store.autoCapitalizeNewLines ? .sentences : .never)
                        .focused($isEditorFocused)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    #endif

                    if !store.query.isEmpty && !store.selectedSearchMatches.isEmpty {
                        searchMatchesFooter
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }
                } else {
                    let titleBinding = Binding(
                        get: { store.selectedNote?.derivedTitle ?? "" },
                        set: { store.updateSelectedTitle($0) }
                    )
                    TextField("Title", text: titleBinding)
                        .font(.system(size: store.editorFontSize + 7, weight: .bold))
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            let cleanBodyIssues = store.spellcheckCleanView ? cleanViewSpellIssues(for: note) : []

                            Text(highlightedCleanBodyText(for: note, spellIssues: cleanBodyIssues))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .lineSpacing(6)
                                .onTapGesture {
                                    store.viewMode = .edit
                                    isEditorFocused = true
                                }

                            if store.spellcheckCleanView && !cleanBodyIssues.isEmpty {
                                cleanViewSpellcheckTray(issues: cleanBodyIssues, note: note)
                            }

                            if !store.query.isEmpty && !store.selectedSearchMatches.isEmpty {
                                searchMatchesFooter
                            }

                            Spacer(minLength: 280)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                    }
                }

                // Bottom clickable AXIF bar so Ascenders can inspect AXIF data with 1 click
                Divider()
                HStack(spacing: 10) {
                    Text(note.ownerAcode9)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(notesGold)
                    if let doc = note.compiledDocument(urlSafeDash: store.urlSafeDash) {
                        Text("• \(doc.axif.munscCount) AXIF token(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• Clock \(doc.axif.jesusClock)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.showInspector.toggle()
                    } label: {
                        Label(
                            store.showInspector ? "Hide AXIF" : "View AXIF Data",
                            systemImage: "info.circle"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.05))
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Mode", selection: $store.viewMode) {
                        ForEach(NotesStore.ViewLayerMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .keyboardShortcut("e", modifiers: .command)
                    .help("Switch Edit / Clean View (Cmd+E)")

                    Toggle(isOn: $store.autoCapitalizeNewLines) {
                        Label("Auto-Cap", systemImage: "textformat.size.larger")
                    }
                    .help("Toggle auto-capitalization & autocorrect (keep OFF for pure lowercase/MLeet)")

                    Toggle(isOn: $store.spellcheckCleanView) {
                        Label("Spellcheck", systemImage: "text.badge.checkmark")
                    }
                    .help("Spellcheck Clean View so Ascenders see typos needing fixes")

                    Button {
                        store.togglePin(note.id)
                    } label: {
                        Label(
                            note.isPinned ? "Unpin" : "Pin",
                            systemImage: note.isPinned ? "pin.fill" : "pin"
                        )
                    }

                    Button {
                        withAnimation {
                            store.showFindBar.toggle()
                        }
                        if store.showFindBar {
                            isInlineFindFocused = true
                        }
                    } label: {
                        Label("Find", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Find in Note (Cmd+F)")

                    Button {
                        store.showInspector.toggle()
                    } label: {
                        Label("AXIF", systemImage: "info.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .keyboardShortcut("i", modifiers: .command)
                    .help("Show AXIF & Acode9 Inspector (Cmd+I)")

                    Button {
                        #if os(macOS)
                        openWindow(id: "help")
                        #else
                        store.showHelp = true
                        #endif
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("Ascension Notes Help (Cmd+?)")
                }
            }
        } else {
            ContentUnavailableView(
                "Select a Note",
                systemImage: "note.text",
                description: Text("Choose a note on the left or press Cmd+N to create one.")
            )
        }
    }

    private var inlineNoteFindStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(notesGold)
            TextField("Find in notes (e.g. NormA, Norm4, Norma4)...", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .focused($isInlineFindFocused)
            searchOptionPill(title: "Aa", help: "Case-Sensitive", isOn: $store.caseSensitive)
            searchOptionPill(title: "W", help: "Whole Word", isOn: $store.wholeWord)
            searchOptionPill(title: ".*", help: "Regex", isOn: $store.useRegex)

            Text("\(store.selectedSearchMatches.count) hit(s)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                withAnimation {
                    store.showFindBar = false
                }
            } label: {
                Text("Done")
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private var searchMatchesFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("AXIF Search Matches (\(store.selectedSearchMatches.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(store.selectedSearchMatches) { hit in
                HStack(spacing: 8) {
                    Text("L\(hit.lineNumber):C\(hit.column)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text(hit.matchedText)
                        .font(.caption.monospaced().bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(notesGold.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    if let entry = hit.axifEntry {
                        Text("→ \(entry.normalizedForm) (\(entry.munscRule))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.top, 8)
    }

    private func cleanViewBodySlice(for note: StoredNote) -> (bodyClean: String, bodyStartOffset: Int) {
        guard let doc = note.compiledDocument(urlSafeDash: store.urlSafeDash) else {
            return (note.derivedBody, note.derivedTitle.count + 1)
        }
        let fullClean = doc.render(normalized: true)
        guard let firstNewline = fullClean.firstIndex(of: "\n") else {
            return ("", fullClean.count)
        }
        let bodyStartIdx = fullClean.index(after: firstNewline)
        let bodyClean = String(fullClean[bodyStartIdx...])
        let bodyStartOffset = fullClean.distance(from: fullClean.startIndex, to: bodyStartIdx)
        return (bodyClean, bodyStartOffset)
    }

    private func cleanViewSpellIssues(for note: StoredNote) -> [SpellcheckIssue] {
        _ = store.spellcheckRevision
        let (bodyClean, _) = cleanViewBodySlice(for: note)
        return SpellcheckHelper.findIssues(in: bodyClean)
    }

    private func cleanViewSpellcheckTray(issues: [SpellcheckIssue], note: StoredNote) -> some View {
        let (_, bodyStartOffset) = cleanViewBodySlice(for: note)
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Label("Clean View Spellcheck (\(issues.count) flagged)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                Text("Click a suggestion to fix or Learn into Apple Dictionary")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(issues) { issue in
                HStack(spacing: 8) {
                    Text(issue.word)
                        .font(.caption.monospaced().bold())
                        .underline(true, color: .red)
                        .foregroundStyle(.red)

                    if issue.guesses.isEmpty {
                        Text("(no guess)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(issue.guesses, id: \.self) { guess in
                            Button(guess) {
                                store.replaceNormalizedSpan(
                                    normOffset: bodyStartOffset + issue.charOffset,
                                    normEnd: bodyStartOffset + issue.charEnd,
                                    with: guess
                                )
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                        }
                    }

                    Spacer()

                    Button("Learn") {
                        store.learnSpellcheckWord(issue.word)
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.top, 6)
    }

    private func highlightedCleanBodyText(for note: StoredNote, spellIssues: [SpellcheckIssue]) -> AttributedString {
        let (bodyClean, bodyStartOffset) = cleanViewBodySlice(for: note)

        var attributed = AttributedString(bodyClean)
        attributed.font = .system(size: store.editorFontSize)

        for issue in spellIssues {
            guard issue.charOffset >= 0,
                  issue.charEnd <= bodyClean.count,
                  issue.charOffset < issue.charEnd else { continue }
            let startIdx = bodyClean.index(bodyClean.startIndex, offsetBy: issue.charOffset)
            let endIdx = bodyClean.index(bodyClean.startIndex, offsetBy: issue.charEnd)
            if let attrRange = Range(startIdx..<endIdx, in: attributed) {
                attributed[attrRange].underlineStyle = Text.LineStyle(pattern: .dot, color: .red)
            }
        }

        for hit in store.searchMatches(for: note) {
            let relStart = hit.normalizedOffset - bodyStartOffset
            let relEnd = hit.normalizedEnd - bodyStartOffset
            guard relStart >= 0, relEnd <= bodyClean.count, relStart < relEnd else { continue }
            let startIdx = bodyClean.index(bodyClean.startIndex, offsetBy: relStart)
            let endIdx = bodyClean.index(bodyClean.startIndex, offsetBy: relEnd)
            if let attrRange = Range(startIdx..<endIdx, in: attributed) {
                attributed[attrRange].backgroundColor = notesGold.opacity(0.38)
            }
        }
        return attributed
    }

    // MARK: - Collapsible Right Drawer: AXIF & Acode9 Inspector

    private var axifInspectorDrawer: some View {
        List {
            if let note = store.selectedNote {
                Section("Note Filing & Owner Acode9") {
                    Picker(
                        "Folder",
                        selection: Binding(
                            get: { note.folder },
                            set: { store.updateSelectedFolder($0) }
                        )
                    ) {
                        ForEach(NoteFolder.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }

                    HStack {
                        TextField(
                            "Acode9",
                            text: Binding(
                                get: { note.ownerAcode9 },
                                set: { store.updateSelectedOwnerAcode9($0) }
                            )
                        )
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                        Toggle("-", isOn: $store.urlSafeDash)
                            .toggleStyle(.button)
                            .help("Toggle Caret ^ / Dash - URL-safe mode")
                    }

                    let validation = Acode9.validate(note.ownerAcode9, strict: true, allowDash: true)
                    Label(
                        validation.valid ? "Valid good1a Acode9" : (validation.reasons.first ?? "Check Acode9"),
                        systemImage: validation.valid ? "checkmark.seal.fill" : "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(validation.valid ? .green : .orange)
                }

                if let doc = store.selectedDocument {
                    Section("AXIF Metadata Layer") {
                        LabeledContent("Version", value: doc.axif.version)
                        LabeledContent("Jesus Clock", value: doc.axif.jesusClock)
                        LabeledContent("Hidden MUNSCs", value: "\(doc.axif.munscCount)")

                        Button {
                            if let json = try? doc.axif.toJSON(prettyPrinted: true) {
                                copyToClipboard(json)
                                showCopiedToast = true
                            }
                        } label: {
                            Label(
                                showCopiedToast ? "Copied AXIF JSON!" : "Copy Shareable AXIF JSON",
                                systemImage: showCopiedToast ? "checkmark" : "doc.on.doc"
                            )
                        }
                    }

                    Section("Indexed MUNSC Tokens") {
                        if doc.axif.entries.isEmpty {
                            Text("No MUNSC tokens detected in this note yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(doc.axif.entries) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(entry.token)
                                            .font(.system(.subheadline, design: .monospaced).bold())
                                        Text("→")
                                            .foregroundStyle(.secondary)
                                        Text(entry.normalizedForm)
                                        Spacer()
                                        Text("@\(entry.offset)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry.munscRule)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("1s Cadence Acode9 Pool") {
                    Button("Mint Fresh Batch") {
                        store.generateNextPool()
                    }
                    ForEach(store.rollingPool) { entry in
                        HStack {
                            Text(entry.acode9)
                                .font(.caption.monospaced())
                            Spacer()
                            Button("Assign") {
                                store.updateSelectedOwnerAcode9(entry.acode9)
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Local Storage & Backup") {
                    Text(store.storageFolderPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("AXIF Inspector")
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
#else
@main
struct AscensionNotesCLIPlaceholder {
    static func main() {
        print("AscensionNotesApp SwiftUI UI requires an Apple platform with SwiftUI.")
    }
}
#endif
