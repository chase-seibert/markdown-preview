import AppKit
import CoreText
import Foundation

public enum MarkdownExportError: LocalizedError {
    case couldNotCreatePDF
    case couldNotEncodeRichText

    public var errorDescription: String? {
        switch self {
        case .couldNotCreatePDF: "The PDF could not be created."
        case .couldNotEncodeRichText: "The rich text could not be encoded."
        }
    }
}

public struct MarkdownExporter: Sendable {
    public init() {}

    @MainActor
    public func rtf(from attributedString: NSAttributedString) throws -> Data {
        try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    @MainActor
    public func pdf(from attributedString: NSAttributedString, title: String? = nil) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw MarkdownExportError.couldNotCreatePDF
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        var metadata: [CFString: Any] = [:]
        if let title { metadata[kCGPDFContextTitle] = title }
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else {
            throw MarkdownExportError.couldNotCreatePDF
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textRect = mediaBox.insetBy(dx: 54, dy: 54)
        var position = 0

        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: position, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            position += visible.length
            context.endPDFPage()
        } while position < attributedString.length

        context.closePDF()
        guard data.length > 0 else { throw MarkdownExportError.couldNotCreatePDF }
        return data as Data
    }
}

