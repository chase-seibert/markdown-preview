import AppKit
import Foundation
import QuickLookUI

@MainActor
final class PreviewProvider: NSViewController, @preconcurrency QLPreviewingController, NSTextViewDelegate {
    private let textView = QuickLookTextView()
    private var previewURL: URL?

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
            previewURL = url
            let fontScale = MarkdownFontScalePreference.storedValue(
                inDomain: MarkdownFontScalePreference.sharedPreferenceDomain
            ) ?? MarkdownFontScalePreference.defaultScale

            _ = view
            textView.fontScale = CGFloat(fontScale)
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
        textView.delegate = self
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let previewURL,
              let linkURL = link as? URL,
              let destinationURL = MarkdownLinkResolver.localMarkdownURL(
                  for: linkURL,
                  relativeTo: previewURL
              ),
              let navigationURL = MarkdownLinkResolver.navigationURL(
                  for: destinationURL,
                  relativeTo: previewURL
              )
        else {
            return false
        }

        NSWorkspace.shared.open(navigationURL)
        return true
    }
}

@MainActor
private final class QuickLookTextView: NSTextView {
    var fontScale = CGFloat(MarkdownFontScalePreference.defaultScale) {
        didSet { updateReadingInsets() }
    }

    override var frame: NSRect {
        didSet { updateReadingInsets() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateReadingInsets()
    }

    private func updateReadingInsets() {
        let maximumWidth = CGFloat(
            MarkdownReadingLayout.maximumTextContainerWidth(fontScale: Double(fontScale))
        )
        let horizontal = max(34, (bounds.width - maximumWidth) / 2)
        textContainerInset = NSSize(width: horizontal, height: 38)
    }
}
