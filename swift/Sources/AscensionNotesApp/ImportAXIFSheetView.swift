import AscensionCore
import Foundation

#if canImport(SwiftUI)
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ImportAXIFSheetView: View {
    @Bindable var store: NotesStore
    @Environment(\.dismiss) private var dismiss

    @State private var payloadText: String = ""
    @State private var targetFolder: NoteFolder = .quickNotes
    @State private var errorMessage: String?

    private let notesGold = Color(red: 0.90, green: 0.64, blue: 0.08)

    private var parsedPreview: Result<AXIFDecodedBundle, Error>? {
        let trimmed = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Result { try AXIFDocument.parseSharedBundle(trimmed) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Paste any AXIF JSON, Clean + [AXIF: ...] footer, or SlogBog phpBBog post.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if let clip = readClipboardString() {
                            payloadText = clip
                            errorMessage = nil
                        }
                    } label: {
                        Label("Paste Clipboard", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                TextEditor(text: $payloadText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(6)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                Picker("Import into Folder", selection: $targetFolder) {
                    ForEach(NoteFolder.allCases) { folder in
                        Text(folder.rawValue).tag(folder)
                    }
                }
                .pickerStyle(.menu)

                verificationSection

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .navigationTitle("Import Shared AXIF Bundle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import & Create Note") {
                        do {
                            _ = try store.importSharedAXIF(payloadText, folder: targetFolder)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(isImportDisabled)
                    .buttonStyle(.borderedProminent)
                    .tint(notesGold)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 580, minHeight: 480)
        #endif
    }

    private var isImportDisabled: Bool {
        guard case .success = parsedPreview else { return true }
        return false
    }

    @ViewBuilder
    private var verificationSection: some View {
        switch parsedPreview {
        case .none:
            Text("Waiting for AXIF snippet...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failure(let err):
            Label(err.localizedDescription, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .success(let bundle):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("Verified \(bundle.sourceFormat)", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(bundle.metadata.acode9)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(notesGold)
                    Text("Clock: \(bundle.metadata.jesusClock)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text("MUNSCs: \(bundle.metadata.munscCount)")
                        .font(.caption2)
                    Text("Embedded Rules: \(bundle.metadata.rules.count)")
                        .font(.caption2)
                    if let normMatch = bundle.normalizedSHA256Matches {
                        Label(
                            normMatch ? "Clean SHA-256 Match" : "Clean SHA-256 Differs",
                            systemImage: normMatch ? "lock.shield.fill" : "exclamationmark.shield"
                        )
                        .font(.caption2)
                        .foregroundStyle(normMatch ? .green : .orange)
                    }
                    if let rawMatch = bundle.rawSHA256Matches {
                        Label(
                            rawMatch ? "Raw SHA-256 Match" : "Raw SHA-256 Differs",
                            systemImage: rawMatch ? "lock.shield.fill" : "exclamationmark.shield"
                        )
                        .font(.caption2)
                        .foregroundStyle(rawMatch ? .green : .orange)
                    }
                }

                if let rawPreview = bundle.reconstructedRawText ?? bundle.normalizedText {
                    Text(rawPreview)
                        .font(.caption)
                        .lineLimit(4)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
            .background(Color.green.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func readClipboardString() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #elseif canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }
}
#endif
