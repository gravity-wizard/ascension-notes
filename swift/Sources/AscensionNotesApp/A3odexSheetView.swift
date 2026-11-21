import AscensionCore
import Foundation

#if canImport(SwiftUI)
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct A3odexSheetView: View {
    @Bindable var store: NotesStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTier: A3odexTier? = nil
    @State private var searchText: String = ""
    @State private var showJSONImporter: Bool = false
    @State private var statusMessage: String?
    @State private var isErrorStatus: Bool = false

    private let notesGold = Color(red: 0.90, green: 0.64, blue: 0.08)

    private var filteredEntries: [A3odexEntry] {
        let base: [A3odexEntry]
        if let tier = selectedTier {
            base = store.a3odexEntries.filter { $0.tier == tier }
        } else {
            base = store.a3odexEntries
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { entry in
            entry.token.localizedCaseInsensitiveContains(q)
                || entry.canonical.localizedCaseInsensitiveContains(q)
                || entry.meaning.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                demoBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(spacing: 8) {
                    Picker("Tier", selection: $selectedTier) {
                        Text("All (\(store.a3odexEntries.count))").tag(A3odexTier?.none)
                        ForEach(A3odexTier.allCases) { tier in
                            Text(tier.displayTitle).tag(A3odexTier?.some(tier))
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter A3odex tokens or meanings...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if let msg = statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: isErrorStatus ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        Text(msg)
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(isErrorStatus ? .red : .green)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                Divider()

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Matching A3odex Entries",
                        systemImage: "books.vertical",
                        description: Text("Try another tier or import an a3odex.json file from disk.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredEntries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(entry.token)
                                        .font(.system(.headline, design: .monospaced).bold())
                                        .textSelection(.enabled)
                                    Text("→ \(entry.canonical)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("\(entry.tier.rawValue) • \(entry.tier.charBadge)")
                                        .font(.caption2.monospaced().weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(notesGold.opacity(0.18))
                                        .foregroundStyle(notesGold)
                                        .clipShape(Capsule())
                                }
                                if !entry.meaning.isEmpty {
                                    Text(entry.meaning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                store.insertA3odexToken(entry.token)
                                isErrorStatus = false
                                statusMessage = "Inserted '\(entry.token)' into \(store.selectedNote?.displayTitle ?? "note")"
                            } label: {
                                Label("Insert into Note", systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Codex / A3odex (4-Tier)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    #if canImport(UniformTypeIdentifiers)
                    Button {
                        showJSONImporter = true
                    } label: {
                        Label("Import a3odex.json", systemImage: "square.and.arrow.down")
                    }
                    #endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(
                isPresented: $showJSONImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    do {
                        let count = try store.importA3odex(from: url)
                        isErrorStatus = false
                        statusMessage = "Imported \(count) A3odex entries from \(url.lastPathComponent)"
                    } catch {
                        isErrorStatus = true
                        statusMessage = error.localizedDescription
                    }
                case .failure(let error):
                    isErrorStatus = true
                    statusMessage = error.localizedDescription
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 520)
        #endif
    }

    private var demoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title2)
                .foregroundStyle(notesGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\"Where's Norma?\" Case-Sensitivity Demo")
                    .font(.headline)
                Text("Opens the Chamber • Norma note, turns ON Aa, switches to Clean View, and searches NormA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.runWheresNormaDemo()
                dismiss()
            } label: {
                Label("Run \"Where's Norma?\" Aa Demo", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(notesGold)
        }
        .padding(12)
        .background(notesGold.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(notesGold.opacity(0.35), lineWidth: 1)
        )
    }
}
#endif
