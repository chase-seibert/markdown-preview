import AppKit
import Foundation

@MainActor
final class MarkdownViewController: NSViewController, NSTextViewDelegate {
    private var source: String
    private var documentURL: URL?
    private let textView = MarkdownTextView()

    init(source: String, documentURL: URL?) {
        self.source = source
        self.documentURL = documentURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // This controller is created entirely in code; decline storyboard
        // decoding without turning an unexpected invocation into a crash.
        return nil
    }

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
        configureTextView()
        render()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontScaleDidChange(_:)),
            name: .markdownFontScaleDidChange,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
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
        textView.usesFindPanel = true
        textView.isIncrementalSearchingEnabled = true
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

    @objc private func fontScaleDidChange(_ notification: Notification) {
        render()
    }

    func updateSource(_ source: String) {
        self.source = source
        render()
    }

    func updateDocumentURL(_ documentURL: URL) {
        self.documentURL = documentURL
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let documentURL,
              let linkURL = link as? URL,
              let destinationURL = MarkdownLinkResolver.localMarkdownURL(
                  for: linkURL,
                  relativeTo: documentURL
              ),
              let navigationURL = MarkdownLinkResolver.navigationURL(
                  for: destinationURL,
                  relativeTo: documentURL
              )
        else {
            return false
        }

        NSWorkspace.shared.open(navigationURL)
        return true
    }

    private func render() {
        let visibleOrigin = (view as? NSScrollView)?.contentView.bounds.origin ?? .zero
        let selectedRange = textView.selectedRange()
        textView.fontScale = FontScaleController.shared.scale
        textView.textStorage?.setAttributedString(
            MarkdownAttributedRenderer().render(
                source,
                options: .init(fontScale: FontScaleController.shared.scale)
            )
        )
        let safeLocation = min(selectedRange.location, textView.string.utf16.count)
        let safeLength = min(selectedRange.length, textView.string.utf16.count - safeLocation)
        textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }
        if let scrollView = view as? NSScrollView {
            scrollView.contentView.scroll(to: visibleOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

@MainActor
private final class MarkdownTextView: NSTextView {
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
