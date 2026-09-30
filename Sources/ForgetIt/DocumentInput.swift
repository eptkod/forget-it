import AppKit
import PDFKit
import ImageIO

extension AttachmentReader {
    static func assistantContent(_ attachment: Attachment) throws -> (text: String, images: [String]) {
        guard attachment.data.count <= limit else { throw AIError.message("Keep each file under 20 MB.") }
        let suffix = URL(fileURLWithPath: attachment.name).pathExtension.lowercased()
        if suffix != "pdf", let source = CGImageSourceCreateWithData(attachment.data as CFData, nil), CGImageSourceGetCount(source) > 0 { return ("", [try aiImage(attachment)]) }
        var text: String
        switch suffix {
        case "txt", "md", "csv", "ics", "json":
            guard let decoded = String(data: attachment.data, encoding: .utf8) ?? String(data: attachment.data, encoding: .utf16) else { throw AIError.message("\(attachment.name) has an unsupported text encoding. Save it as UTF-8.") }
            text = decoded
        case "rtf", "docx", "doc":
            let type: NSAttributedString.DocumentType = suffix == "rtf" ? .rtf : suffix == "docx" ? .officeOpenXML : .docFormat
            text = try NSAttributedString(data: attachment.data, options: [.documentType: type], documentAttributes: nil).string
        case "pdf":
            guard let pdf = PDFDocument(data: attachment.data), !pdf.isLocked else { throw AIError.message("This PDF is locked or unreadable. Export an unlocked copy.") }
            guard pdf.pageCount <= 40 else { throw AIError.message("Use a PDF with up to 40 pages, or export only the relevant pages.") }
            text = ""
            var images: [String] = []
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index) else { throw AIError.message("A PDF page could not be read.") }
                if let content = page.string, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text += "\nPage \(index + 1):\n" + content
                } else {
                    guard images.count < 6, let tiff = page.thumbnail(of: NSSize(width: 1600, height: 2000), for: .mediaBox).tiffRepresentation else { throw AIError.message("Use up to six scanned PDF pages at a time.") }
                    images.append(try aiImage(Attachment(name: "Page.png", data: tiff)))
                }
            }
            guard text.count <= 24_000 else { throw AIError.message("This PDF is too long. Export the relevant pages (up to 24,000 characters).") }
            return ("\nAttached PDF source: \(attachment.name)\n<source>\n\(text)\n</source>", images)
        default: throw AIError.message("\(attachment.name) can be attached to a task, but the assistant cannot read this format. Use an image, PDF, Word, RTF, TXT, Markdown or CSV file.")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.message("\(attachment.name) has no readable text.") }
        guard text.count <= 24_000 else { throw AIError.message("\(attachment.name) is too long for the local assistant. Upload the relevant section (up to 24,000 characters).") }
        return ("\nAttached source document: \(attachment.name)\n<source>\n\(text)\n</source>", [])
    }
}
