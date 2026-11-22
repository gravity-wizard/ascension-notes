import AscensionCore
import Foundation

#if canImport(SwiftUI)
import SwiftUI
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(Vision)
import Vision
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
        let exactUnixTimestamp: Int64
        let base38Tag: String
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
        let now = Int64(Date().timeIntervalSince1970)
        let tag = Base38Clock.cleanExactClockExpression(unixSeconds: now, contextWords: ["capture"], maxLength: 17).expression
        return "Capture \(tag).png"
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
        return preparePNG(fromData: data, filename: filename, preserveRawPNG: isPNG, fileURL: url)
    }

    static func preparePNG(
        fromData data: Data,
        filename: String,
        preserveRawPNG: Bool,
        fileURL: URL? = nil
    ) -> PreparedPNG? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let pixelW = cgImage.width
        let pixelH = cgImage.height
        guard pixelW > 0, pixelH > 0 else { return nil }

        let exactTs = SmartImageRetitler.extractExactUnixTimestamp(from: source, fileURL: fileURL)
        let retitled = SmartImageRetitler.retitle(
            cgImage: cgImage,
            originalFilename: filename,
            exactUnixTimestamp: exactTs
        )

        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if preserveRawPNG && data.count >= 4 && Array(data.prefix(4)) == pngSignature {
            return PreparedPNG(
                pngData: data,
                pixelWidth: pixelW,
                pixelHeight: pixelH,
                filename: retitled.filename,
                exactUnixTimestamp: exactTs,
                base38Tag: retitled.base38Tag
            )
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let encoded = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return PreparedPNG(
            pngData: encoded,
            pixelWidth: pixelW,
            pixelHeight: pixelH,
            filename: retitled.filename,
            exactUnixTimestamp: exactTs,
            base38Tag: retitled.base38Tag
        )
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

@MainActor
enum SmartImageRetitler {
    private static let boilerplatePrefixes = [
        "screenshot", "screen shot", "screen recording", "cleanshot",
        "img_", "dsc_", "pxl_", "mvimg_", "capture", "image", "photo", "paste"
    ]

    private static let genericVisionLabels: Set<String> = [
        "structure", "material", "text", "screenshot", "computer", "display",
        "screen", "graphics", "rectangle", "symbol", "sign", "font",
        "document", "page", "design", "pattern", "indoor", "outdoor"
    ]

    private static let visionAliases: [String: String] = [
        "gymnasium": "Gym",
        "fitness_center": "Gym",
        "weeping_willow": "Weeping Willow",
        "willow": "Willow Tree"
    ]

    static func extractExactUnixTimestamp(from source: CGImageSource, fileURL: URL?) -> Int64 {
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                for key in [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifDateTimeDigitized] {
                    if let raw = exif[key] as? String, let parsed = formatter.date(from: raw) {
                        return Int64(parsed.timeIntervalSince1970)
                    }
                }
            }
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let raw = tiff[kCGImagePropertyTIFFDateTime] as? String,
               let parsed = formatter.date(from: raw) {
                return Int64(parsed.timeIntervalSince1970)
            }
        }

        if let fileURL,
           let values = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
           let fileDate = values.creationDate ?? values.contentModificationDate {
            return Int64(fileDate.timeIntervalSince1970)
        }

        return Int64(Date().timeIntervalSince1970)
    }

    static func isBoilerplateStem(_ stem: String) -> Bool {
        let lower = stem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return true }
        for prefix in boilerplatePrefixes where lower.hasPrefix(prefix) {
            return true
        }
        let compact = lower.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        if compact.count >= 16 && compact.allSatisfy({ $0.isHexDigit }) {
            return true
        }
        return false
    }

    static func retitle(
        cgImage: CGImage,
        originalFilename: String,
        exactUnixTimestamp: Int64
    ) -> (filename: String, base38Tag: String) {
        let stem = (originalFilename as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let subject: String
        var contextWords: [String] = []

        if !isBoilerplateStem(stem) {
            let cleaned = stem.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let capped = cleaned.count > 32 ? String(cleaned.prefix(32)).trimmingCharacters(in: .whitespaces) : cleaned
            subject = capped.isEmpty ? "Capture" : capped
            contextWords = subject.components(separatedBy: CharacterSet.alphanumerics.inverted)
        } else {
            let vision = detectVisionSubject(cgImage: cgImage)
            subject = vision.subject
            contextWords = vision.contextWords
        }

        let expr = Base38Clock.cleanExactClockExpression(
            unixSeconds: exactUnixTimestamp,
            contextWords: contextWords,
            maxLength: 17
        ).expression

        if subject.contains(expr) {
            return ("\(subject).png", expr)
        }
        return ("\(subject) \(expr).png", expr)
    }

    static func editableSubject(from filename: String, base38Tag: String?) -> String {
        var stem = (filename as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let tag = base38Tag, !tag.isEmpty, stem.hasSuffix(" \(tag)") {
            stem = String(stem.dropLast(tag.count + 1))
        }
        return stem.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isReadableWord(_ word: String) -> Bool {
        let lower = word.lowercased()
        guard lower.count >= 2 && lower.count <= 13 else { return false }
        if lower.count >= 6 && lower.allSatisfy({ $0.isHexDigit }) { return false }
        let letters = lower.filter { $0 >= "a" && $0 <= "z" }
        guard !letters.isEmpty else { return false }
        let vowels = letters.filter { "aeiouy".contains($0) }.count
        if letters.count >= 5 && vowels == 0 { return false }
        #if os(macOS)
        let spellRange = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
        if spellRange.location == NSNotFound {
            return true
        }
        #endif
        return lower.count <= 8 && vowels >= 1
    }

    private static func detectVisionSubject(cgImage: CGImage) -> (subject: String, contextWords: [String]) {
        #if canImport(Vision)
        let classifyRequest = VNClassifyImageRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([classifyRequest, textRequest])

        var concreteLabels: [String] = []
        if let results = classifyRequest.results {
            for obs in results where obs.confidence >= 0.40 {
                let rawID = obs.identifier.lowercased()
                let human = visionAliases[rawID] ?? rawID
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                let words = rawID.split(separator: "_").map(String.init)
                if !words.contains(where: { genericVisionLabels.contains($0) }) {
                    concreteLabels.append(human)
                }
                if concreteLabels.count >= 2 { break }
            }
        }

        var bestOCRTitle: String? = nil
        var bestOCRWords: [String] = []
        var bestOCRScore: Double = -1.0

        if let textResults = textRequest.results {
            for obs in textResults.prefix(30) {
                guard let candidate = obs.topCandidates(1).first,
                      candidate.confidence >= 0.50 else { continue }
                let rawWords = candidate.string
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 2 && $0.count <= 13 }
                let goodWords = rawWords.filter { isReadableWord($0) }
                guard !goodWords.isEmpty,
                      goodWords.count * 2 >= rawWords.count else { continue }

                var chosenWords: [String] = []
                for w in goodWords {
                    let next = (chosenWords + [w]).joined(separator: " ")
                    if next.count > 26 { break }
                    chosenWords.append(w)
                    if chosenWords.count >= 3 { break }
                }
                let joined = chosenWords.joined(separator: " ")
                guard joined.count >= 4 else { continue }

                var realCount = 0
                #if os(macOS)
                for w in chosenWords {
                    if NSSpellChecker.shared.checkSpelling(of: w, startingAt: 0).location == NSNotFound {
                        realCount += 1
                    }
                }
                #else
                realCount = chosenWords.count
                #endif
                guard realCount >= 1 else { continue }

                let score = Double(realCount) * 3.0
                    + Double(chosenWords.count) * 0.8
                    + Double(obs.boundingBox.height) * 20.0
                    + (obs.boundingBox.maxY > 0.7 ? 1.5 : 0.0)
                    + Double(candidate.confidence)

                if score > bestOCRScore {
                    bestOCRScore = score
                    bestOCRTitle = joined
                    bestOCRWords = goodWords.map { $0.lowercased() }
                }
            }
        }

        if let label = concreteLabels.first {
            let context = label.components(separatedBy: CharacterSet.alphanumerics.inverted) + bestOCRWords
            return (label, context)
        }
        if let bestOCRTitle {
            return (bestOCRTitle, bestOCRWords)
        }
        #endif
        return ("Capture", ["capture"])
    }
}

struct RenameAttachmentPopover: View {
    @Bindable var store: NotesStore
    let noteID: UUID
    let attachment: NoteAttachment
    @Binding var isPresented: Bool

    @State private var subjectDraft: String

    init(store: NotesStore, noteID: UUID, attachment: NoteAttachment, isPresented: Binding<Bool>) {
        self.store = store
        self.noteID = noteID
        self.attachment = attachment
        self._isPresented = isPresented
        _subjectDraft = State(
            initialValue: SmartImageRetitler.editableSubject(
                from: attachment.filename,
                base38Tag: attachment.base38TimestampTag
            )
        )
    }

    private var exactTimestamp: Int64 {
        attachment.exactUnixTimestamp ?? Int64(attachment.createdAt.timeIntervalSince1970)
    }

    private var previewTag: String {
        let words = subjectDraft.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Base38Clock.cleanExactClockExpression(
            unixSeconds: exactTimestamp,
            contextWords: words,
            maxLength: 17
        ).expression
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SMART ReTiT1e Image")
                .font(.headline)
            TextField("What is this image? (e.g. Weeping WilLoW Tree)", text: $subjectDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 280)

            HStack(spacing: 6) {
                Text("Tag (≤17 chars):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(previewTag)
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(retinaGold.opacity(0.18))
                    .foregroundStyle(retinaGold)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(exactTimestamp)).formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Spacer()
                Button("Save Title") {
                    _ = store.smartRenameAttachment(attachment, in: noteID, subjectInput: subjectDraft)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(retinaGold)
            }
        }
        .padding(14)
    }
}

struct CrispAttachmentImageView: View {
    @Bindable var store: NotesStore
    let noteID: UUID
    let attachment: NoteAttachment
    let maxDisplayHeight: CGFloat?

    @Environment(\.displayScale) private var displayScale
    @State private var showRenamePopover: Bool = false

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
                    showRenamePopover = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("SMART ReTiT1e Image & Exact Base-38 Tag")
                .popover(isPresented: $showRenamePopover) {
                    RenameAttachmentPopover(
                        store: store,
                        noteID: noteID,
                        attachment: attachment,
                        isPresented: $showRenamePopover
                    )
                }

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
    @State private var showRenamePopover: Bool = false

    private var loadedImage: CrispRetinaImage? {
        guard let data = store.readAttachmentData(for: request.attachment) else { return nil }
        return RetinaImageSupport.loadCrispImage(from: data, backingScale: displayScale)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(request.attachment.filename)
                                .font(.headline)
                            if let tag = request.attachment.base38TimestampTag, !tag.isEmpty {
                                Text(tag)
                                    .font(.caption.monospaced().bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(retinaGold.opacity(0.18))
                                    .foregroundStyle(retinaGold)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
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

                    Button {
                        showRenamePopover = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $showRenamePopover) {
                        RenameAttachmentPopover(
                            store: store,
                            noteID: request.noteID,
                            attachment: request.attachment,
                            isPresented: $showRenamePopover
                        )
                    }

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
