import Foundation

#if canImport(SwiftUI)
import SwiftUI
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private let retinaGold = Color(red: 0.90, green: 0.64, blue: 0.08)

struct CrispRetinaImage: Sendable {
    let cgImage: CGImage
    let pixelWidth: Int
    let pixelHeight: Int
    let backingScale: CGFloat
    let logicalSize: CGSize
}

@MainActor
enum RetinaImageSupport {
    struct PreparedPNG: Sendable {
        let pngData: Data
        let pixelWidth: Int
        let pixelHeight: Int
        let filename: String
    }

    static var currentBackingScale: CGFloat {
        #if os(macOS)
        return max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0)
        #elseif canImport(UIKit)
        return max(1.0, UITraitCollection.current.displayScale)
        #else
        return 2.0
        #endif
    }

    static func loadCrispImage(
        from data: Data,
        backingScale: CGFloat = currentBackingScale
    ) -> CrispRetinaImage? {
        let scale = max(1.0, backingScale)

        #if os(macOS)
        if let rep = NSBitmapImageRep(data: data),
           let cgImage = rep.cgImage {
            let pixelW = rep.pixelsWide > 0 ? rep.pixelsWide : cgImage.width
            let pixelH = rep.pixelsHigh > 0 ? rep.pixelsHigh : cgImage.height
            guard pixelW > 0, pixelH > 0 else { return nil }
            let logicalSize = CGSize(
                width: CGFloat(pixelW) / scale,
                height: CGFloat(pixelH) / scale
            )
            return CrispRetinaImage(
                cgImage: cgImage,
                pixelWidth: pixelW,
                pixelHeight: pixelH,
                backingScale: scale,
                logicalSize: logicalSize
            )
        }
        #endif

        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let pixelW = cgImage.width
        let pixelH = cgImage.height
        guard pixelW > 0, pixelH > 0 else { return nil }
        let logicalSize = CGSize(
            width: CGFloat(pixelW) / scale,
            height: CGFloat(pixelH) / scale
        )
        return CrispRetinaImage(
            cgImage: cgImage,
            pixelWidth: pixelW,
            pixelHeight: pixelH,
            backingScale: scale,
            logicalSize: logicalSize
        )
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "tif", "heic", "heif", "webp", "gif", "bmp"
    ]

    static func isImageFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        if supportedImageExtensions.contains(ext) {
            return true
        }
        if let ut = UTType(filenameExtension: ext) {
            return ut.conforms(to: .image)
        }
        return false
    }

    static func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil {
            return true
        }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           urls.contains(where: { isImageFileURL($0) }) {
            return true
        }
        if let types = pasteboard.types,
           types.contains(.URL),
           let urlStr = pasteboard.string(forType: .URL),
           let url = URL(string: urlStr),
           isImageFileURL(url) {
            return true
        }
        return false
    }

    static func extractImages(from pasteboard: NSPasteboard) -> [PreparedPNG] {
        var prepared: [PreparedPNG] = []

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in urls where isImageFileURL(url) {
                if let item = preparePNG(fromFileURL: url) {
                    prepared.append(item)
                }
            }
        }
        if !prepared.isEmpty {
            return prepared
        }

        if let urlStr = pasteboard.string(forType: .URL),
           let url = URL(string: urlStr),
           isImageFileURL(url),
           let item = preparePNG(fromFileURL: url) {
            return [item]
        }

        if let pngData = pasteboard.data(forType: .png),
           let item = preparePNG(fromData: pngData, filename: defaultScreenshotFilename(), preserveRawPNG: true) {
            return [item]
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let item = preparePNG(fromData: tiffData, filename: defaultScreenshotFilename(), preserveRawPNG: false) {
            return [item]
        }

        return []
    }

    private static func defaultScreenshotFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Screenshot_\(formatter.string(from: Date())).png"
    }

    static func preparePNG(fromFileURL url: URL) -> PreparedPNG? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let baseName = url.deletingPathExtension().lastPathComponent
        let filename = baseName.isEmpty ? defaultScreenshotFilename() : "\(baseName).png"
        let isPNG = url.pathExtension.lowercased() == "png"
        return preparePNG(fromData: data, filename: filename, preserveRawPNG: isPNG)
    }

    static func preparePNG(
        fromData data: Data,
        filename: String,
        preserveRawPNG: Bool
    ) -> PreparedPNG? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let pixelW = cgImage.width
        let pixelH = cgImage.height
        guard pixelW > 0, pixelH > 0 else { return nil }

        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if preserveRawPNG && data.count >= 4 && Array(data.prefix(4)) == pngSignature {
            return PreparedPNG(pngData: data, pixelWidth: pixelW, pixelHeight: pixelH, filename: filename)
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let encoded = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return PreparedPNG(pngData: encoded, pixelWidth: pixelW, pixelHeight: pixelH, filename: filename)
    }

    static func makeCrispNSImage(from data: Data, backingScale: CGFloat = currentBackingScale) -> NSImage? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        let pixelW = rep.pixelsWide
        let pixelH = rep.pixelsHigh
        guard pixelW > 0, pixelH > 0 else { return nil }
        let scale = max(1.0, backingScale)
        let logicalSize = NSSize(
            width: CGFloat(pixelW) / scale,
            height: CGFloat(pixelH) / scale
        )
        rep.size = logicalSize
        let nsImage = NSImage(size: logicalSize)
        nsImage.addRepresentation(rep)
        return nsImage
    }
    #endif
}

