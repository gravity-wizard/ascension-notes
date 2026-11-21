import AscensionCore
import Foundation

#if canImport(SwiftUI)
import Combine
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
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

@MainActor
func exportSelectedNoteAsMarkdownFile(store: NotesStore) {
    guard let note = store.selectedNote,
          let markdown = store.exportMarkdown(for: note) else {
        NSSound.beep()
        return
    }

    let savePanel = NSSavePanel()
    savePanel.title = "Export Note as Markdown"
    savePanel.prompt = "Export"
    if let mdType = UTType(filenameExtension: "md") {
        savePanel.allowedContentTypes = [mdType, .plainText]
    } else {
        savePanel.allowedContentTypes = [.plainText]
    }
    savePanel.canCreateDirectories = true
    savePanel.isExtensionHidden = false

    let candidateTitle = note.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let sanitized = candidateTitle
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let baseName = sanitized.isEmpty ? note.ownerAcode9 : "\(sanitized)"
    savePanel.nameFieldStringValue = "\(baseName).md"

    savePanel.begin { response in
        if response == .OK, let url = savePanel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save markdown file: \(error)")
            }
        }
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

    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    var body: some Scene {
        WindowGroup("Ascension Notes") {
            AscensionNotesRootView(store: store)
                #if os(macOS)
                .frame(minWidth: 940, minHeight: 600)
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
        .defaultSize(width: 1140, height: 720)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    store.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    store.save()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("Export Note as Markdown...") {
                    #if os(macOS)
                    exportSelectedNoteAsMarkdownFile(store: store)
                    #endif
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(store.selectedNote == nil)

                Button("Copy Note as Markdown") {
                    if let note = store.selectedNote, let md = store.exportMarkdown(for: note) {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                        #endif
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(store.selectedNote == nil)
            }
            CommandGroup(after: .textFormatting) {
                Button("Grow Selected Text") {
                    #if os(macOS)
                    _ = NSApp.sendAction(#selector(AscensionNSTextView.growSelectedText(_:)), to: nil, from: nil)
                    #endif
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Grow Selected Text (=)") {
                    #if os(macOS)
                    _ = NSApp.sendAction(#selector(AscensionNSTextView.growSelectedText(_:)), to: nil, from: nil)
                    #endif
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Shrink Selected Text") {
                    #if os(macOS)
                    _ = NSApp.sendAction(#selector(AscensionNSTextView.shrinkSelectedText(_:)), to: nil, from: nil)
                    #endif
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Selected Text Size") {
                    #if os(macOS)
                    _ = NSApp.sendAction(#selector(AscensionNSTextView.resetSelectedTextSize(_:)), to: nil, from: nil)
                    #endif
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Fold Selected Block") {
                    #if os(macOS)
                    _ = NSApp.sendAction(#selector(AscensionNSTextView.foldSelectedBlock(_:)), to: nil, from: nil)
                    #endif
                }
                .keyboardShortcut("[", modifiers: [.command, .option])

                Button("Unfold Block / All") {
                    #if os(macOS)
                    _ = NSApp.sendAction(#selector(AscensionNSTextView.unfoldBlockAtCursor(_:)), to: nil, from: nil)
                    #endif
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
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
    @State private var copiedFeedbackLabel: String?
    @State private var copiedClockToast: Bool = false
    @State private var newRuleToken: String = ""
    @State private var newRuleNormalized: String = ""
    @State private var newRuleDescription: String = ""
    @State private var showSyncFolderImporter: Bool = false
    @State private var syncFolderError: String?
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
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
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
        .sheet(isPresented: $store.showA3odex) {
            A3odexSheetView(store: store)
        }
        .sheet(isPresented: $store.showImportAXIF) {
            ImportAXIFSheetView(store: store)
        }
        .sheet(item: $store.skipVowelsPrompt) { request in
            SkipVowelsConfirmSheet(store: store, request: request)
        }
        .sheet(item: $store.activeLightboxRequest) { request in
            RetinaLightboxSheet(store: store, request: request)
        }
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(
            isPresented: $showSyncFolderImporter,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                syncFolderError = nil
                store.setSyncFolder(url)
            case .failure(let error):
                syncFolderError = error.localizedDescription
            }
        }
        #endif
        .onReceive(clockTimer) { _ in
            store.refreshClock()
        }
        .onChange(of: store.selectedNoteID) { _, _ in
            copiedFeedbackLabel = nil
            store.cursorSpellTarget = nil
        }
        .onChange(of: store.viewMode) { _, _ in
            store.cursorSpellTarget = nil
        }
    }

    // MARK: - Column 1: Button-Driven Folders Sidebar (100% Clickable on macOS & iOS)

    private var foldersSidebar: some View {
        List {
            Section("Library") {
                sidebarButtonRow(.all)
                sidebarButtonRow(.pinned)
            }

            Section("Folders") {
                ForEach(NoteFolder.allCases) { folder in
                    sidebarButtonRow(.folder(folder))
                }
            }

            Section("Jesus Clock (Base-38)") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: store.clockIsPaused ? "pause.circle.fill" : "clock")
                            .foregroundStyle(store.clockIsPaused ? .orange : notesGold)
                        Text(store.liveClockText)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            copyToClipboard(store.liveClockText)
                            copiedClockToast = true
                        } label: {
                            Image(systemName: copiedClockToast ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy Base-38 Jesus Clock")
                    }
                    if store.clockIsPaused {
                        Text("Paused to skip 666 / filter (raw: \(store.rawClockText))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Vault: \(store.unusedAcodeVault.count) unused Acode9 stored")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle("Auto-Cap / Autocorrect", isOn: $store.autoCapitalizeNewLines)
                    Toggle("URL-Safe (- and _)", isOn: $store.urlSafeDash)
                    Divider()
                    Button("Run \"Where's Norma?\" Aa Demo") {
                        store.runWheresNormaDemo()
                    }
                    Button("Codex / A3odex (4-Tier)...") {
                        store.showA3odex = true
                    }
                    Button("Import Shared AXIF...") {
                        store.showImportAXIF = true
                    }
                    Button("Sync Now / Reload") {
                        store.reloadFromSyncFolder()
                    }
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

    private func sidebarButtonRow(_ filter: SidebarFilter) -> some View {
        let isSelected = (store.activeSidebarFilter == filter)
        return Button {
            store.selectSidebarFilter(filter)
            copiedClockToast = false
        } label: {
            HStack {
                Label(filter.title, systemImage: filter.systemImage)
                    .foregroundStyle(isSelected ? notesGold : .primary)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                Text("\(store.count(for: filter))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? notesGold : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? notesGold.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Column 2: Searchable Notes List

    private var notesListColumn: some View {
        VStack(spacing: 0) {
            listSearchHeader
            Divider()

            if store.filteredNotes.isEmpty {
                ContentUnavailableView(
                    store.query.isEmpty ? "No Notes in \(store.activeSidebarFilter.title)" : "No Matches",
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
                            .contentShape(Rectangle())
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
        .navigationTitle(store.activeSidebarFilter.title)
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
                Text(note.previewBody(normalized: true, rules: store.customRules))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(note.ownerAcode9)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let doc = note.compiledDocument(rules: store.customRules), doc.axif.munscCount > 0 {
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

                // Centered Apple Notes-style date + folder badge
                HStack(spacing: 8) {
                    Spacer()
                    Text(note.folder.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(notesGold.opacity(0.15))
                        .foregroundStyle(notesGold)
                        .clipShape(Capsule())
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
                        defaultFontSize: store.editorFontSize,
                        autoCapitalizeNewLines: store.autoCapitalizeNewLines,
                        foldedBlocks: note.foldedBlocks,
                        fontSpans: note.fontSpans
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

                    if !note.attachments.isEmpty {
                        Divider()
                        NoteAttachmentsGalleryView(store: store, note: note)
                    }

                    if !store.query.isEmpty && !store.selectedSearchMatches.isEmpty {
                        searchMatchesFooter
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }

                    if let target = store.cursorSpellTarget, target.noteID == note.id {
                        Divider()
                        cursorSpellActionStrip(target: target)
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
                            let (bodyClean, _) = cleanViewBodySlice(for: note)
                            let cleanLayout = CleanViewAttachmentLayout.buildSegments(
                                bodyClean: bodyClean,
                                attachments: note.attachments
                            )

                            ForEach(cleanLayout.segments) { segment in
                                switch segment {
                                case .text(_, let rangeOffset, let rangeEnd):
                                    let attrSlice = highlightedCleanBodyText(
                                        for: note,
                                        spellIssues: cleanBodyIssues,
                                        rangeOffset: rangeOffset,
                                        rangeEnd: rangeEnd
                                    )
                                    if !attrSlice.characters.isEmpty {
                                        Text(attrSlice)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                            .lineSpacing(6)
                                            .onTapGesture {
                                                store.viewMode = .edit
                                                isEditorFocused = true
                                            }
                                    }
                                case .attachment(_, let attachment):
                                    CrispAttachmentImageView(
                                        store: store,
                                        noteID: note.id,
                                        attachment: attachment,
                                        maxDisplayHeight: nil
                                    )
                                }
                            }

                            if !cleanLayout.unreferenced.isEmpty {
                                Divider()
                                Text("Attached Screenshots")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(cleanLayout.unreferenced) { attachment in
                                    CrispAttachmentImageView(
                                        store: store,
                                        noteID: note.id,
                                        attachment: attachment,
                                        maxDisplayHeight: nil
                                    )
                                }
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

                // Bottom selectable Jesus Clock & clickable View AXIF Data bar
                Divider()
                HStack(spacing: 10) {
                    Text(note.ownerAcode9)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(notesGold)
                        .textSelection(.enabled)
                    if let doc = note.compiledDocument(urlSafeDash: store.urlSafeDash, rules: store.customRules) {
                        Text("• \(doc.axif.munscCount) AXIF token(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("• Clock:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.liveClockText)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(store.clockIsPaused ? .orange : .primary)
                            .textSelection(.enabled)
                        if store.clockIsPaused {
                            Text("(PAUSED)")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                        }
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
                        store.showA3odex = true
                    } label: {
                        Label("A3odex", systemImage: "books.vertical")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Open 4-Tier A3odex Codex & \"Where's Norma?\" Aa Demo")

                    Menu {
                        Button {
                            #if os(macOS)
                            exportSelectedNoteAsMarkdownFile(store: store)
                            #endif
                        } label: {
                            Label("Export Note as Markdown (.md)...", systemImage: "arrow.down.doc")
                        }

                        Button {
                            if let md = store.exportMarkdown(for: note) {
                                copyToClipboard(md)
                                copiedFeedbackLabel = "Copied Note as Markdown!"
                            }
                        } label: {
                            Label("Copy Note as Markdown", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button {
                            if let footerText = store.exportCleanWithAXIFFooter(for: note) {
                                copyToClipboard(footerText)
                                copiedFeedbackLabel = "Copied Clean + AXIF Footer!"
                            }
                        } label: {
                            Label("Copy Clean + AXIF Footer", systemImage: "doc.text.fill")
                        }

                        Button {
                            if let bbcode = store.exportSlogBogBBCode(for: note) {
                                copyToClipboard(bbcode)
                                copiedFeedbackLabel = "Copied SlogBog phpBBog Post!"
                            }
                        } label: {
                            Label("Copy SlogBog phpBBog Post", systemImage: "quote.bubble")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Export Note as Markdown (.md) or Copy Shareable Formats (Cmd+Shift+E)")

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
        guard let doc = note.compiledDocument(urlSafeDash: store.urlSafeDash, rules: store.customRules) else {
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

    private func cursorSpellActionStrip(target: CursorSpellTarget) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(target.word)
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((target.isGrammarIs ? Color.blue : Color.red).opacity(0.14))
                    .foregroundStyle(target.isGrammarIs ? .blue : .red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if target.isGrammarIs {
                    Button {
                        store.applyAppendIS5(
                            token: target.word,
                            location: target.rangeLocation,
                            length: target.rangeLength
                        )
                    } label: {
                        Label("Replace \"\(target.word)\" → \"is5\" (No Grammar Squiggle)", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(notesGold)
                    .controlSize(.small)

                    Button {
                        store.applyAppendII(
                            token: target.word,
                            location: target.rangeLocation,
                            length: target.rangeLength
                        )
                    } label: {
                        Text("Append \"ii\" → \(VerificationTagHelper.appendII(to: target.word))")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    if let suggestion = target.skipVowelsSuggestion, target.skipVowelsIsExact {
                        Button {
                            _ = store.addSkipVowelsRule(token: target.word, normalized: suggestion)
                        } label: {
                            Label("Skip Vowels: → \"\(suggestion)\"", systemImage: "text.badge.checkmark")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(notesGold)
                        .controlSize(.small)
                    }

                    Button {
                        store.openSkipVowelsPrompt(
                            token: target.word,
                            rangeLocation: target.rangeLocation,
                            rangeLength: target.rangeLength
                        )
                    } label: {
                        Label(
                            target.skipVowelsSuggestion != nil
                                ? "Skip Vowels Rule..."
                                : "Verify \"Skip Vowels\"...",
                            systemImage: "slider.horizontal.3"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    let iiTarget = VerificationTagHelper.appendII(to: target.word)
                    Button {
                        store.applyAppendII(
                            token: target.word,
                            location: target.rangeLocation,
                            length: target.rangeLength
                        )
                    } label: {
                        Text(iiTarget == target.word ? "Verify \"\(target.word)\" (ii)" : "Append \"ii\" → \(iiTarget)")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    let is5Target = VerificationTagHelper.appendIS5(to: target.word)
                    Button {
                        store.applyAppendIS5(
                            token: target.word,
                            location: target.rangeLocation,
                            length: target.rangeLength
                        )
                    } label: {
                        Text("Append \"is5\" → \(is5Target)")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        store.applyLearnWord(token: target.word)
                    } label: {
                        Text("Learn \"\(target.word)\"")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    ForEach(target.guesses.prefix(2), id: \.self) { guess in
                        Button(guess) {
                            store.applyReplaceSpan(
                                location: target.rangeLocation,
                                length: target.rangeLength,
                                with: guess,
                                learnWord: nil
                            )
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color.secondary.opacity(0.06))
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
                Text("Click a suggestion to fix, add Skip Vowels rule, or Learn")
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

                    Button("Skip Vowels...") {
                        store.openSkipVowelsPrompt(
                            token: issue.word,
                            rangeLocation: bodyStartOffset + issue.charOffset,
                            rangeLength: max(0, issue.charEnd - issue.charOffset)
                        )
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)

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

    private func highlightedCleanBodyText(
        for note: StoredNote,
        spellIssues: [SpellcheckIssue],
        rangeOffset: Int? = nil,
        rangeEnd: Int? = nil
    ) -> AttributedString {
        let (bodyClean, bodyStartOffset) = cleanViewBodySlice(for: note)
        let sliceStartOffset = max(0, min(rangeOffset ?? 0, bodyClean.count))
        let sliceEndOffset = max(sliceStartOffset, min(rangeEnd ?? bodyClean.count, bodyClean.count))

        let sliceStartIdx = bodyClean.index(bodyClean.startIndex, offsetBy: sliceStartOffset)
        let sliceEndIdx = bodyClean.index(bodyClean.startIndex, offsetBy: sliceEndOffset)
        let sliceText = String(bodyClean[sliceStartIdx..<sliceEndIdx])

        var attributed = AttributedString(sliceText)
        attributed.font = .system(size: store.editorFontSize)

        for issue in spellIssues {
            let ovStart = max(issue.charOffset, sliceStartOffset)
            let ovEnd = min(issue.charEnd, sliceEndOffset)
            guard ovStart < ovEnd else { continue }
            let relS = ovStart - sliceStartOffset
            let relE = ovEnd - sliceStartOffset
            let startIdx = sliceText.index(sliceText.startIndex, offsetBy: relS)
            let endIdx = sliceText.index(sliceText.startIndex, offsetBy: relE)
            if let attrRange = Range(startIdx..<endIdx, in: attributed) {
                attributed[attrRange].underlineStyle = Text.LineStyle(pattern: .dot, color: .red)
            }
        }

        for hit in store.searchMatches(for: note) {
            let relStart = hit.normalizedOffset - bodyStartOffset
            let relEnd = hit.normalizedEnd - bodyStartOffset
            let ovStart = max(relStart, sliceStartOffset)
            let ovEnd = min(relEnd, sliceEndOffset)
            guard ovStart < ovEnd else { continue }
            let localS = ovStart - sliceStartOffset
            let localE = ovEnd - sliceStartOffset
            let startIdx = sliceText.index(sliceText.startIndex, offsetBy: localS)
            let endIdx = sliceText.index(sliceText.startIndex, offsetBy: localE)
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

                        Toggle("-/_", isOn: $store.urlSafeDash)
                            .toggleStyle(.button)
                            .help("Use URL-safe '-' (for ^) and '_' (for |)")
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
                    Section("AXIF Metadata & Share") {
                        LabeledContent("Version", value: doc.axif.version)
                        HStack {
                            Text("Jesus Clock")
                            Spacer()
                            Text(store.liveClockText)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        LabeledContent("Hidden MUNSCs", value: "\(doc.axif.munscCount)")

                        Button {
                            #if os(macOS)
                            exportSelectedNoteAsMarkdownFile(store: store)
                            #endif
                        } label: {
                            Label("Export Note as Markdown...", systemImage: "arrow.down.doc")
                        }

                        Button {
                            if let md = store.exportMarkdown(for: note) {
                                copyToClipboard(md)
                                copiedFeedbackLabel = "Copied Note as Markdown!"
                            }
                        } label: {
                            Label("Copy Note as Markdown", systemImage: "doc.on.doc")
                        }

                        Button {
                            if let footerText = store.exportCleanWithAXIFFooter(for: note) {
                                copyToClipboard(footerText)
                                copiedFeedbackLabel = "Copied Clean + AXIF Footer!"
                            }
                        } label: {
                            Label("Copy Clean + AXIF Footer", systemImage: "doc.text.fill")
                        }

                        Button {
                            if let bbcode = store.exportSlogBogBBCode(for: note) {
                                copyToClipboard(bbcode)
                                copiedFeedbackLabel = "Copied SlogBog phpBBog Post!"
                            }
                        } label: {
                            Label("Copy SlogBog phpBBog Post", systemImage: "quote.bubble")
                        }

                        Button {
                            if let json = try? doc.axif.toJSON(prettyPrinted: true) {
                                copyToClipboard(json)
                                copiedFeedbackLabel = "Copied Shareable AXIF JSON!"
                            }
                        } label: {
                            Label("Copy Shareable AXIF JSON", systemImage: "doc.on.doc")
                        }

                        Button {
                            store.showImportAXIF = true
                        } label: {
                            Label("Import Shared AXIF Bundle...", systemImage: "square.and.arrow.down")
                        }

                        if let feedback = copiedFeedbackLabel {
                            Label(feedback, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
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
            }

            Section("Custom MUNSC Rules (\(store.customRules.count))") {
                if store.customRules.isEmpty {
                    Text("No custom MUNSC rules yet. Built-ins handle NormA, Norm4, Norma4, and leet patterns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.customRules) { rule in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(rule.pattern)
                                        .font(.system(.caption, design: .monospaced).bold())
                                    Text("→")
                                        .foregroundStyle(.secondary)
                                    Text(rule.replacement)
                                        .font(.caption.weight(.semibold))
                                }
                                if !rule.description.isEmpty {
                                    Text(rule.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                store.deleteCustomRule(name: rule.name)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete custom rule \(rule.pattern)")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Add Custom Rule")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        TextField("Raw Token (e.g. NormA)", text: $newRuleToken)
                            .font(.system(.caption, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        Text("→")
                            .foregroundStyle(.secondary)
                        TextField("Clean Word (e.g. Norma)", text: $newRuleNormalized)
                            .font(.caption)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField("Description (optional)", text: $newRuleDescription)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if store.addCustomRule(
                            token: newRuleToken,
                            normalized: newRuleNormalized,
                            description: newRuleDescription
                        ) {
                            newRuleToken = ""
                            newRuleNormalized = ""
                            newRuleDescription = ""
                        }
                    } label: {
                        Label("+ Add MUNSC Rule", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        newRuleToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || newRuleNormalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || newRuleToken.trimmingCharacters(in: .whitespacesAndNewlines)
                                == newRuleNormalized.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .padding(.vertical, 4)
            }

            Section("Codex / A3odex & Demo") {
                Button {
                    store.runWheresNormaDemo()
                } label: {
                    Label("Run \"Where's Norma?\" Aa Demo", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.showA3odex = true
                } label: {
                    Label("Browse A3odex (4-Tier)", systemImage: "books.vertical")
                }

                if store.selectedNote == nil {
                    Button {
                        store.showImportAXIF = true
                    } label: {
                        Label("Import Shared AXIF Bundle...", systemImage: "square.and.arrow.down")
                    }
                }
            }

            Section("Stored Unused Acodes Vault (\(store.unusedAcodeVault.count))") {
                HStack {
                    Button("Harvest +12") {
                        store.harvestUnusedAcodes(count: 12)
                    }
                    Spacer()
                    Button("Claim & Assign") {
                        let code = store.claimUnusedAcode()
                        store.updateSelectedOwnerAcode9(code)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedNote == nil)
                }
                ForEach(store.unusedAcodeVault.prefix(6)) { entry in
                    HStack {
                        Text(entry.acode9)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Text(entry.jesusClock)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Cloud Sync & Local Storage") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.storageFolderPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(store.lastSyncStatus)
                        .font(.caption2)
                        .foregroundStyle(notesGold)
                }

                ForEach(NotesStore.detectSyncFolderCandidates()) { candidate in
                    let isCurrent = candidate.url.standardizedFileURL == store.activeSyncFolderURL.standardizedFileURL
                    Button {
                        store.setSyncFolder(candidate.url)
                    } label: {
                        HStack {
                            Label(candidate.name, systemImage: candidate.systemImage)
                            Spacer()
                            if isCurrent {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if candidate.existsAlready {
                                Text("Has Notes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                #if canImport(UniformTypeIdentifiers)
                Button {
                    showSyncFolderImporter = true
                } label: {
                    Label("Choose Sync Folder...", systemImage: "folder.badge.plus")
                }
                #endif

                HStack {
                    Button {
                        store.reloadFromSyncFolder()
                    } label: {
                        Label("Sync Now / Reload", systemImage: "arrow.clockwise")
                    }

                    Spacer()

                    if store.activeSyncFolderURL.standardizedFileURL != NotesStore.defaultStorageFolderURL.standardizedFileURL {
                        Button("Default") {
                            store.resetToDefaultSyncFolder()
                        }
                        .font(.caption)
                    }
                }

                #if os(macOS)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.activeSyncFolderURL])
                } label: {
                    Label("Reveal Sync Folder in Finder", systemImage: "finder")
                }
                #endif

                if let syncFolderError {
                    Text(syncFolderError)
                        .font(.caption2)
                        .foregroundStyle(.red)
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

struct SkipVowelsConfirmSheet: View {
    @Bindable var store: NotesStore
    let request: SkipVowelsPromptRequest

    @Environment(\.dismiss) private var dismiss
    @State private var normalizedTarget: String

    init(store: NotesStore, request: SkipVowelsPromptRequest) {
        self.store = store
        self.request = request
        _normalizedTarget = State(initialValue: request.suggestedNormalized)
    }

    private var allSuggestions: [SkipVowelsSuggestion] {
        let knownEntries = store.customRules.map { ($0.pattern, $0.replacement) }
            + store.a3odexEntries.map { ($0.token, $0.canonical) }
        let extraLexicon = store.a3odexEntries.map(\.canonical) + store.customRules.map(\.replacement)
        return SkipVowelsHelper.suggestCleanForms(
            for: request.token,
            knownEntries: knownEntries,
            extraLexicon: extraLexicon
        )
    }

    private var trimmedTarget: String {
        normalizedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(request.token)
                        .font(.system(.title3, design: .monospaced).bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(notesGold.opacity(0.18))
                        .foregroundStyle(notesGold)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    TextField("Normalized clean form", text: $normalizedTarget)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.weight(.medium))
                }

                if !allSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggested Vowel-Restored Targets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allSuggestions) { sug in
                                    Button {
                                        normalizedTarget = sug.normalized
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(sug.normalized)
                                            Text("(\(sug.source))")
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if trimmedTarget == request.token {
                        Label(
                            "Matches raw token — learns \"\(request.token)\" in dictionary and clears red underline without changing Clean View.",
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label(
                            "Saves MUNSC rule \"\(request.token)\" → \"\(trimmedTarget)\" (description: \"Skip vowels verified\") to munsc_rules.json and learns spelling.",
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.green)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Verify \"Skip Vowels\" Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify & Save") {
                        _ = store.addSkipVowelsRule(token: request.token, normalized: trimmedTarget)
                        dismiss()
                    }
                    .disabled(trimmedTarget.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(notesGold)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 270)
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
