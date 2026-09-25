import AppKit
import EverClipCore

/// Writes a stored item back onto the system pasteboard so it can be pasted.
enum ClipboardWriter {
    static func write(_ item: ClipItem, store: ClipStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text, .url:
            pasteboard.setString(item.text ?? "", forType: .string)

        case .richText:
            var wroteRich = false
            if let rtf = item.rtfData {
                pasteboard.setData(rtf, forType: .rtf)
                wroteRich = true
            }
            if let html = item.htmlText {
                pasteboard.setString(html, forType: .html)
                wroteRich = true
            }
            // Always include a plain-text representation as a fallback.
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            } else if !wroteRich {
                pasteboard.setString("", forType: .string)
            }

        case .image, .screenshot:
            if let url = store.blobURL(for: item), let data = try? Data(contentsOf: url) {
                let type: NSPasteboard.PasteboardType = url.pathExtension.lowercased() == "png" ? .png : .tiff
                pasteboard.setData(data, forType: type)
            }

        case .file:
            let urls = item.fileURLs.map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty {
                pasteboard.writeObjects(urls)
            } else if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        }
    }
}
