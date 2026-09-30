import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

enum AttachmentReader {
    static let limit = 20 * 1024 * 1024
    static func file(_ url: URL) throws -> Attachment {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= limit else { throw AIError.message("Choose a file under 20 MB.") }
        return Attachment(name: url.lastPathComponent, data: try Data(contentsOf: url))
    }
    static func image(_ data: Data) throws -> Attachment {
        guard data.count <= limit, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width * height <= 100_000_000,
              let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]), png.count <= limit else {
            throw AIError.message("Use a readable screenshot under 20 MB.")
        }
        return Attachment(name: "Screenshot-\(UUID().uuidString.prefix(6)).png", data: png)
    }
    @MainActor static func pasteboard(_ board: NSPasteboard) throws -> [Attachment] {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { return try urls.map(file) }
        if let data = board.data(forType: .png) ?? board.data(forType: .tiff) { return [try image(data)] }
        return []
    }
    static func providers(_ providers: [NSItemProvider]) async throws -> [Attachment] {
        var results: [Attachment] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let data = try await load(provider, type: UTType.fileURL.identifier)
                guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { throw AIError.message("Drop a file from this Mac.") }
                results.append(try file(url))
            } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                results.append(try image(await load(provider, type: type)))
            }
        }
        return results
    }
    static func load(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? AIError.message("The dropped image could not be read.")) }
            }
        }
    }
    static func aiImage(_ attachment: Attachment) throws -> String {
        guard let source = CGImageSourceCreateWithData(attachment.data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw AIError.message("\(attachment.name) is not a supported image. Paste its text or upload a screenshot.")
        }
        return data.base64EncodedString()
    }
}

struct AttachmentInput: View {
    @Binding var attachments: [Attachment]
    var imagesOnly = false
    var onOpen: ((Attachment) -> Void)? = nil
    @State private var targeted = false
    @State private var error: String?
    @Binding var loading: Bool
    init(attachments: Binding<[Attachment]>, imagesOnly: Bool = false, onOpen: ((Attachment) -> Void)? = nil, loading: Binding<Bool> = .constant(false)) {
        _attachments = attachments; self.imagesOnly = imagesOnly; self.onOpen = onOpen; _loading = loading
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(attachments) { item in
                HStack {
                    if let image = NSImage(data: item.data) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 42, height: 32).clipShape(RoundedRectangle(cornerRadius: 4))
                    } else { Image(systemName: "paperclip") }
                    if let onOpen { Button(item.name) { onOpen(item) }.buttonStyle(.link).lineLimit(1) } else { Text(item.name).lineLimit(1) }
                    Spacer()
                    Button("Remove", systemImage: "xmark") { attachments.removeAll { $0.id == item.id } }.labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            HStack {
                Image(systemName: "photo.badge.plus")
                Text(loading ? "Reading attachment…" : "Drop files here, or paste from your clipboard.").font(.caption)
                Spacer()
                Button("Paste") { do { let items = try AttachmentReader.pasteboard(.general); if items.isEmpty { error = "Copy an image or file first." }; try append(items) } catch { self.error = error.localizedDescription } }
                Button("Choose…") {
                    let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
                    if imagesOnly { panel.allowedContentTypes = [.image] }
                    if panel.runModal() == .OK { do { try append(panel.urls.map(AttachmentReader.file)) } catch { self.error = error.localizedDescription } }
                }
            }.padding(12).background(targeted ? SchoolClass.tint("lavender").opacity(0.15) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $targeted) { providers in
            guard !loading else { return false }
            if imagesOnly && attachments.count + providers.count > 6 { error = "Use up to six screenshots at a time."; return false }
            loading = true
            Task { defer { loading = false }; do { try append(await AttachmentReader.providers(providers)) } catch { self.error = error.localizedDescription } }
            return true
        }
    }
    private func append(_ items: [Attachment]) throws {
        if imagesOnly && items.contains(where: { CGImageSourceCreateWithData($0.data as CFData, nil) == nil }) { throw AIError.message("For AI, add screenshots or paste the document’s text.") }
        guard !imagesOnly || attachments.count + items.count <= 6 else { throw AIError.message("Use up to six screenshots at a time.") }
        for item in items where !attachments.contains(where: { $0.data == item.data }) { attachments.append(item) }
        error = nil
    }
}

/// Keeps normal text editing while routing image paste/drop to the attachment collection.
struct AttachmentTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var attachments: [Attachment]
    var onError: (String) -> Void = { _ in }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = PastingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 130)); view.isRichText = false; view.allowsUndo = true; view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.drawsBackground = false; view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true; view.delegate = context.coordinator
        view.registerForDraggedTypes([.fileURL, .png, .tiff]); scroll.documentView = view
        update(view, context: context); return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PastingTextView else { return }; update(view, context: context)
    }
    private func update(_ view: PastingTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text { view.string = text }
        view.receive = { items in
            for item in items where !attachments.contains(where: { $0.data == item.data }) { attachments.append(item) }
        }
        view.failure = onError
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AttachmentTextEditor
        init(_ parent: AttachmentTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
}
final class PastingTextView: NSTextView {
    var receive: ([Attachment]) -> Void = { _ in }
    var failure: (String) -> Void = { _ in }
    private func consume(_ board: NSPasteboard) -> Bool {
        do { let items = try AttachmentReader.pasteboard(board); if !items.isEmpty { receive(items); return true } }
        catch { failure(error.localizedDescription); return true }
        return false
    }
    override func paste(_ sender: Any?) { if !consume(.general) { super.paste(sender) } }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if consume(sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }
}
