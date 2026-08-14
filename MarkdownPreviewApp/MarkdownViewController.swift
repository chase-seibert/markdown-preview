import AppKit
import Foundation

@MainActor
final class MarkdownViewController: NSViewController {
    private let source: String
    private let textView = MarkdownTextView()

    init(source: String) {
        self.source = source
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
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
    }

    @objc private func fontScaleDidChange(_ notification: Notification) {
        render()
    }

    private func render() {
        let visibleOrigin = (view as? NSScrollView)?.contentView.bounds.origin ?? .zero
        let selectedRange = textView.selectedRange()
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
