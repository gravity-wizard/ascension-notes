import AscensionCore
import Foundation

#if canImport(SwiftUI)
import Observation
import SwiftUI

@main
struct AscensionNotesApp: App {
    var body: some Scene {
        WindowGroup("Ascension Notes — Hydrogen4^high-mode5") {
            AscensionWorkspaceView()
        }
    }
}

@MainActor
@Observable
final class NotesWorkspaceModel {
    enum ViewLayerMode: String, CaseIterable, Identifiable {
        case normalized = "Normalized"
        case raw = "Raw MUNSC"
        var id: String { rawValue }
    }

    var title: String = "Summit Observation Log"
    var ownerAcode9: String = "Ab2p^a40z"
    var rawText: String = """
    Field note authored under Acode9 Ab2p^a40z (Jesus Clock 2p15ek).
    Met NormA at the trailhead, confirmed coordinates with Norm4, and archived Norma4 in the AXIF ledger.
    Future milestone reference: Ac3x^chch and archival token Ab2p^0oyu.
    """

    var viewMode: ViewLayerMode = .normalized
    var query: String = "NormA"
    var caseSensitive: Bool = true
    var wholeWord: Bool = false
    var useRegex: Bool = false
    var searchLayer: SearchLayer = .dual
    var urlSafeDash: Bool = false
    var rollingPool: [Acode9PoolEntry] = []

    var document: AXIFDocument? {
        try? AXIFDocument(
            title: title,
            rawText: rawText,
            ownerAcode9: normalizedOwnerCode,
            timestampUnix: Base38Clock.t0Unix + 210_661_380
        )
    }

    var normalizedOwnerCode: String {
        if urlSafeDash {
            return (try? Acode9.toDash(ownerAcode9)) ?? ownerAcode9
        }
        return (try? Acode9.toCaret(ownerAcode9)) ?? ownerAcode9
    }

    var validation: Acode9ValidationResult {
        Acode9.validate(normalizedOwnerCode, strict: true, allowDash: true)
    }

    var displayedText: String {
        guard let doc = document else { return rawText }
        return doc.render(normalized: viewMode == .normalized)
    }

    var searchMatches: [SearchMatch] {
        guard let doc = document, !query.isEmpty else { return [] }
        let options = SearchOptions(
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            regex: useRegex,
            layer: searchLayer
        )
        return (try? CaseSensitiveSearch.search(document: doc, query: query, options: options)) ?? []
    }

