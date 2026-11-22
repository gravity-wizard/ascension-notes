import AscensionCore
import Foundation
import Observation
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

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

public struct NoteAttachment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var filename: String
    public var relativePath: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var createdAt: Date
    public var exactUnixTimestamp: Int64?
    public var base38TimestampTag: String?

    enum CodingKeys: String, CodingKey {
        case id, filename, relativePath, pixelWidth, pixelHeight, createdAt, exactUnixTimestamp, base38TimestampTag
    }

    public var shortID: String {
        String(id.uuidString.prefix(4)).lowercased()
    }

    public var markerText: String {
        let safeName = filename
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
        return "▸[Image: \(safeName) #\(shortID)]"
    }

    public init(
        id: UUID = UUID(),
        filename: String,
        relativePath: String,
        pixelWidth: Int,
        pixelHeight: Int,
        createdAt: Date = Date(),
        exactUnixTimestamp: Int64? = nil,
        base38TimestampTag: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.relativePath = relativePath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
        self.exactUnixTimestamp = exactUnixTimestamp
        self.base38TimestampTag = base38TimestampTag
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        pixelWidth = try c.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        exactUnixTimestamp = try c.decodeIfPresent(Int64.self, forKey: .exactUnixTimestamp)
        base38TimestampTag = try c.decodeIfPresent(String.self, forKey: .base38TimestampTag)
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
    public var attachments: [NoteAttachment]
    public var authorAAid: String?

    enum CodingKeys: String, CodingKey {
        case id, rawText, ownerAcode9, folder, isPinned, createdAt, updatedAt, foldedBlocks, fontSpans, attachments, authorAAid
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
        fontSpans: [FontSizeSpan] = [],
        attachments: [NoteAttachment] = [],
        authorAAid: String? = "Ab2p^a00z"
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
        self.attachments = attachments
        self.authorAAid = authorAAid
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
        attachments = try c.decodeIfPresent([NoteAttachment].self, forKey: .attachments) ?? []
        authorAAid = try c.decodeIfPresent(String.self, forKey: .authorAAid) ?? "Ab2p^a00z"
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

    public func compiledDocument(urlSafeDash: Bool = false, rules: [MUNSCRule] = []) -> AXIFDocument? {
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
            rules: rules,
            timestampUnix: Int64(updatedAt.timeIntervalSince1970)
        )
    }

    public func previewBody(normalized: Bool = true, rules: [MUNSCRule] = []) -> String {
        let text = compiledDocument(rules: rules)?.render(normalized: normalized) ?? expandedRawText
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count <= 1 {
            return "No additional text"
        }
        return lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SyncFolderCandidate: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let subtitle: String
    public let url: URL
    public let systemImage: String
    public let existsAlready: Bool
}

public struct AXIFImportResult: Sendable {
    public let note: StoredNote
    public let bundle: AXIFDecodedBundle
    public let importedRulesCount: Int
}

public struct CursorSpellTarget: Equatable, Sendable {
    public let noteID: UUID
    public let word: String
    public let rangeLocation: Int
    public let rangeLength: Int
    public let isMisspelled: Bool
    public let isGrammarIs: Bool
    public let guesses: [String]
    public let skipVowelsSuggestion: String?
    public let skipVowelsIsExact: Bool
}

public struct SkipVowelsPromptRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let token: String
    public let suggestedNormalized: String
    public let rangeLocation: Int
    public let rangeLength: Int

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        token: String,
        suggestedNormalized: String,
        rangeLocation: Int,
        rangeLength: Int
    ) {
        self.id = id
        self.noteID = noteID
        self.token = token
        self.suggestedNormalized = suggestedNormalized
        self.rangeLocation = rangeLocation
        self.rangeLength = rangeLength
    }
}

public struct RetinaLightboxRequest: Identifiable, Equatable, Sendable {
    public var id: UUID { attachment.id }
    public let noteID: UUID
    public let attachment: NoteAttachment
}

public struct CopyWithImagesRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let selectedText: String
    public let attachments: [NoteAttachment]
    public let preselectedAttachmentIDs: Set<UUID>
    public let appendUnreferenced: Bool

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        selectedText: String,
        attachments: [NoteAttachment],
        preselectedAttachmentIDs: Set<UUID>,
        appendUnreferenced: Bool
    ) {
        self.id = id
        self.noteID = noteID
        self.selectedText = selectedText
        self.attachments = attachments
        self.preselectedAttachmentIDs = preselectedAttachmentIDs
        self.appendUnreferenced = appendUnreferenced
    }
}

public enum TextViewQuickAction: Sendable {
    case replaceRange(location: Int, length: Int, with: String, learnWord: String?)
    case learnOnly(String)
    case insertText(String)
    case revealRange(NSRange)
    case flushAndSave
}

