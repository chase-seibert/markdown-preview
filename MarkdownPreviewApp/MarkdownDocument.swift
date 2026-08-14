import AppKit
import Foundation

@MainActor
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    // NSDocument's read/write overrides are imported as nonisolated in Swift 6.
    // AppKit serializes document loading before window creation, so this storage
    // is safe to bridge into the otherwise main-actor document object.
    nonisolated(unsafe) private(set) var source = ""

    override class var autosavesInPlace: Bool { false }
    override var isDocumentEdited: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        if let utf8 = String(data: data, encoding: .utf8) {
            source = utf8
            return
        }

        var converted: NSString?
        var lossy = ObjCBool(false)
        guard NSString.stringEncoding(
            for: data,
            encodingOptions: nil,
            convertedString: &converted,
            usedLossyConversion: &lossy
        ) != 0, let converted
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        source = converted as String
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(source.utf8)
    }

    override func makeWindowControllers() {
        let contentController = MarkdownViewController(source: source)
        let window = NSWindow(contentViewController: contentController)
        window.setContentSize(NSSize(width: 780, height: 760))
        window.minSize = NSSize(width: 460, height: 320)
        window.styleMask.insert([.resizable, .miniaturizable, .closable, .titled, .fullSizeContentView])
        window.titlebarAppearsTransparent = false
        window.tabbingMode = .disallowed
        window.representedURL = fileURL
        window.title = displayName
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        addWindowController(controller)
    }

    var renderedText: NSAttributedString {
        MarkdownAttributedRenderer().render(
            source,
            options: .init(fontScale: FontScaleController.shared.scale)
        )
    }

    var printableText: NSAttributedString {
        MarkdownAttributedRenderer().render(
            source,
            options: .init(fontScale: FontScaleController.shared.scale, palette: .print)
        )
    }
}