struct CrispAttachmentImageView: View {
    @Bindable var store: NotesStore
    let noteID: UUID
    let attachment: NoteAttachment
    let maxDisplayHeight: CGFloat?

    @Environment(\.displayScale) private var displayScale

    private var loadedImage: CrispRetinaImage? {
        guard let data = store.readAttachmentData(for: attachment) else { return nil }
        return RetinaImageSupport.loadCrispImage(from: data, backingScale: displayScale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let crisp = loadedImage {
                let cappedHeight = maxDisplayHeight.map { min($0, crisp.logicalSize.height) } ?? crisp.logicalSize.height
                Image(decorative: crisp.cgImage, scale: crisp.backingScale, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: crisp.logicalSize.width, maxHeight: cappedHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.activeLightboxRequest = RetinaLightboxRequest(noteID: noteID, attachment: attachment)
                    }
                    .help("Click to inspect full-resolution Retina image (\(attachment.pixelWidth)×\(attachment.pixelHeight) px)")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Missing image: \(attachment.filename)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.caption2)
                    .foregroundStyle(retinaGold)
                Text(attachment.filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("\(attachment.pixelWidth)×\(attachment.pixelHeight) px • @\(Int(max(1, displayScale)))x")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("#\(attachment.shortID)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(retinaGold)

                Spacer()

                Button {
                    store.activeLightboxRequest = RetinaLightboxRequest(noteID: noteID, attachment: attachment)
                } label: {
                    Label("Inspect", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)

                #if os(macOS)
                Button {
                    let url = store.attachmentFileURL(for: attachment)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "finder")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Reveal PNG in Finder")
                #endif

                Button(role: .destructive) {
                    store.deleteAttachment(attachment, from: noteID)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Delete Screenshot")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}

struct NoteAttachmentsGalleryView: View {
    @Bindable var store: NotesStore
    let note: StoredNote
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(retinaGold)
                    Text("Screenshots & Attachments (\(note.attachments.count))")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("Retina 1:1 / 2x PNG")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(note.attachments) { attachment in
                            CrispAttachmentImageView(
                                store: store,
                                noteID: note.id,
                                attachment: attachment,
                                maxDisplayHeight: 190
                            )
                            .frame(maxWidth: 380)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }
}

struct RetinaLightboxSheet: View {
    enum ZoomMode: String, CaseIterable, Identifiable {
        case fit = "Fit"
        case actual = "1:1 Actual Size"
        var id: String { rawValue }
    }

    @Bindable var store: NotesStore
    let request: RetinaLightboxRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var zoomMode: ZoomMode = .fit

    private var loadedImage: CrispRetinaImage? {
        guard let data = store.readAttachmentData(for: request.attachment) else { return nil }
        return RetinaImageSupport.loadCrispImage(from: data, backingScale: displayScale)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.attachment.filename)
                            .font(.headline)
                        Text("\(request.attachment.pixelWidth) × \(request.attachment.pixelHeight) px • @\(Int(max(1, displayScale)))x Retina (\(Int(CGFloat(request.attachment.pixelWidth) / max(1, displayScale))) × \(Int(CGFloat(request.attachment.pixelHeight) / max(1, displayScale))) pt)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("Zoom", selection: $zoomMode) {
                        ForEach(ZoomMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)

                    #if os(macOS)
                    Button {
                        let url = store.attachmentFileURL(for: request.attachment)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal", systemImage: "finder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    #endif

                    Button(role: .destructive) {
                        store.deleteAttachment(request.attachment, from: request.noteID)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                if let crisp = loadedImage {
                    if zoomMode == .fit {
                        GeometryReader { _ in
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(decorative: crisp.cgImage, scale: crisp.backingScale, orientation: .up)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: crisp.logicalSize.width, maxHeight: crisp.logicalSize.height)
                                        .padding(16)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            Image(decorative: crisp.cgImage, scale: crisp.backingScale, orientation: .up)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: crisp.logicalSize.width, height: crisp.logicalSize.height)
                                .padding(20)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Image File Not Found",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("Expected lossless PNG at \(request.attachment.relativePath)")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Retina Screenshot Inspector")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 540)
        #endif
    }
}

enum CleanViewContentSegment: Identifiable {
    case text(id: String, rangeOffset: Int, rangeEnd: Int)
    case attachment(id: String, attachment: NoteAttachment)

    var id: String {
        switch self {
        case .text(let id, _, _): return id
        case .attachment(let id, _): return id
        }
    }
}

enum CleanViewAttachmentLayout {
    static func buildSegments(
        bodyClean: String,
        attachments: [NoteAttachment]
    ) -> (segments: [CleanViewContentSegment], unreferenced: [NoteAttachment]) {
        guard !attachments.isEmpty else {
            return ([.text(id: "text:0", rangeOffset: 0, rangeEnd: bodyClean.count)], [])
        }

        struct MarkerHit {
            let startOffset: Int
            let endOffset: Int
            let attachment: NoteAttachment
        }

        var hits: [MarkerHit] = []
        var matchedIDs: Set<UUID> = []

        for attachment in attachments {
            let marker = attachment.markerText
            var searchStart = bodyClean.startIndex
            while searchStart < bodyClean.endIndex,
                  let found = bodyClean.range(of: marker, range: searchStart..<bodyClean.endIndex) {
                let s = bodyClean.distance(from: bodyClean.startIndex, to: found.lowerBound)
                let e = bodyClean.distance(from: bodyClean.startIndex, to: found.upperBound)
                hits.append(MarkerHit(startOffset: s, endOffset: e, attachment: attachment))
                matchedIDs.insert(attachment.id)
                searchStart = found.upperBound
            }
        }

        hits.sort { $0.startOffset < $1.startOffset }

        var segments: [CleanViewContentSegment] = []
        var cursor = 0
        for (idx, hit) in hits.enumerated() {
            if hit.startOffset > cursor {
                segments.append(.text(id: "text:\(idx):\(cursor)", rangeOffset: cursor, rangeEnd: hit.startOffset))
            }
            segments.append(.attachment(id: "att:\(idx):\(hit.attachment.id.uuidString)", attachment: hit.attachment))
            cursor = max(cursor, hit.endOffset)
        }
        if cursor < bodyClean.count {
            segments.append(.text(id: "text:tail:\(cursor)", rangeOffset: cursor, rangeEnd: bodyClean.count))
        }
        if segments.isEmpty {
            segments.append(.text(id: "text:empty", rangeOffset: 0, rangeEnd: bodyClean.count))
        }

        let unreferenced = attachments.filter { !matchedIDs.contains($0.id) }
        return (segments, unreferenced)
    }
}

#if os(macOS)
struct CopyWithImagesSheet: View {
    @Bindable var store: NotesStore
    let request: CopyWithImagesRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var selectedIDs: Set<UUID>
    @State private var expandTabs: Bool = true

    init(store: NotesStore, request: CopyWithImagesRequest) {
        self.store = store
        self.request = request
        _selectedIDs = State(initialValue: request.preselectedAttachmentIDs)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Choose which images to embed alongside your copied text (RTFD + PNGs paste directly into Apple Notes in 1 step):")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Select All (\(request.attachments.count))") {
                        selectedIDs = Set(request.attachments.map(\.id))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Text Only (None)") {
                        selectedIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Toggle("Expand tabs (3 spaces)", isOn: $expandTabs)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(request.attachments) { att in
                            let isChecked = selectedIDs.contains(att.id)
                            Button {
                                if isChecked {
                                    selectedIDs.remove(att.id)
                                } else {
                                    selectedIDs.insert(att.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isChecked ? retinaGold : .secondary)

                                    if let data = store.readAttachmentData(for: att),
                                       let crisp = RetinaImageSupport.loadCrispImage(from: data, backingScale: displayScale) {
                                        Image(decorative: crisp.cgImage, scale: crisp.backingScale, orientation: .up)
                                            .resizable()
                                            .interpolation(.high)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 72, height: 48)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                            )
                                    } else {
                                        Image(systemName: "photo")
                                            .frame(width: 72, height: 48)
                                            .foregroundStyle(.secondary)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(att.filename)
                                            .font(.body.weight(.medium))
                                            .lineLimit(1)
                                        Text("\(att.pixelWidth)×\(att.pixelHeight) px • #\(att.shortID)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(8)
                                .background(isChecked ? retinaGold.opacity(0.10) : Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isChecked ? retinaGold.opacity(0.55) : Color.clear, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            .padding(20)
            .navigationTitle("Copy for Apple Notes — Include Images?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedIDs.isEmpty ? "Copy Plain Text" : "Copy Text + \(selectedIDs.count) Image(s)") {
                        store.performCopyForAppleNotes(
                            text: request.selectedText,
                            attachments: request.attachments,
                            includedAttachmentIDs: selectedIDs,
                            appendUnreferenced: request.appendUnreferenced,
                            expandTabs: expandTabs
                        )
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(retinaGold)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 380)
    }
}
#endif
#endif
