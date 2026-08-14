import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping @Sendable (QLPreviewReply?, (any Error)?) -> Void
    ) {
        let url = request.fileURL
        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 760, height: 900)
        ) { _ in
            let source = try String(contentsOf: url, encoding: .utf8)
            let html = MarkdownHTMLRenderer().document(
                source: source,
                title: url.deletingPathExtension().lastPathComponent
            )
            return Data(html.utf8)
        }
        reply.stringEncoding = .utf8
        reply.title = url.lastPathComponent
        handler(reply, nil)
    }
}
