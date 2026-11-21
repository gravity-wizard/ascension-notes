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

public struct FontSizeSpan: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int
    public var size: Double

    public init(location: Int, length: Int, size: Double) {
        self.location = location
        self.length = length
        self.size = size
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
    public var foldedBlocks: [String: String]
    public var fontSpans: [FontSizeSpan]

    enum CodingKeys: String, CodingKey {
        case id, rawText, ownerAcode9, folder, isPinned, createdAt, updatedAt, foldedBlocks, fontSpans
    }

    public init(
        id: UUID = UUID(),
        rawText: String,
        ownerAcode9: String,
        folder: NoteFolder = .quickNotes,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        foldedBlocks: [String: String] = [:],
        fontSpans: [FontSizeSpan] = []
    ) {
        self.id = id
        self.rawText = rawText
        self.ownerAcode9 = ownerAcode9
        self.folder = folder
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.foldedBlocks = foldedBlocks
        self.fontSpans = fontSpans
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        rawText = try c.decode(String.self, forKey: .rawText)
        ownerAcode9 = try c.decode(String.self, forKey: .ownerAcode9)
        folder = try c.decodeIfPresent(NoteFolder.self, forKey: .folder) ?? .quickNotes
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        foldedBlocks = try c.decodeIfPresent([String: String].self, forKey: .foldedBlocks) ?? [:]
        fontSpans = try c.decodeIfPresent([FontSizeSpan].self, forKey: .fontSpans) ?? []
    }

    public var derivedTitle: String {
        rawText
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { String($0) } ?? ""
    }

    public var displayTitle: String {
        let trimmed = derivedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Note" : trimmed
    }

    public var derivedBody: String {
        guard let nl = rawText.firstIndex(of: "\n") else {
            return ""
        }
        return String(rawText[rawText.index(after: nl)...])
    }

    public var expandedRawText: String {
        guard !foldedBlocks.isEmpty else { return rawText }
        var out = rawText
        for (marker, original) in foldedBlocks {
            out = out.replacingOccurrences(of: marker, with: original)
        }
        return out
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
            rawText: expandedRawText,
            ownerAcode9: normalizedCode,
            timestampUnix: Int64(updatedAt.timeIntervalSince1970)
        )
    }

    public func previewBody(normalized: Bool = true) -> String {
        let text = compiledDocument()?.render(normalized: normalized) ?? expandedRawText
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
    var activeSidebarFilter: SidebarFilter = .all
    var selectedNoteID: UUID?

    var viewMode: ViewLayerMode = .edit
    var showFindBar: Bool = false
    var showInspector: Bool = false
    var showHelp: Bool = false
    var autoCapitalizeNewLines: Bool = false
    var spellcheckCleanView: Bool = true
    var spellcheckRevision: Int = 0
    var editorFontSize: Double = 15.0

    var query: String = ""
    var caseSensitive: Bool = true
    var wholeWord: Bool = false
    var useRegex: Bool = false
    var searchLayer: SearchLayer = .dual
    var urlSafeDash: Bool = false

    var rollingPool: [Acode9PoolEntry] = []
    var unusedAcodeVault: [Acode9PoolEntry] = []
    var liveClockText: String = Base38Clock.safeJesusClock(minWidth: 2).clock
    var rawClockText: String = Base38Clock.jesusClock(minWidth: 2)
    var clockIsPaused: Bool = false

    private let storageURL: URL
    private let backupURL: URL
    private let vaultURL: URL

    init() {
        let appSupport = URL.applicationSupportDirectory.appendingPathComponent("AscensionNotes", isDirectory: true)
        self.storageURL = appSupport.appendingPathComponent("notes.json")
        self.backupURL = appSupport.appendingPathComponent("notes.backup.json")
        self.vaultURL = appSupport.appendingPathComponent("acode_vault.json")
        loadOrSeed()
        loadVault()
        refreshClock()
        generateNextPool()
    }

    var storageFolderPath: String {
        storageURL.deletingLastPathComponent().path
    }

    func selectSidebarFilter(_ filter: SidebarFilter) {
        activeSidebarFilter = filter
        if let firstMatch = filteredNotes.first {
            selectedNoteID = firstMatch.id
        } else {
            selectedNoteID = nil
        }
    }

    var selectedNote: StoredNote? {
        if let id = selectedNoteID, let match = filteredNotes.first(where: { $0.id == id }) {
            return match
        }
        return filteredNotes.first
    }

    var selectedDocument: AXIFDocument? {
        selectedNote?.compiledDocument(urlSafeDash: urlSafeDash)
    }

    var filteredNotes: [StoredNote] {
        let base: [StoredNote]
        switch activeSidebarFilter {
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

    func updateSelectedFullText(_ newText: String, fontSpans: [FontSizeSpan]? = nil) {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        var changed = false
        if notes[idx].rawText != newText {
            notes[idx].rawText = newText
            notes[idx].updatedAt = Date()
            changed = true
        }
        if let spans = fontSpans, notes[idx].fontSpans != spans {
            notes[idx].fontSpans = spans
            changed = true
        }
        if changed {
            save()
        }
    }

    func updateSelectedFontSpans(_ spans: [FontSizeSpan]) {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[idx].fontSpans != spans {
            notes[idx].fontSpans = spans
            save()
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

    func registerFold(original: String) -> String? {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return nil }
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let lineCount = max(1, original.split(separator: "\n", omittingEmptySubsequences: false).count)
        let firstLine = original
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? "Block"
        let snippet = String(firstLine.prefix(24)).replacingOccurrences(of: "]", with: ")")
        let shortId = String(UUID().uuidString.prefix(4)).lowercased()
        let marker = "▸[Folded \(lineCount)L: \(snippet)… #\(shortId)]"

        notes[idx].foldedBlocks[marker] = original
        save()
        return marker
    }

    func consumeFoldedOriginal(for marker: String) -> String? {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }),
              let original = notes[idx].foldedBlocks.removeValue(forKey: marker) else { return nil }
        save()
        return original
    }

    static func autoCapitalizeLeading(oldText: String, newText: String) -> String {
        guard newText.count > oldText.count,
              let first = newText.first,
              first.isASCII && first.isLowercase else {
            return newText
        }
        if oldText.isEmpty || ((newText.count - oldText.count) >= 2 && !newText.hasPrefix(oldText)) {
            return String(first).uppercased() + newText.dropFirst()
        }
        return newText
    }

    static func autoCapitalizeAfterNewlines(oldText: String, newText: String) -> String {
        guard newText.count > oldText.count else { return newText }

        var commonPrefixEnd = newText.startIndex
        var oldIdx = oldText.startIndex
        while oldIdx < oldText.endIndex && commonPrefixEnd < newText.endIndex {
            if oldText[oldIdx] != newText[commonPrefixEnd] { break }
            oldIdx = oldText.index(after: oldIdx)
            commonPrefixEnd = newText.index(after: commonPrefixEnd)
        }

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

    func replaceNormalizedSpan(normOffset: Int, normEnd: Int, with replacement: String) {
        guard let note = selectedNote,
              let doc = note.compiledDocument(urlSafeDash: urlSafeDash),
              let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }

        if !notes[idx].foldedBlocks.isEmpty {
            notes[idx].rawText = notes[idx].expandedRawText
            notes[idx].foldedBlocks.removeAll()
        }

        let rawSpan = doc.mapNormalizedSpanToRaw(start: normOffset, end: normEnd)
        let raw = notes[idx].rawText
        guard rawSpan.start >= 0,
              rawSpan.end <= raw.count,
              rawSpan.start <= rawSpan.end else { return }
        let sIdx = raw.index(raw.startIndex, offsetBy: rawSpan.start)
        let eIdx = raw.index(raw.startIndex, offsetBy: rawSpan.end)
        var updated = raw
        updated.replaceSubrange(sIdx..<eIdx, with: replacement)
        notes[idx].rawText = updated
        notes[idx].updatedAt = Date()
        spellcheckRevision += 1
        save()
    }

    func learnSpellcheckWord(_ word: String) {
        SpellcheckHelper.learnWord(word)
        spellcheckRevision += 1
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
        let freshCode = claimUnusedAcode(fallbackNow: Int64(now.timeIntervalSince1970))

        let targetFolder: NoteFolder
        if case .folder(let f) = activeSidebarFilter {
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
        let nowSec = Int64(Date().timeIntervalSince1970)
        let reading = Base38Clock.safeJesusClock(unixSeconds: nowSec, minWidth: 2, urlSafe: urlSafeDash)
        liveClockText = reading.clock
        rawClockText = reading.rawClock
        clockIsPaused = reading.isPaused

        // Harvest clean Acodes that would otherwise go unused whenever the clock is not paused
        if !reading.isPaused && unusedAcodeVault.count < 120 {
            let alreadyHasSecond = unusedAcodeVault.contains { $0.timestamp == nowSec }
            if !alreadyHasSecond {
                let existingSet = Set(unusedAcodeVault.map(\.acode9) + notes.map(\.ownerAcode9))
                if let harvested = try? Acode9.generate(
                    unixSeconds: nowSec,
                    mode: .good1a,
                    urlSafe: urlSafeDash,
                    existingPool: existingSet
                ) {
                    unusedAcodeVault.insert(
                        Acode9PoolEntry(acode9: harvested, timestamp: nowSec, jesusClock: reading.clock, mode: .good1a),
                        at: 0
                    )
                    if unusedAcodeVault.count > 120 {
                        unusedAcodeVault.removeLast(unusedAcodeVault.count - 120)
                    }
                    saveVault()
                }
            }
        }
    }

    func harvestUnusedAcodes(count: Int = 12) {
        let nowSec = Int64(Date().timeIntervalSince1970)
        let existingSet = Set(unusedAcodeVault.map(\.acode9) + notes.map(\.ownerAcode9))
        if let batch = try? Acode9.generateRollingPool(
            count: count,
            startUnixSeconds: nowSec,
            cadenceSeconds: 1,
            mode: .good1a,
            urlSafe: urlSafeDash,
            existingPool: existingSet
        ) {
            unusedAcodeVault.insert(contentsOf: batch, at: 0)
            if unusedAcodeVault.count > 120 {
                unusedAcodeVault.removeLast(unusedAcodeVault.count - 120)
            }
            saveVault()
        }
    }

    func claimUnusedAcode(fallbackNow: Int64 = Int64(Date().timeIntervalSince1970)) -> String {
        if let first = unusedAcodeVault.first {
            unusedAcodeVault.removeFirst()
            saveVault()
            return urlSafeDash ? ((try? Acode9.toDash(first.acode9)) ?? first.acode9) : ((try? Acode9.toCaret(first.acode9)) ?? first.acode9)
        }
        return (try? Acode9.generate(unixSeconds: fallbackNow, mode: .good1a, urlSafe: urlSafeDash)) ?? "Ab2p^a40z"
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
        for candidateURL in [storageURL, backupURL] {
            if let data = try? Data(contentsOf: candidateURL),
               let decoded = try? JSONDecoder().decode([StoredNote].self, from: data),
               !decoded.isEmpty {
                notes = decoded
                selectedNoteID = filteredNotes.first?.id
                return
            }
        }
        notes = Self.makeSeedNotes()
        selectedNoteID = notes.first?.id
        save()
    }

    func save() {
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(notes) {
            if FileManager.default.fileExists(atPath: storageURL.path) {
                try? FileManager.default.copyItem(at: storageURL, to: backupURL)
            }
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func loadVault() {
        if let data = try? Data(contentsOf: vaultURL),
           let decoded = try? JSONDecoder().decode([Acode9PoolEntry].self, from: data) {
            unusedAcodeVault = decoded
        } else {
            harvestUnusedAcodes(count: 10)
        }
    }

    private func saveVault() {
        let dir = vaultURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(unusedAcodeVault) {
            try? data.write(to: vaultURL, options: .atomic)
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
