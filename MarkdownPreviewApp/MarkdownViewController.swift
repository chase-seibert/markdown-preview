import AppKit
import Foundation

@MainActor
final class MarkdownViewController: NSViewController, NSTextViewDelegate {
    private var source: String
    private var documentURL: URL?
    private let onTaskToggle: (Int) -> Void
    private let textView = MarkdownTextView()

    init(source: String, documentURL: URL?, onTaskToggle: @escaping (Int) -> Void) {
        self.source = source
        self.documentURL = documentURL
        self.onTaskToggle = onTaskToggle
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
        textView.onTaskToggle = onTaskToggle
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
        textView.window?.invalidateCursorRects(for: textView)
    }
}

@MainActor
private final class MarkdownTextView: NSTextView {
    var onTaskToggle: ((Int) -> Void)?
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

    override func mouseDown(with event: NSEvent) {
        guard let taskIndex = taskIndex(at: event) else {
            super.mouseDown(with: event)
            return
        }

        onTaskToggle?(taskIndex)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let textStorage, let layoutManager, let textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        textStorage.enumerateAttribute(
            .markdownTaskIndex,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, characterRange, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            addCursorRect(rect.insetBy(dx: -2, dy: -2), cursor: .pointingHand)
        }
    }

    private func taskIndex(at event: NSEvent) -> Int? {
        guard let textStorage, let layoutManager, let textContainer else { return nil }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)
        guard containerPoint.x >= 0, containerPoint.y >= 0 else { return nil }

        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return nil }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(
            .markdownTaskIndex,
            at: characterIndex,
            effectiveRange: nil
        ) as? Int
    }

    private func updateReadingInsets() {
        let maximumWidth = CGFloat(
            MarkdownReadingLayout.maximumTextContainerWidth(fontScale: Double(fontScale))
        )
        let horizontal = max(34, (bounds.width - maximumWidth) / 2)
        textContainerInset = NSSize(width: horizontal, height: 38)
    }
}