    var searchErrorMessage: String? {
        guard useRegex, !query.isEmpty, let doc = document else { return nil }
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
}

struct AscensionWorkspaceView: View {
    @State private var model = NotesWorkspaceModel()

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationTitle("AXIF Inspector")
        } detail: {
            editorAndSearchView
                .navigationTitle(model.title)
        }
        .onAppear {
            if model.rollingPool.isEmpty {
                model.generateNextPool()
            }
        }
    }

    private var editorAndSearchView: some View {
        VStack(spacing: 12) {
            xcodeSearchBar

            HStack {
                Picker("View Layer", selection: $model.viewMode) {
                    ForEach(NotesWorkspaceModel.ViewLayerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Spacer()

                Text("\(model.searchMatches.count) match(es)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            if let errorMsg = model.searchErrorMessage {
                Text("Regex error: \(errorMsg)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            GroupBox(model.viewMode == .normalized ? "Normalized Output (Clean View)" : "Raw MUNSC Source") {
                if model.viewMode == .raw {
                    TextEditor(text: $model.rawText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                } else {
                    ScrollView {
                        Text(highlightedNormalizedAttributedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(6)
                    }
                    .frame(minHeight: 180)
                }
            }
            .padding(.horizontal)

            GroupBox("Xcode-Style Dual-Layer Search Results") {
                if model.searchMatches.isEmpty {
                    Text(model.query.isEmpty ? "Enter a query to search." : "No matches found.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    List(model.searchMatches) { hit in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("L\(hit.lineNumber):C\(hit.column)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(hit.matchedText)
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                if let entry = hit.axifEntry {
                                    Text("→ \(entry.normalizedForm) [\(entry.munscRule)]")
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                }
                                Spacer()
                                Text(hit.layer.rawValue.uppercased())
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(hit.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 140)
                }
            }
            .padding([.horizontal, .bottom])
        }
        .padding(.top, 8)
    }

    private var xcodeSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find (NormA, Norm4, Norma4, Norma...)", text: $model.query)
                .textFieldStyle(.roundedBorder)

            Toggle(isOn: $model.caseSensitive) {
                Text("Aa")
                    .font(.system(.caption, design: .monospaced).bold())
            }
            .toggleStyle(.button)
            .help("Case-Sensitive (Xcode Aa)")

            Toggle(isOn: $model.wholeWord) {
                Text("W")
                    .font(.system(.caption, design: .monospaced).bold())
            }
            .toggleStyle(.button)
            .help("Whole Word")

            Toggle(isOn: $model.useRegex) {
                Text(".*")
                    .font(.system(.caption, design: .monospaced).bold())
            }
            .toggleStyle(.button)
            .help("Regular Expression")

            Picker("Layer", selection: $model.searchLayer) {
                Text("Dual AXIF").tag(SearchLayer.dual)
                Text("Normalized").tag(SearchLayer.normalized)
                Text("Raw MUNSC").tag(SearchLayer.raw)
            }
            .frame(maxWidth: 130)
        }
        .padding(.horizontal)
    }

    private var sidebarView: some View {
        List {
            Section("Owner Acode9") {
                HStack {
                    TextField("Owner Acode9", text: $model.ownerAcode9)
                        .font(.system(.body, design: .monospaced))
                    Toggle("URL -", isOn: $model.urlSafeDash)
                        .toggleStyle(.button)
                }
                HStack {
                    Label(
                        model.validation.valid ? "Valid good1a" : "Check Failed",
                        systemImage: model.validation.valid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.validation.valid ? .green : .orange)
                    .font(.caption)
                    Spacer()
                    Text(model.normalizedOwnerCode)
                        .font(.caption.monospaced())
                }
                if let doc = model.document {
                    LabeledContent("Jesus Clock", value: doc.axif.jesusClock)
                        .font(.caption.monospaced())
                    LabeledContent("MUNSC Count", value: "\(doc.axif.munscCount)")
                        .font(.caption.monospaced())
                }
            }

            Section("AXIF Metadata Index") {
                if let entries = model.document?.axif.entries, !entries.isEmpty {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.token)
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                Text("→")
                                    .foregroundStyle(.secondary)
                                Text(entry.normalizedForm)
                                    .font(.subheadline)
                                Spacer()
                                Text("@\(entry.offset)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(entry.acode9) • \(entry.munscRule)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No MUNSC entries indexed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Generate 1s Rolling Pool") {
                    model.generateNextPool()
                }
                ForEach(model.rollingPool) { item in
                    HStack {
                        Text(item.acode9)
                            .font(.caption.monospaced())
                        Spacer()
                        Text(item.jesusClock)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("1s Cadence Pool (good1a)")
            }
        }
    }

    private var highlightedNormalizedAttributedText: AttributedString {
        let base = model.displayedText
        var attributed = AttributedString(base)
        for hit in model.searchMatches {
            guard hit.normalizedOffset >= 0,
                  hit.normalizedEnd <= base.count,
                  hit.normalizedOffset < hit.normalizedEnd else { continue }
            let startStrIdx = base.index(base.startIndex, offsetBy: hit.normalizedOffset)
            let endStrIdx = base.index(base.startIndex, offsetBy: hit.normalizedEnd)
            if let attrRange = Range(startStrIdx..<endStrIdx, in: attributed) {
                attributed[attrRange].backgroundColor = Color.yellow.opacity(0.35)
            }
        }
        return attributed
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