@MainActor
@Observable
final class NotesStore {
    enum ViewLayerMode: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case clean = "Clean View"
        var id: String { rawValue }
    }

    static let syncFolderDefaultsKey = "ascensionNotesSyncFolderPath"
    static let syncFolderBookmarkKey = "ascensionNotesSyncFolderBookmark"

    var notes: [StoredNote] = []
    var customRules: [MUNSCRule] = []
    var a3odexEntries: [A3odexEntry] = A3odexCatalog.starterEntries
    var activeSidebarFilter: SidebarFilter = .all
    var selectedNoteID: UUID?

    var authorAAid: String = "Ab2p^a00z"
    var lastInsertedEmoji: String = "🔻🔻"

    public struct EmojiInsertionRecord {
        public let noteID: UUID
        public let location: Int
        public let emoji: String
        public let timestamp: Date
    }

    var lastEmojiInsertionRecord: EmojiInsertionRecord? = nil

    static let starterRecentEmojis: [String] = ["🔻🔻", "🔺🔺", "🐇", "🪿", "😎", "🐸", "🐬", "🗝️", "🆒"]
    var recentEmojis: [String] = starterRecentEmojis
    var recentEmojiCycleIndex: Int = 0

    static func normalizeDitto(_ emoji: String) -> String {
        let clean = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean == "🔺" { return "🔺🔺" }
        if clean == "🔻" { return "🔻🔻" }
        return clean
    }

    var viewMode: ViewLayerMode = .edit
    var showFindBar: Bool = false
    var activeSearchMatchIndex: Int = 0
    var showInspector: Bool = false
    var showHelp: Bool = false
    var showA3odex: Bool = false
    var showImportAXIF: Bool = false
    var activeCopyWithImagesRequest: CopyWithImagesRequest? = nil
    var autoCapitalizeNewLines: Bool = false
    var spellcheckCleanView: Bool = true
    var spellcheckRevision: Int = 0
    var editorFontSize: Double = 15.0

    var isFocusMode: Bool = false
    var previousViewMode: ViewLayerMode = .edit
    var previousShowInspector: Bool = false
    var previousShowFindBar: Bool = false

    func toggleFocusMode() {
        if isFocusMode {
            isFocusMode = false
            viewMode = previousViewMode
            showInspector = previousShowInspector
            showFindBar = previousShowFindBar
        } else {
            previousViewMode = viewMode
            previousShowInspector = showInspector
            previousShowFindBar = showFindBar
            isFocusMode = true
            viewMode = .clean
            showInspector = false
            showFindBar = false
        }
    }

    func recordEmojiInsertion(location: Int, emoji: String) {
        guard let id = selectedNoteID else { return }
        let clean = Self.normalizeDitto(emoji)
        lastEmojiInsertionRecord = EmojiInsertionRecord(
            noteID: id,
            location: location,
            emoji: clean,
            timestamp: Date()
        )
        registerRecentEmoji(clean)
    }

    func registerRecentEmoji(_ emoji: String) {
        let clean = Self.normalizeDitto(emoji)
        guard !clean.isEmpty else { return }
        if let existingIdx = recentEmojis.firstIndex(of: clean) {
            recentEmojis.remove(at: existingIdx)
        }
        recentEmojis.insert(clean, at: 0)
        for seed in Self.starterRecentEmojis {
            if !recentEmojis.contains(seed) {
                recentEmojis.append(seed)
            }
        }
        if recentEmojis.count > 24 {
            recentEmojis = Array(recentEmojis.prefix(24))
        }
    }

    func preemptRecentEmoji(_ emoji: String) {
        let clean = Self.normalizeDitto(emoji)
        guard !clean.isEmpty else { return }
        registerRecentEmoji(clean)
        lastInsertedEmoji = clean
        recentEmojiCycleIndex = 0
    }

    func repeatLastEmoji() {
        if viewMode != .edit {
            viewMode = .edit
        }
        let snippet = Self.normalizeDitto(lastInsertedEmoji.isEmpty ? "🔻🔻" : lastInsertedEmoji)
        if let handler = activeTextViewActionHandler, handler(.insertText(snippet)) {
            return
        }
        guard let note = selectedNote else { return }
        let newPos = (note.rawText as NSString).length
        updateSelectedFullText(note.rawText + snippet, fontSpans: note.fontSpans)
        recordEmojiInsertion(location: newPos, emoji: snippet)
    }

    func cycleRecentEmoji() {
        if viewMode != .edit {
            viewMode = .edit
        }
        guard !recentEmojis.isEmpty else { return }
        recentEmojiCycleIndex = (recentEmojiCycleIndex + 1) % recentEmojis.count
        let nextEmoji = recentEmojis[recentEmojiCycleIndex]
        let oldEmoji = lastInsertedEmoji
        lastInsertedEmoji = nextEmoji

        // If user just inserted an emoji within 5 seconds in the active note, swap it in place
        if let rec = lastEmojiInsertionRecord,
           rec.noteID == selectedNoteID,
           Date().timeIntervalSince(rec.timestamp) < 5.0,
           rec.emoji == oldEmoji {
            let oldLen = (oldEmoji as NSString).length
            if let handler = activeTextViewActionHandler,
               handler(.replaceRange(location: rec.location, length: oldLen, with: nextEmoji, learnWord: nil)) {
                lastEmojiInsertionRecord = EmojiInsertionRecord(
                    noteID: rec.noteID,
                    location: rec.location,
                    emoji: nextEmoji,
                    timestamp: Date()
                )
                return
            }
        }
    }

    func setFavoriteEmojiAndInsert(_ emoji: String) {
        let clean = Self.normalizeDitto(emoji)
        lastInsertedEmoji = clean
        if let idx = recentEmojis.firstIndex(of: clean) {
            recentEmojiCycleIndex = idx
        }
        repeatLastEmoji()
    }

    var cursorSpellTarget: CursorSpellTarget? = nil
    var skipVowelsPrompt: SkipVowelsPromptRequest? = nil
    var activeLightboxRequest: RetinaLightboxRequest? = nil
    @ObservationIgnored var activeTextViewActionHandler: ((TextViewQuickAction) -> Bool)? = nil

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

    var activeSyncFolderURL: URL
    var lastSyncStatus: String = "Ready"
    var lastSyncDate: Date?
    var lastSaveError: String? = nil

    private var storageURL: URL { activeSyncFolderURL.appendingPathComponent("notes.json") }
    private var backupURL: URL { activeSyncFolderURL.appendingPathComponent("notes.backup.json") }
    private var vaultURL: URL { activeSyncFolderURL.appendingPathComponent("acode_vault.json") }
    private var munscRulesURL: URL { activeSyncFolderURL.appendingPathComponent("munsc_rules.json") }
    private var a3odexURL: URL { activeSyncFolderURL.appendingPathComponent("a3odex.json") }

    init() {
        self.activeSyncFolderURL = Self.resolveInitialSyncFolder()
        loadCustomRules()
        loadOrSeed()
        loadVault()
        loadA3odex()
        refreshClock()
        generateNextPool()
    }

    var storageFolderPath: String {
        activeSyncFolderURL.path
    }

    static var defaultStorageFolderURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("AscensionNotes", isDirectory: true)
    }

    private static var sharedSyncFolderPointerURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ascension-notes-sync-folder")
    }

    private static func saveSharedSyncFolderPath(_ path: String) {
        try? path.write(to: sharedSyncFolderPointerURL, atomically: true, encoding: .utf8)
    }

    private static func clearSharedSyncFolderPath() {
        try? FileManager.default.removeItem(at: sharedSyncFolderPointerURL)
    }

    static func resolveInitialSyncFolder() -> URL {
        let fm = FileManager.default
        if let bookmarkData = UserDefaults.standard.data(forKey: syncFolderBookmarkKey) {
            var isStale = false
            #if os(macOS)
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
            #else
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
            #endif
        }

        if let savedPath = UserDefaults.standard.string(forKey: syncFolderDefaultsKey),
           !savedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: savedPath, isDirectory: true)
        }

        if let sharedPath = try? String(contentsOf: sharedSyncFolderPointerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !sharedPath.isEmpty {
            let sharedURL = URL(fileURLWithPath: sharedPath, isDirectory: true)
            if fm.fileExists(atPath: sharedURL.path) {
                return sharedURL
            }
        }

        let defaultNotes = defaultStorageFolderURL.appendingPathComponent("notes.json").path
        if !fm.fileExists(atPath: defaultNotes),
           let existingCandidate = detectSyncFolderCandidates().first(where: { $0.existsAlready }) {
            return existingCandidate.url
        }

        return defaultStorageFolderURL
    }

    static func detectSyncFolderCandidates() -> [SyncFolderCandidate] {
        var candidates: [SyncFolderCandidate] = []
        let fm = FileManager.default

        let defaultURL = defaultStorageFolderURL
        candidates.append(
            SyncFolderCandidate(
                name: "Default Local Storage",
                subtitle: defaultURL.path,
                url: defaultURL,
                systemImage: "internaldrive",
                existsAlready: fm.fileExists(atPath: defaultURL.appendingPathComponent("notes.json").path)
            )
        )

        let home = fm.homeDirectoryForCurrentUser
        let iCloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let iCloudTarget = iCloudDocs.appendingPathComponent("AscensionNotes", isDirectory: true)
        if fm.fileExists(atPath: iCloudDocs.path) || fm.fileExists(atPath: iCloudTarget.path) {
            candidates.append(
                SyncFolderCandidate(
                    name: "iCloud Drive",
                    subtitle: iCloudTarget.path,
                    url: iCloudTarget,
                    systemImage: "icloud",
                    existsAlready: fm.fileExists(atPath: iCloudTarget.appendingPathComponent("notes.json").path)
                )
            )
        }

        let cloudStorageRoot = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(
            at: cloudStorageRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in items where item.lastPathComponent.hasPrefix("GoogleDrive-") {
                let myDrive = item.appendingPathComponent("My Drive", isDirectory: true)
                let gDriveTarget = myDrive.appendingPathComponent("AscensionNotes", isDirectory: true)
                if fm.fileExists(atPath: myDrive.path) || fm.fileExists(atPath: gDriveTarget.path) {
                    let accountLabel = item.lastPathComponent.replacingOccurrences(of: "GoogleDrive-", with: "")
                    candidates.append(
                        SyncFolderCandidate(
                            name: "Google Drive (\(accountLabel))",
                            subtitle: gDriveTarget.path,
                            url: gDriveTarget,
                            systemImage: "externaldrive.connected.to.line.below",
                            existsAlready: fm.fileExists(atPath: gDriveTarget.appendingPathComponent("notes.json").path)
                        )
                    )
                }
            }
        }

        return candidates
    }

    private func withFolderAccess<T>(_ folderURL: URL, _ body: () throws -> T) rethrows -> T {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    func setSyncFolder(_ url: URL) {
        let targetDir = url
        let previousDir = activeSyncFolderURL

        if targetDir.standardizedFileURL == previousDir.standardizedFileURL {
            reloadFromSyncFolder()
            return
        }

        let fm = FileManager.default
        let targetNotesFile = targetDir.appendingPathComponent("notes.json")
        let targetRulesFile = targetDir.appendingPathComponent("munsc_rules.json")
        let targetVaultFile = targetDir.appendingPathComponent("acode_vault.json")
        let targetA3odexFile = targetDir.appendingPathComponent("a3odex.json")

        let targetHasNotes = withFolderAccess(targetDir) {
            fm.fileExists(atPath: targetNotesFile.path)
        }

        withFolderAccess(targetDir) {
            try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

            if !targetHasNotes {
                withFolderAccess(previousDir) {
                    let files = ["notes.json", "notes.backup.json", "munsc_rules.json", "acode_vault.json", "a3odex.json"]
                    for name in files {
                        let src = previousDir.appendingPathComponent(name)
                        let dst = targetDir.appendingPathComponent(name)
                        if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                            try? fm.copyItem(at: src, to: dst)
                        }
                    }
                    let srcAttach = previousDir.appendingPathComponent("attachments", isDirectory: true)
                    let dstAttach = targetDir.appendingPathComponent("attachments", isDirectory: true)
                    if fm.fileExists(atPath: srcAttach.path), !fm.fileExists(atPath: dstAttach.path) {
                        try? fm.copyItem(at: srcAttach, to: dstAttach)
                    }
                }
            }
        }

        activeSyncFolderURL = targetDir
        UserDefaults.standard.set(targetDir.path, forKey: Self.syncFolderDefaultsKey)
        Self.saveSharedSyncFolderPath(targetDir.path)
        withFolderAccess(targetDir) {
            #if os(macOS)
            if let bookmark = try? targetDir.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmark, forKey: Self.syncFolderBookmarkKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.syncFolderBookmarkKey)
            }
            #else
            if let bookmark = try? targetDir.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmark, forKey: Self.syncFolderBookmarkKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.syncFolderBookmarkKey)
            }
            #endif
        }

        let targetExists = withFolderAccess(targetDir) {
            (
                rules: fm.fileExists(atPath: targetRulesFile.path),
                vault: fm.fileExists(atPath: targetVaultFile.path),
                a3odex: fm.fileExists(atPath: targetA3odexFile.path)
            )
        }

        if targetHasNotes {
            if targetExists.rules {
                loadCustomRules()
            } else {
                saveCustomRules()
            }
            loadOrSeed()
            if targetExists.vault {
                loadVault()
            } else {
                saveVault()
            }
            if targetExists.a3odex {
                loadA3odex()
            }
            lastSyncStatus = "Loaded existing notes from \(targetDir.lastPathComponent)"
        } else {
            save()
            saveCustomRules()
            saveVault()
            lastSyncStatus = "Migrated notes to \(targetDir.lastPathComponent)"
        }
        lastSyncDate = Date()
        spellcheckRevision += 1
    }

    func resetToDefaultSyncFolder() {
        UserDefaults.standard.removeObject(forKey: Self.syncFolderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.syncFolderBookmarkKey)
        Self.clearSharedSyncFolderPath()
        setSyncFolder(Self.defaultStorageFolderURL)
    }

    func reloadFromSyncFolder() {
        let previousSelected = selectedNoteID
        loadCustomRules()
        loadOrSeed()
        loadVault()
        loadA3odex()
        if let prev = previousSelected, notes.contains(where: { $0.id == prev }) {
            selectedNoteID = prev
        }
        lastSyncDate = Date()
        lastSyncStatus = "Synced at \(Date().formatted(date: .omitted, time: .shortened))"
        spellcheckRevision += 1
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
        selectedNote?.compiledDocument(urlSafeDash: urlSafeDash, rules: customRules)
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
            if note.derivedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               note.displayTitle.range(
                   of: trimmedQuery,
                   options: caseSensitive ? [] : [.caseInsensitive]
               ) != nil {
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
        guard !q.isEmpty, let doc = note.compiledDocument(urlSafeDash: urlSafeDash, rules: customRules) else {
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

    func searchHighlightNSRanges(for note: StoredNote) -> [NSRange] {
        let matches = searchMatches(for: note)
        guard !matches.isEmpty else { return [] }

        let raw = note.rawText
        guard !raw.isEmpty else { return [] }

        if note.foldedBlocks.isEmpty {
            let charCount = raw.count
            var result: [NSRange] = []
            result.reserveCapacity(matches.count)
            for hit in matches {
                let sOff = max(0, min(hit.rawOffset, charCount))
                let eOff = max(sOff, min(hit.rawEnd, charCount))
                guard sOff < eOff else { continue }
                let sIdx = raw.index(raw.startIndex, offsetBy: sOff)
                let eIdx = raw.index(raw.startIndex, offsetBy: eOff)
                let nsRange = NSRange(sIdx..<eIdx, in: raw)
                if nsRange.length > 0 {
                    result.append(nsRange)
                }
            }
            return result
        }

        // Map expandedRawText character offsets back onto note.rawText NSRanges when fold markers are present.
        struct SegmentMap {
            let rawRange: Range<String.Index>
            let expStart: Int
            let expEnd: Int
            let isFolded: Bool
        }

        var segments: [SegmentMap] = []
        var rawCursor = raw.startIndex
        var expCursor = 0
        let markers = Array(note.foldedBlocks.keys)

        while rawCursor < raw.endIndex {
            var earliestRange: Range<String.Index>? = nil
            var earliestMarker: String? = nil
            for marker in markers {
                if let found = raw.range(of: marker, range: rawCursor..<raw.endIndex) {
                    if earliestRange == nil || found.lowerBound < earliestRange!.lowerBound {
                        earliestRange = found
                        earliestMarker = marker
                    }
                }
            }

            guard let foundRange = earliestRange, let marker = earliestMarker else {
                let tailLen = raw.distance(from: rawCursor, to: raw.endIndex)
                segments.append(
                    SegmentMap(
                        rawRange: rawCursor..<raw.endIndex,
                        expStart: expCursor,
                        expEnd: expCursor + tailLen,
                        isFolded: false
                    )
                )
                break
            }

            if rawCursor < foundRange.lowerBound {
                let plainLen = raw.distance(from: rawCursor, to: foundRange.lowerBound)
                segments.append(
                    SegmentMap(
                        rawRange: rawCursor..<foundRange.lowerBound,
                        expStart: expCursor,
                        expEnd: expCursor + plainLen,
                        isFolded: false
                    )
                )
                expCursor += plainLen
            }

            let expandedLen = (note.foldedBlocks[marker] ?? marker).count
            segments.append(
                SegmentMap(
                    rawRange: foundRange,
                    expStart: expCursor,
                    expEnd: expCursor + expandedLen,
                    isFolded: true
                )
            )
            expCursor += expandedLen
            rawCursor = foundRange.upperBound
        }

        var result: [NSRange] = []
        result.reserveCapacity(matches.count)
        for hit in matches {
            let hS = max(0, min(hit.rawOffset, expCursor))
            let hE = max(hS, min(hit.rawEnd, expCursor))
            guard hS < hE else { continue }
            for seg in segments {
                let ovS = max(hS, seg.expStart)
                let ovE = min(hE, seg.expEnd)
                guard ovS < ovE else { continue }
                if seg.isFolded {
                    let nsRange = NSRange(seg.rawRange, in: raw)
                    if nsRange.length > 0 {
                        result.append(nsRange)
                    }
                } else {
                    let relS = ovS - seg.expStart
                    let relE = ovE - seg.expStart
                    let sIdx = raw.index(seg.rawRange.lowerBound, offsetBy: relS)
                    let eIdx = raw.index(seg.rawRange.lowerBound, offsetBy: relE)
                    let nsRange = NSRange(sIdx..<eIdx, in: raw)
                    if nsRange.length > 0 {
                        result.append(nsRange)
                    }
                }
            }
        }
        return result
    }

    func jumpToSearchMatch(at index: Int) {
        guard let note = selectedNote else { return }
        let ranges = searchHighlightNSRanges(for: note)
        guard !ranges.isEmpty else {
            activeSearchMatchIndex = 0
            return
        }
        let clamped = ((index % ranges.count) + ranges.count) % ranges.count
        activeSearchMatchIndex = clamped
        _ = activeTextViewActionHandler?(.revealRange(ranges[clamped]))
    }

    func stepSearchMatch(delta: Int) {
        guard let note = selectedNote else { return }
        let ranges = searchHighlightNSRanges(for: note)
        guard !ranges.isEmpty else {
            activeSearchMatchIndex = 0
            return
        }
        let next = ((activeSearchMatchIndex + delta) % ranges.count + ranges.count) % ranges.count
        jumpToSearchMatch(at: next)
    }

    // MARK: - Custom MUNSC Rules

    @discardableResult
    func addCustomRule(token: String, normalized: String, description: String = "", isRegex: Bool = false) -> Bool {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNormalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty, !cleanNormalized.isEmpty, cleanToken != cleanNormalized else {
            return false
        }

        if let existingIdx = customRules.firstIndex(where: { $0.pattern == cleanToken && $0.isRegex == isRegex }) {
            let existingName = customRules[existingIdx].name
            customRules[existingIdx] = MUNSCRule(
                name: existingName,
                pattern: cleanToken,
                replacement: cleanNormalized,
                isRegex: isRegex,
                description: cleanDescription.isEmpty
                    ? "Custom MUNSC '\(cleanToken)' -> '\(cleanNormalized)'"
                    : cleanDescription
            )
        } else {
            let slug = cleanToken.map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
            var candidateName = "custom_\(slug)"
            var suffix = 2
            while customRules.contains(where: { $0.name == candidateName }) {
                candidateName = "custom_\(slug)_\(suffix)"
                suffix += 1
            }
            customRules.append(
                MUNSCRule(
                    name: candidateName,
                    pattern: cleanToken,
                    replacement: cleanNormalized,
                    isRegex: isRegex,
                    description: cleanDescription.isEmpty
                        ? "Custom MUNSC '\(cleanToken)' -> '\(cleanNormalized)'"
                        : cleanDescription
                )
            )
        }
        saveCustomRules()
        spellcheckRevision += 1
        return true
    }

    func deleteCustomRule(name: String) {
        customRules.removeAll { $0.name == name }
        saveCustomRules()
        spellcheckRevision += 1
    }

    @discardableResult
    func importCustomRules(_ incoming: [MUNSCRule]) -> Int {
        var added = 0
        for rule in incoming {
            guard !rule.pattern.isEmpty, rule.pattern != rule.replacement else { continue }
            let alreadyExists = customRules.contains {
                $0.pattern == rule.pattern && $0.replacement == rule.replacement && $0.isRegex == rule.isRegex
            }
            if !alreadyExists {
                var ruleToInsert = rule
                if customRules.contains(where: { $0.name == rule.name }) {
                    let uniqueName = "\(rule.name)_\(String(UUID().uuidString.prefix(4)).lowercased())"
                    ruleToInsert = MUNSCRule(
                        name: uniqueName,
                        pattern: rule.pattern,
                        replacement: rule.replacement,
                        isRegex: rule.isRegex,
                        description: rule.description
                    )
                }
                customRules.append(ruleToInsert)
                added += 1
            }
        }
        if added > 0 {
            saveCustomRules()
            spellcheckRevision += 1
        }
        return added
    }

    // MARK: - Shareable AXIF Export & Import

    func exportCleanWithAXIFFooter(for note: StoredNote? = nil) -> String? {
        let target = note ?? selectedNote
        guard let doc = target?.compiledDocument(urlSafeDash: urlSafeDash, rules: customRules) else {
            return nil
        }
        return try? doc.exportCleanWithAXIFFooter(useBase64: true)
    }

    func exportSlogBogBBCode(for note: StoredNote? = nil) -> String? {
        let target = note ?? selectedNote
        guard let doc = target?.compiledDocument(urlSafeDash: urlSafeDash, rules: customRules) else {
            return nil
        }
        return try? doc.exportSlogBogBBCode()
    }

    func exportMarkdown(
        for note: StoredNote? = nil,
        includeFrontmatter: Bool = true,
        includeAXIFFooter: Bool = true,
        useRawText: Bool = false
    ) -> String? {
        let target = note ?? selectedNote
        guard let target else { return nil }
        guard let doc = target.compiledDocument(urlSafeDash: urlSafeDash, rules: customRules) else {
            return nil
        }
        let aaid = target.authorAAid ?? authorAAid
        var text = (try? doc.exportMarkdown(
            title: target.displayTitle,
            authorAAid: aaid,
            includeFrontmatter: includeFrontmatter,
            includeAXIFFooter: includeAXIFFooter,
            useRawText: useRawText
        )) ?? (useRawText ? target.rawText : target.derivedBody)

        for att in target.attachments {
            let marker = att.markerText
            let mdImage = "![\(att.filename)](\(att.relativePath))"
            text = text.replacingOccurrences(of: marker, with: mdImage)
        }
        return text
    }

    @discardableResult
    func importSharedAXIF(_ payload: String, folder: NoteFolder = .quickNotes) throws -> AXIFImportResult {
        let bundle = try AXIFDocument.parseSharedBundle(payload)
        let importedRulesCount = importCustomRules(bundle.metadata.rules)

        let rawText: String
        if let reconstructed = bundle.reconstructedRawText, !reconstructed.isEmpty {
            rawText = reconstructed
        } else if let norm = bundle.normalizedText, !norm.isEmpty {
            rawText = norm
        } else {
            var lines: [String] = [
                bundle.title ?? "Imported AXIF • \(bundle.metadata.acode9)",
                "Acode9: \(bundle.metadata.acode9) | Jesus Clock: \(bundle.metadata.jesusClock)"
            ]
            if !bundle.metadata.entries.isEmpty {
                lines.append("Indexed MUNSC tokens:")
                for entry in bundle.metadata.entries {
                    lines.append("- \(entry.token) -> \(entry.normalizedForm) (\(entry.munscRule) @\(entry.offset))")
                }
            }
            rawText = lines.joined(separator: "\n")
        }

        let now = Date()
        let formattedCode = urlSafeDash
            ? ((try? Acode9.toDash(bundle.metadata.acode9)) ?? bundle.metadata.acode9)
            : ((try? Acode9.toCaret(bundle.metadata.acode9)) ?? bundle.metadata.acode9)

        let newNote = StoredNote(
            rawText: rawText,
            ownerAcode9: formattedCode,
            folder: folder,
            isPinned: false,
            createdAt: now,
            updatedAt: now
        )
        notes.insert(newNote, at: 0)
        activeSidebarFilter = .all
        selectedNoteID = newNote.id
        save()
        spellcheckRevision += 1
        return AXIFImportResult(note: newNote, bundle: bundle, importedRulesCount: importedRulesCount)
    }

    // MARK: - A3odex Browser & "Where's Norma?" Demo

    func insertA3odexToken(_ token: String) {
        if selectedNote == nil {
            createNewNote()
        }
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }

        let current = notes[idx].rawText
        let separator: String
        if current.isEmpty || current.hasSuffix("\n") || current.hasSuffix(" ") {
            separator = ""
        } else {
            separator = " "
        }
        notes[idx].rawText = current + separator + token
        notes[idx].updatedAt = Date()
        save()
        spellcheckRevision += 1
    }

    @discardableResult
    func importA3odex(from url: URL) throws -> Int {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let decoded = try A3odexCatalog.decodeJSON(data)
        var merged = decoded
        for starter in A3odexCatalog.starterEntries {
            if !merged.contains(where: { $0.token == starter.token }) {
                merged.append(starter)
            }
        }
        a3odexEntries = merged
        saveA3odex()
        return decoded.count
    }

    func runWheresNormaDemo() {
        let target: StoredNote
        if let existing = notes.first(where: { $0.folder == .chamberNorma })
            ?? notes.first(where: { $0.rawText.contains("NormA") }) {
            target = existing
        } else {
            let demoNote = Self.makeSeedNotes().first ?? StoredNote(
                rawText: "N0rma — Chamber Luncheon & Trailhead Log\nMet NormA at the trailhead, confirmed coordinates with Norm4, and archived Norma4 in the AXIF ledger.",
                ownerAcode9: "Ab2p^a40z",
                folder: .chamberNorma,
                isPinned: true
            )
            notes.insert(demoNote, at: 0)
            save()
            target = demoNote
        }

        if !filteredNotes.contains(where: { $0.id == target.id }) {
            activeSidebarFilter = .folder(target.folder)
        }
        selectedNoteID = target.id
        caseSensitive = true
        wholeWord = false
        useRegex = false
        searchLayer = .dual
        viewMode = .clean
        query = "NormA"
        showFindBar = true
    }

    // MARK: - Note Editing & CRUD

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
            harvestRecentEmojis(from: newText)
            save()
        }
    }

    func harvestRecentEmojis(from text: String) {
        if text.contains("🔻🔻") && !recentEmojis.contains("🔻🔻") {
            recentEmojis.append("🔻🔻")
        }
        if text.contains("🔺🔺") && !recentEmojis.contains("🔺🔺") {
            recentEmojis.append("🔺🔺")
        }
        for char in text {
            for scalar in char.unicodeScalars {
                if scalar.properties.isEmoji && (scalar.properties.isEmojiPresentation || scalar.value > 0x2388) {
                    let s = String(char)
                    if s != "🔻" && s != "🔺" && !recentEmojis.contains(s) {
                        recentEmojis.append(s)
                    }
                    break
                }
            }
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
              let doc = note.compiledDocument(urlSafeDash: urlSafeDash, rules: customRules),
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

    // MARK: - Skip Vowels, ii / is5 Quick Actions & Attachments

    func suggestSkipVowels(for token: String) -> SkipVowelsSuggestion? {
        let knownEntries: [(token: String, canonical: String)] =
            customRules.map { ($0.pattern, $0.replacement) }
            + a3odexEntries.map { ($0.token, $0.canonical) }
        let extraLexicon = a3odexEntries.map(\.canonical) + customRules.map(\.replacement)
        return SkipVowelsHelper.bestSuggestion(
            for: token,
            knownEntries: knownEntries,
            extraLexicon: extraLexicon
        )
    }

    func openSkipVowelsPrompt(token: String, rangeLocation: Int, rangeLength: Int) {
        guard let noteID = selectedNote?.id else { return }
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        let suggested = suggestSkipVowels(for: cleanToken)?.normalized ?? cleanToken
        skipVowelsPrompt = SkipVowelsPromptRequest(
            noteID: noteID,
            token: cleanToken,
            suggestedNormalized: suggested,
            rangeLocation: rangeLocation,
            rangeLength: rangeLength
        )
    }

    @discardableResult
    func addSkipVowelsRule(token: String, normalized: String) -> Bool {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNormalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty, !cleanNormalized.isEmpty else { return false }

        applyLearnWord(token: cleanToken)

        if cleanToken != cleanNormalized {
            return addCustomRule(
                token: cleanToken,
                normalized: cleanNormalized,
                description: "Skip vowels verified"
            )
        }
        return true
    }

    func applyAppendII(token: String, location: Int, length: Int) {
        let updated = VerificationTagHelper.appendII(to: token)
        guard !updated.isEmpty else { return }
        applyReplaceSpan(location: location, length: length, with: updated, learnWord: updated)
    }

    func applyAppendIS5(token: String, location: Int, length: Int) {
        let updated = VerificationTagHelper.appendIS5(to: token)
        guard !updated.isEmpty else { return }
        applyReplaceSpan(location: location, length: length, with: updated, learnWord: updated)
    }

    func applyReplaceSpan(location: Int, length: Int, with replacement: String, learnWord: String? = nil) {
        if let learnWord, !learnWord.isEmpty {
            SpellcheckHelper.learnWord(learnWord)
        }
        if let handler = activeTextViewActionHandler,
           handler(.replaceRange(location: location, length: length, with: replacement, learnWord: learnWord)) {
            spellcheckRevision += 1
            return
        }

        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let ns = notes[idx].rawText as NSString
        guard location >= 0, length >= 0, location + length <= ns.length else { return }
        notes[idx].rawText = ns.replacingCharacters(in: NSRange(location: location, length: length), with: replacement)
        notes[idx].updatedAt = Date()
        cursorSpellTarget = nil
        spellcheckRevision += 1
        save()
    }

    func applyLearnWord(token: String) {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        SpellcheckHelper.learnWord(clean)
        _ = activeTextViewActionHandler?(.learnOnly(clean))
        if cursorSpellTarget?.word == clean {
            cursorSpellTarget = nil
        }
        spellcheckRevision += 1
    }

    func attachmentsDirectoryURL() -> URL {
        activeSyncFolderURL.appendingPathComponent("attachments", isDirectory: true)
    }

    func attachmentFileURL(for attachment: NoteAttachment) -> URL {
        activeSyncFolderURL.appendingPathComponent(attachment.relativePath)
    }

    func readAttachmentData(for attachment: NoteAttachment) -> Data? {
        let targetURL = attachmentFileURL(for: attachment)
        return withFolderAccess(activeSyncFolderURL) {
            try? Data(contentsOf: targetURL)
        }
    }

    @discardableResult
    func saveImageAttachment(
        pngData: Data,
        filename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        exactUnixTimestamp: Int64? = nil,
        base38TimestampTag: String? = nil
    ) -> NoteAttachment? {
        guard let id = selectedNote?.id,
              let idx = notes.firstIndex(where: { $0.id == id }) else { return nil }

        let attachmentID = UUID()
        let relativePath = "attachments/\(attachmentID.uuidString).png"
        let targetURL = activeSyncFolderURL.appendingPathComponent(relativePath)

        var writeSucceeded = false
        withFolderAccess(activeSyncFolderURL) {
            let dir = attachmentsDirectoryURL()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try pngData.write(to: targetURL, options: .atomic)
                writeSucceeded = true
            } catch {
                writeSucceeded = false
            }
        }
        guard writeSucceeded else { return nil }

        let resolvedTs = exactUnixTimestamp ?? Int64(Date().timeIntervalSince1970)
        let resolvedTag = base38TimestampTag ?? Base38Clock.cleanExactClockExpression(
            unixSeconds: resolvedTs,
            contextWords: [filename],
            maxLength: 17
        ).expression

        let cleanName = filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Capture \(resolvedTag).png"
            : filename.trimmingCharacters(in: .whitespacesAndNewlines)

        let attachment = NoteAttachment(
            id: attachmentID,
            filename: cleanName,
            relativePath: relativePath,
            pixelWidth: max(1, pixelWidth),
            pixelHeight: max(1, pixelHeight),
            createdAt: Date(),
            exactUnixTimestamp: resolvedTs,
            base38TimestampTag: resolvedTag
        )
        notes[idx].attachments.append(attachment)
        notes[idx].updatedAt = Date()
        save()
        return attachment
    }

    func requestCopyWithImages(text: String, isSelectAll: Bool) -> Bool {
        guard let note = selectedNote, !note.attachments.isEmpty else {
            return false
        }
        let matched = note.attachments.filter { text.contains($0.markerText) }
        guard !matched.isEmpty || isSelectAll else {
            return false
        }
        let preselected: Set<UUID> = matched.isEmpty
            ? Set(note.attachments.map(\.id))
            : Set(matched.map(\.id))
        activeCopyWithImagesRequest = CopyWithImagesRequest(
            noteID: note.id,
            selectedText: text,
            attachments: note.attachments,
            preselectedAttachmentIDs: preselected,
            appendUnreferenced: isSelectAll || matched.isEmpty
        )
        return true
    }

    #if os(macOS)
    func performCopyForAppleNotes(
        text: String,
        attachments: [NoteAttachment],
        includedAttachmentIDs: Set<UUID>,
        appendUnreferenced: Bool,
        expandTabs: Bool = true
    ) {
        let workingText = expandTabs ? text.replacingOccurrences(of: "\t", with: "   ") : text
        let baseFont = NSFont.systemFont(ofSize: CGFloat(editorFontSize))
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ]

        struct MarkerHit {
            let range: Range<String.Index>
            let attachment: NoteAttachment
        }

        var hits: [MarkerHit] = []
        for att in attachments {
            let marker = att.markerText
            var searchStart = workingText.startIndex
            while searchStart < workingText.endIndex,
                  let found = workingText.range(of: marker, range: searchStart..<workingText.endIndex) {
                hits.append(MarkerHit(range: found, attachment: att))
                searchStart = found.upperBound
            }
        }
        hits.sort { $0.range.lowerBound < $1.range.lowerBound }

        let attributed = NSMutableAttributedString()
        var plainParts: [String] = []
        var referencedIDs: Set<UUID> = []
        var cursor = workingText.startIndex

        for hit in hits {
            if hit.range.lowerBound < cursor {
                continue
            }
            if cursor < hit.range.lowerBound {
                let chunk = String(workingText[cursor..<hit.range.lowerBound])
                attributed.append(NSAttributedString(string: chunk, attributes: baseAttrs))
                plainParts.append(chunk)
            }
            referencedIDs.insert(hit.attachment.id)
            if includedAttachmentIDs.contains(hit.attachment.id),
               let pngData = readAttachmentData(for: hit.attachment) {
                let wrapper = FileWrapper(regularFileWithContents: pngData)
                wrapper.preferredFilename = hit.attachment.filename
                let textAtt = NSTextAttachment(fileWrapper: wrapper)
                if let crisp = RetinaImageSupport.makeCrispNSImage(from: pngData) {
                    textAtt.image = crisp
                    textAtt.bounds = NSRect(origin: .zero, size: crisp.size)
                }
                attributed.append(NSAttributedString(attachment: textAtt))
            }
            cursor = hit.range.upperBound
        }

        if cursor < workingText.endIndex {
            let tail = String(workingText[cursor..<workingText.endIndex])
            attributed.append(NSAttributedString(string: tail, attributes: baseAttrs))
            plainParts.append(tail)
        }

        if appendUnreferenced {
            for att in attachments where includedAttachmentIDs.contains(att.id) && !referencedIDs.contains(att.id) {
                if let pngData = readAttachmentData(for: att) {
                    if attributed.length > 0 && !attributed.string.hasSuffix("\n") {
                        attributed.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                    }
                    let wrapper = FileWrapper(regularFileWithContents: pngData)
                    wrapper.preferredFilename = att.filename
                    let textAtt = NSTextAttachment(fileWrapper: wrapper)
                    if let crisp = RetinaImageSupport.makeCrispNSImage(from: pngData) {
                        textAtt.image = crisp
                        textAtt.bounds = NSRect(origin: .zero, size: crisp.size)
                    }
                    attributed.append(NSAttributedString(attachment: textAtt))
                }
            }
        }

        let plainFallback = plainParts.joined()
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .newlines)

        let pb = NSPasteboard.general
        pb.clearContents()
        if !includedAttachmentIDs.isEmpty,
           attributed.length > 0,
           let rtfdData = try? attributed.data(
               from: NSRange(location: 0, length: attributed.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
           ) {
            let item = NSPasteboardItem()
            item.setData(rtfdData, forType: .rtfd)
            if let rtfData = try? attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                item.setData(rtfData, forType: .rtf)
            }
            item.setString(plainFallback.isEmpty ? workingText : plainFallback, forType: .string)
            pb.writeObjects([item])
        } else {
            pb.writeObjects([(plainFallback.isEmpty ? workingText : plainFallback) as NSString])
        }
    }
    #endif

    @discardableResult
    func smartRenameAttachment(
        _ attachment: NoteAttachment,
        in noteID: UUID,
        subjectInput: String,
        appendBase38Tag: Bool = true,
        alwaysUseDifferenceFormula: Bool = true
    ) -> NoteAttachment? {
        let trimmedSubject = subjectInput
            .replacingOccurrences(of: ".png", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let exactTs = attachment.exactUnixTimestamp ?? Int64(attachment.createdAt.timeIntervalSince1970)
        let contextWords = trimmedSubject.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let clockExpr = Base38Clock.cleanExactClockExpression(
            unixSeconds: exactTs,
            contextWords: contextWords,
            maxLength: 17,
            alwaysUseDifferenceFormula: alwaysUseDifferenceFormula
        ).expression

        let finalStem: String
        if trimmedSubject.isEmpty {
            finalStem = clockExpr
        } else if appendBase38Tag && !trimmedSubject.contains(clockExpr) {
            finalStem = "\(trimmedSubject) \(clockExpr)"
        } else {
            finalStem = trimmedSubject
        }
        return renameAttachment(
            attachment,
            in: noteID,
            newFilename: "\(finalStem).png",
            exactUnixTimestamp: exactTs,
            base38TimestampTag: clockExpr
        )
    }

    @discardableResult
    func renameAttachment(
        _ attachment: NoteAttachment,
        in noteID: UUID,
        newFilename: String,
        exactUnixTimestamp: Int64? = nil,
        base38TimestampTag: String? = nil
    ) -> NoteAttachment? {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }),
              let attIdx = notes[idx].attachments.firstIndex(where: { $0.id == attachment.id }) else {
            return nil
        }
        let clean = newFilename
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        let oldMarker = notes[idx].attachments[attIdx].markerText
        notes[idx].attachments[attIdx].filename = clean
        if let exactUnixTimestamp {
            notes[idx].attachments[attIdx].exactUnixTimestamp = exactUnixTimestamp
        }
        if let base38TimestampTag {
            notes[idx].attachments[attIdx].base38TimestampTag = base38TimestampTag
        }
        let updated = notes[idx].attachments[attIdx]
        let newMarker = updated.markerText

        if oldMarker != newMarker && notes[idx].rawText.contains(oldMarker) {
            notes[idx].rawText = notes[idx].rawText.replacingOccurrences(of: oldMarker, with: newMarker)
        }
        notes[idx].updatedAt = Date()
        if activeLightboxRequest?.attachment.id == attachment.id {
            activeLightboxRequest = RetinaLightboxRequest(noteID: noteID, attachment: updated)
        }
        save()
        return updated
    }

    func deleteAttachment(_ attachment: NoteAttachment, from noteID: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].attachments.removeAll { $0.id == attachment.id }

        let marker = attachment.markerText
        if notes[idx].rawText.contains(marker) {
            var updated = notes[idx].rawText
                .replacingOccurrences(of: "\n\(marker)\n", with: "\n")
                .replacingOccurrences(of: "\n\(marker)", with: "")
                .replacingOccurrences(of: "\(marker)\n", with: "")
                .replacingOccurrences(of: marker, with: "")
            updated = updated.trimmingCharacters(in: CharacterSet(charactersIn: ""))
            notes[idx].rawText = updated
        }
        notes[idx].updatedAt = Date()

        let fileURL = attachmentFileURL(for: attachment)
        withFolderAccess(activeSyncFolderURL) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if activeLightboxRequest?.attachment.id == attachment.id {
            activeLightboxRequest = nil
        }
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
        query = ""
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

    // MARK: - Persistence

    func loadOrSeed() {
        let loaded: [StoredNote]? = withFolderAccess(activeSyncFolderURL) {
            for candidateURL in [storageURL, backupURL] {
                if let data = try? Data(contentsOf: candidateURL),
                   let decoded = try? JSONDecoder().decode([StoredNote].self, from: data),
                   !decoded.isEmpty {
                    return decoded
                }
            }
            return nil
        }

        if let loaded {
            notes = loaded
            selectedNoteID = filteredNotes.first?.id
            harvestAscenderRecentEmojis()
            return
        }

        withFolderAccess(activeSyncFolderURL) {
            let fm = FileManager.default
            if fm.fileExists(atPath: storageURL.path),
               let existingData = try? Data(contentsOf: storageURL),
               !existingData.isEmpty {
                let ts = Int(Date().timeIntervalSince1970)
                let recoveryURL = activeSyncFolderURL.appendingPathComponent("notes.recovery-\(ts).json")
                try? existingData.write(to: recoveryURL, options: .atomic)
            }
        }

        notes = Self.makeSeedNotes()
        selectedNoteID = notes.first?.id
        harvestAscenderRecentEmojis()
        save()
    }

    func harvestAscenderRecentEmojis() {
        var found: [String] = []
        for note in notes.prefix(40) {
            if note.rawText.contains("🔻🔻") && !found.contains("🔻🔻") {
                found.append("🔻🔻")
            }
            if note.rawText.contains("🔺🔺") && !found.contains("🔺🔺") {
                found.append("🔺🔺")
            }
            for char in note.rawText {
                for scalar in char.unicodeScalars {
                    if scalar.properties.isEmoji && (scalar.properties.isEmojiPresentation || scalar.value > 0x2388) {
                        let s = String(char)
                        if s != "🔻" && s != "🔺" && !found.contains(s) {
                            found.append(s)
                        }
                        break
                    }
                }
            }
        }
        for em in found.reversed() {
            registerRecentEmoji(em)
        }
    }

    @discardableResult
    func flushAndSave() -> Bool {
        _ = activeTextViewActionHandler?(.flushAndSave)
        save()
        return lastSaveError == nil
    }

    func save() {
        withFolderAccess(activeSyncFolderURL) {
            let dir = storageURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(notes)
                if FileManager.default.fileExists(atPath: storageURL.path) {
                    try? FileManager.default.removeItem(at: backupURL)
                    try? FileManager.default.copyItem(at: storageURL, to: backupURL)
                }
                try data.write(to: storageURL, options: .atomic)
                lastSaveError = nil
                lastSyncDate = Date()
                lastSyncStatus = "Saved \(Date().formatted(date: .omitted, time: .shortened))"
            } catch {
                lastSaveError = error.localizedDescription
                lastSyncStatus = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadCustomRules() {
        let loaded: [MUNSCRule]? = withFolderAccess(activeSyncFolderURL) {
            guard let data = try? Data(contentsOf: munscRulesURL) else { return nil }
            return try? JSONDecoder().decode([MUNSCRule].self, from: data)
        }
        customRules = loaded ?? []
    }

    private func saveCustomRules() {
        withFolderAccess(activeSyncFolderURL) {
            let dir = munscRulesURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(customRules) {
                try? data.write(to: munscRulesURL, options: .atomic)
            }
        }
    }

    private func loadVault() {
        let loaded: [Acode9PoolEntry]? = withFolderAccess(activeSyncFolderURL) {
            guard let data = try? Data(contentsOf: vaultURL) else { return nil }
            return try? JSONDecoder().decode([Acode9PoolEntry].self, from: data)
        }
        if let loaded {
            unusedAcodeVault = loaded
        } else {
            harvestUnusedAcodes(count: 10)
        }
    }

    private func saveVault() {
        withFolderAccess(activeSyncFolderURL) {
            let dir = vaultURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(unusedAcodeVault) {
                try? data.write(to: vaultURL, options: .atomic)
            }
        }
    }

    private func loadA3odex() {
        let loaded: [A3odexEntry]? = withFolderAccess(activeSyncFolderURL) {
            guard let data = try? Data(contentsOf: a3odexURL) else { return nil }
            return try? A3odexCatalog.decodeJSON(data)
        }
        if let loaded, !loaded.isEmpty {
            var merged = loaded
            for starter in A3odexCatalog.starterEntries {
                if !merged.contains(where: { $0.token == starter.token }) {
                    merged.append(starter)
                }
            }
            a3odexEntries = merged
        } else {
            a3odexEntries = A3odexCatalog.starterEntries
        }
    }

    private func saveA3odex() {
        withFolderAccess(activeSyncFolderURL) {
            let dir = a3odexURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(a3odexEntries) {
                try? data.write(to: a3odexURL, options: .atomic)
            }
        }
    }

    private static func makeSeedNotes() -> [StoredNote] {
        let now = Date()
        let baseTs = TimeInterval(Base38Clock.t0Unix + 210_661_380)
        let refDate = Date(timeIntervalSince1970: max(now.timeIntervalSince1970, baseTs))

        return [
            StoredNote(
                rawText: """
                N0rma — Where's Norma? Chamber & Trailhead Log
                Field note authored under Acode9 Ab2p^a40z (Jesus Clock 2p15ek) in Anotes.
                Met NormA at the trailhead, confirmed coordinates with Norm4, and archived Norma4 in the AXIF ledger.
                WhrNrmA and WhrNrmB (skipping the vowels) are both 7-char SvnUNCs; NrmA and NrmB are 4-char FUNs; GSii and i9or1 / is5 keep search hierarchy clean without blue grammar squiggles.
                Tip: Click or right-click any red-underlined token (WhrNrmA, NrmA, GSii, Anotes) for Skip Vowels, +ii, +is5, and Learn quick actions — or drop a Retina screenshot right into this note!
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
                - Solving "Where's Norma?" with N0rma, WhrNrmA, WhrNrmB, NrmA, NrmB, GSii, i9or1, and AXIF
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
