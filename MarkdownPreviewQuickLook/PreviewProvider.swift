import AppKit
import Foundation
import QuickLookUI

@MainActor
final class PreviewProvider: NSViewController, @preconcurrency QLPreviewingController {
    private let textView = QuickLookTextView()

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 760, height: 900)
        configureTextView()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let fontScale = MarkdownFontScalePreference.storedValue(
                inDomain: MarkdownFontScalePreference.sharedPreferenceDomain
            ) ?? MarkdownFontScalePreference.defaultScale

            _ = view
            textView.textStorage?.setAttributedString(
                MarkdownAttributedRenderer().render(
                    source,
                    options: .init(fontScale: CGFloat(fontScale))
                )
            )
            title = url.lastPathComponent
            handler(nil)
        } catch {
            handler(error)
        }
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.allowsUndo = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
    }
}

@MainActor
private final class QuickLookTextView: NSTextView {
    override var frame: NSRect {
        didSet { updateReadingInsets() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateReadingInsets()
    }

    private func updateReadingInsets() {
        let horizontal = max(34, (bounds.width - 900) / 2)
        textContainerInset = NSSize(width: horizontal, height: 38)
    }
}
