import AscensionCore
import Foundation
import Observation

public enum NoteFolder: String, Codable, CaseIterable, Identifiable, Sendable {
    case chamberNorma = "Chamber • Norma"
    case hydrogen4 = "Hydrogen4"
    case milestones = "Milestones"
    case quickNotes = "Quick Notes"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .chamberNorma: return "person.text.rectangle"
        case .hydrogen4: return "atom"
        case .milestones: return "clock.badge.checkmark"
        case .quickNotes: return "note.text"
        }
    }
}

public enum SidebarFilter: Hashable, Identifiable, Sendable {
    case all
    case pinned
    case folder(NoteFolder)

    public var id: String {
        switch self {
        case .all: return "all"
        case .pinned: return "pinned"
        case .folder(let f): return "folder:\(f.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .all: return "All Notes"
        case .pinned: return "Pinned"
        case .folder(let f): return f.rawValue
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .pinned: return "pin.fill"
        case .folder(let f): return f.systemImage
        }
    }
}

public struct StoredNote: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var rawText: String
    public var ownerAcode9: String
    public var folder: NoteFolder
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        rawText: String,
        ownerAcode9: String,
        folder: NoteFolder = .quickNotes,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.rawText = rawText
        self.ownerAcode9 = ownerAcode9
        self.folder = folder
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Apple Notes convention: Line 1 is the note title.
    public var derivedTitle: String {
        let firstLine = rawText
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { String($0) } ?? ""
        return firstLine
    }

    public var displayTitle: String {
        let trimmed = derivedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Note" : trimmed
    }

    /// Everything after the first newline.
    public var derivedBody: String {
        guard let nl = rawText.firstIndex(of: "\n") else {
            return ""
        }
        return String(rawText[rawText.index(after: nl)...])
    }

    public func compiledDocument(urlSafeDash: Bool = false) -> AXIFDocument? {
        let normalizedCode: String
        if urlSafeDash {
            normalizedCode = (try? Acode9.toDash(ownerAcode9)) ?? ownerAcode9
        } else {
            normalizedCode = (try? Acode9.toCaret(ownerAcode9)) ?? ownerAcode9
        }
        return try? AXIFDocument(
            title: displayTitle,
            rawText: rawText,
            ownerAcode9: normalizedCode,
            timestampUnix: Int64(updatedAt.timeIntervalSince1970)
        )
    }

    public func previewBody(normalized: Bool = true) -> String {
        let text = compiledDocument()?.render(normalized: normalized) ?? rawText
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count <= 1 {
            return "No additional text"
        }
        return lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
@Observable
final class NotesStore {
    enum ViewLayerMode: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case clean = "Clean View"
        var id: String { rawValue }
    }

    var notes: [StoredNote] = []
    var sidebarFilter: SidebarFilter = .all
    var selectedNoteID: UUID?

    /// Default to live editing like Apple Notes so opening any note allows immediate Title & Body changes.
    var viewMode: ViewLayerMode = .edit
    var showFindBar: Bool = false
    var showInspector: Bool = false
    var showHelp: Bool = false
    var autoCapitalizeNewLines: Bool = true

    var query: String = ""
    var caseSensitive: Bool = true
    var wholeWord: Bool = false
    var useRegex: Bool = false
    var searchLayer: SearchLayer = .dual
    var urlSafeDash: Bool = false

    var rollingPool: [Acode9PoolEntry] = []
    var liveClockText: String = Base38Clock.jesusClock(minWidth: 2)

    private let storageURL: URL

    init() {
        let appSupport = URL.applicationSupportDirectory.appendingPathComponent("AscensionNotes", isDirectory: true)
        self.storageURL = appSupport.appendingPathComponent("notes.json")
        loadOrSeed()
        refreshClock()
        generateNextPool()
    }

    var selectedNote: StoredNote? {
        guard let id = selectedNoteID else { return filteredNotes.first }
        return notes.first(where: { $0.id == id }) ?? filteredNotes.first
    }

    var selectedDocument: AXIFDocument? {
        selectedNote?.compiledDocument(urlSafeDash: urlSafeDash)
    }

    var filteredNotes: [StoredNote] {
        let base: [StoredNote]
        switch sidebarFilter {
        case .all:
            base = notes
        case .pinned:
            base = notes.filter(\.isPinned)
        case .folder(let folder):
            base = notes.filter { $0.folder == folder }
        }

        let sorted = base.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return sorted }

        return sorted.filter { note in
            if matchesQuery(in: note) {
                return true
            }
            return note.ownerAcode9.range(
                of: trimmedQuery,
                options: caseSensitive ? [] : [.caseInsensitive]
            ) != nil
        }
    }

    func count(for filter: SidebarFilter) -> Int {
        switch filter {
        case .all:
            return notes.count
        case .pinned:
            return notes.filter(\.isPinned).count
        case .folder(let f):
            return notes.filter { $0.folder == f }.count
        }
    }

    func searchMatches(for note: StoredNote) -> [SearchMatch] {
        let q = query
        guard !q.isEmpty, let doc = note.compiledDocument(urlSafeDash: urlSafeDash) else {
            return []
        }
        let opts = SearchOptions(
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            regex: useRegex,
            layer: searchLayer
        )
        return (try? CaseSensitiveSearch.search(document: doc, query: q, options: opts)) ?? []
    }

    func matchesQuery(in note: StoredNote) -> Bool {
        !searchMatches(for: note).isEmpty
    }

    var selectedSearchMatches: [SearchMatch] {
        guard let note = selectedNote else { return [] }
        return searchMatches(for: note)
    }

    var searchErrorMessage: String? {
        guard useRegex, !query.isEmpty, let doc = selectedDocument else { return nil }
        do {
            _ = try CaseSensitiveSearch.search(
                document: doc,
                query: query,
                options: SearchOptions(
                    caseSensitive: caseSensitive,
                    wholeWord: wholeWord,
                    regex: true,
                    layer: searchLayer
                )
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func updateSelectedTitle(_ newTitle: String) {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }

        let singleLine = newTitle.replacingOccurrences(of: "\n", with: " ")
        let oldTitle = notes[idx].derivedTitle
        let adjusted = autoCapitalizeNewLines
            ? Self.autoCapitalizeLeading(oldText: oldTitle, newText: singleLine)
            : singleLine

        let body = notes[idx].derivedBody
        let combined = body.isEmpty ? adjusted : "\(adjusted)\n\(body)"
        if notes[idx].rawText != combined {
            notes[idx].rawText = combined
            notes[idx].updatedAt = Date()
            save()
        }
    }

    func updateSelectedBody(_ newBody: String) {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }

        let oldBody = notes[idx].derivedBody
        let adjustedBody = autoCapitalizeNewLines
            ? Self.autoCapitalizeAfterNewlines(oldText: oldBody, newText: newBody)
            : newBody

        let title = notes[idx].derivedTitle
        let combined = "\(title)\n\(adjustedBody)"
        if notes[idx].rawText != combined {
            notes[idx].rawText = combined
            notes[idx].updatedAt = Date()
            save()
        }
    }

    /// Capitalize first letter when typing or dictating via Siri at start of title.
    static func autoCapitalizeLeading(oldText: String, newText: String) -> String {
        guard newText.count > oldText.count,
              let first = newText.first,
              first.isASCII && first.isLowercase else {
            return newText
        }
        // Only capitalize when starting from empty or when Siri/paste inserted a chunk
        if oldText.isEmpty || ((newText.count - oldText.count) >= 2 && !newText.hasPrefix(oldText)) {
            return String(first).uppercased() + newText.dropFirst()
        }
        return newText
    }

    /// Capitalize lowercase start of a line when newly typed or inserted via macOS Siri Dictation.
    static func autoCapitalizeAfterNewlines(oldText: String, newText: String) -> String {
        guard newText.count > oldText.count else { return newText }

        // Find common prefix between oldText and newText
        var commonPrefixEnd = newText.startIndex
        var oldIdx = oldText.startIndex
        while oldIdx < oldText.endIndex && commonPrefixEnd < newText.endIndex {
            if oldText[oldIdx] != newText[commonPrefixEnd] { break }
            oldIdx = oldText.index(after: oldIdx)
            commonPrefixEnd = newText.index(after: commonPrefixEnd)
        }

        // Find common suffix from end
        var newSuffixStart = newText.endIndex
        var oldSuffixStart = oldText.endIndex
        while oldSuffixStart > oldIdx && newSuffixStart > commonPrefixEnd {
            let prevOld = oldText.index(before: oldSuffixStart)
            let prevNew = newText.index(before: newSuffixStart)
            if oldText[prevOld] != newText[prevNew] { break }
            oldSuffixStart = prevOld
            newSuffixStart = prevNew
        }

        guard commonPrefixEnd < newSuffixStart else { return newText }

        var chars = Array(newText)
        let startOffset = newText.distance(from: newText.startIndex, to: commonPrefixEnd)
        let endOffset = newText.distance(from: newText.startIndex, to: newSuffixStart)

        var modified = false
        for pos in startOffset..<endOffset {
            let ch = chars[pos]
            guard ch.isASCII && ch.isLowercase else { continue }
            let atStartOfBody = (pos == 0)
            let rightAfterNewline = (pos > 0 && chars[pos - 1] == "\n")
            if atStartOfBody || rightAfterNewline {
                chars[pos] = Character(String(ch).uppercased())
                modified = true
            }
        }
        return modified ? String(chars) : newText
    }

    func updateSelectedOwnerAcode9(_ newCode: String) {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].ownerAcode9 = newCode
        notes[idx].updatedAt = Date()
        save()
    }

    func updateSelectedFolder(_ folder: NoteFolder) {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].folder = folder
        notes[idx].updatedAt = Date()
        save()
    }

    func togglePin(_ noteID: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].isPinned.toggle()
        save()
    }

    func createNewNote() {
        let now = Date()
        let freshCode = (try? Acode9.generate(
            unixSeconds: Int64(now.timeIntervalSince1970),
            mode: .good1a,
            urlSafe: urlSafeDash
        )) ?? "Ab2p^a40z"

        let targetFolder: NoteFolder
        if case .folder(let f) = sidebarFilter {
            targetFolder = f
        } else {
            targetFolder = .quickNotes
        }

        let note = StoredNote(
            rawText: "\n",
            ownerAcode9: freshCode,
            folder: targetFolder,
            isPinned: false,
            createdAt: now,
            updatedAt: now
        )
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        viewMode = .edit
        save()
    }

    func deleteNotes(at offsets: IndexSet) {
        let current = filteredNotes
        let idsToRemove = Set(offsets.map { current[$0].id })
        notes.removeAll { idsToRemove.contains($0.id) }
        if let sel = selectedNoteID, idsToRemove.contains(sel) {
            selectedNoteID = filteredNotes.first?.id
        }
        save()
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNoteID == id {
            selectedNoteID = filteredNotes.first?.id
        }
        save()
    }

    func resetSampleNotes() {
        notes = Self.makeSeedNotes()
        selectedNoteID = notes.first?.id
        viewMode = .edit
        save()
    }

    func refreshClock() {
        liveClockText = Base38Clock.jesusClock(minWidth: 2)
    }

    func generateNextPool() {
        let now = Int64(Date().timeIntervalSince1970)
        rollingPool = (try? Acode9.generateRollingPool(
            count: 6,
            startUnixSeconds: now,
            cadenceSeconds: 1,
            mode: .good1a,
            urlSafe: urlSafeDash
        )) ?? []
    }

    func loadOrSeed() {
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([StoredNote].self, from: data),
           !decoded.isEmpty {
            notes = decoded
            selectedNoteID = filteredNotes.first?.id
            return
        }
        notes = Self.makeSeedNotes()
        selectedNoteID = notes.first?.id
        save()
    }

    func save() {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private static func makeSeedNotes() -> [StoredNote] {
        let now = Date()
        let baseTs = TimeInterval(Base38Clock.t0Unix + 210_661_380)
        let refDate = Date(timeIntervalSince1970: max(now.timeIntervalSince1970, baseTs))

        return [
            StoredNote(
                rawText: """
                N0rma — Chamber Luncheon & Trailhead Log
                Field note authored under Acode9 Ab2p^a40z (Jesus Clock 2p15ek).
                Met NormA at the trailhead, confirmed coordinates with Norm4, and archived Norma4 in the AXIF ledger.
                Tip: Turn on Aa Case-Sensitive search and search NormA, Norm4, or Norma4 — or switch to Clean View!
                """,
                ownerAcode9: "Ab2p^a40z",
                folder: .chamberNorma,
                isPinned: true,
                createdAt: refDate.addingTimeInterval(-3600),
                updatedAt: refDate.addingTimeInterval(-120)
            ),
            StoredNote(
                rawText: """
                Hydrogen4^high-mode5 — Ascension Apps Charter
                Every Acode9 starts with BigA and carries a middle mountain ^ pointing to the Heavens Above.
                MUNSCs (Multiple Unique Non-Special Characters) stay hidden inside Clean View output via AXIF metadata while remaining 100% case-sensitively searchable.
                """,
                ownerAcode9: "Ab2p^0oyu",
                folder: .hydrogen4,
                isPinned: true,
                createdAt: refDate.addingTimeInterval(-7200),
                updatedAt: refDate.addingTimeInterval(-900)
            ),
            StoredNote(
                rawText: """
                Ac3x^chch — Future Epoch Milestone (C == 3, H == 8)
                When the Base-38 Jesus Clock advances into 3x...., the paired lead letter becomes c (matching C == 3) while 8 pairs with H == 8.
                First1a marks defining moments across Ascender1a logs.
                """,
                ownerAcode9: "Ac3x^chch",
                folder: .milestones,
                isPinned: false,
                createdAt: refDate.addingTimeInterval(-14400),
                updatedAt: refDate.addingTimeInterval(-3600)
            ),
            StoredNote(
                rawText: """
                Reading & B00K Checklist (FUNs, FUNCs, SxUNCs, SvnUNCs)
                - Priming the Sits-You-Weigh-Station (S1tsUW8)
                - Solving "Were's Norma?" with N0rma and AXIF
                - Reviewing 7Aunts & Slog at Formicary Castle
                """,
                ownerAcode9: "Ab2p^k7mz",
                folder: .quickNotes,
                isPinned: false,
                createdAt: refDate.addingTimeInterval(-28800),
                updatedAt: refDate.addingTimeInterval(-7200)
            )
        ]
    }
}
