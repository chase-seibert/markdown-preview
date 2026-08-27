import AppKit
import Foundation

@MainActor
final class MarkdownViewController: NSViewController, NSTextViewDelegate {
    private var source: String
    private var documentURL: URL?
    private let onTaskToggle: (Int) -> Void
    private let onSourceChange: (String) -> MarkdownDocument.EditWriteResult
    private let onEditConflict: (String, MarkdownViewController) -> Void
    private let textView = MarkdownTextView()
    private var isRendering = false

    init(
        source: String,
        documentURL: URL?,
        onTaskToggle: @escaping (Int) -> Void,
        onSourceChange: @escaping (String) -> MarkdownDocument.EditWriteResult,
        onEditConflict: @escaping (String, MarkdownViewController) -> Void
    ) {
        self.source = source
        self.documentURL = documentURL
        self.onTaskToggle = onTaskToggle
        self.onSourceChange = onSourceChange
        self.onEditConflict = onEditConflict
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
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.allowsUndo = true
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

    func toggleBold(_ sender: Any? = nil) {
        textView.toggleInlineStyle(.bold)
    }

    func toggleItalic(_ sender: Any? = nil) {
        textView.toggleInlineStyle(.italic)
    }

    func toggleBulletedList(_ sender: Any? = nil) {
        textView.toggleList(ordered: false)
    }

    func toggleNumberedList(_ sender: Any? = nil) {
        textView.toggleList(ordered: true)
    }

    func undo(_ sender: Any? = nil) {
        textView.undoManager?.undo()
    }

    func redo(_ sender: Any? = nil) {
        textView.undoManager?.redo()
    }

    var canUndo: Bool { textView.undoManager?.canUndo == true }
    var canRedo: Bool { textView.undoManager?.canRedo == true }

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
        isRendering = true
        defer { isRendering = false }
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

    func textDidChange(_ notification: Notification) {
        guard !isRendering else { return }
        textView.removeEmptyRenderedElements()
        textView.normalizeTypedMarkers()
        let proposedSource = MarkdownSourceSerializer().serialize(textView.attributedString())
        switch onSourceChange(proposedSource) {
        case .saved:
            source = proposedSource
        case .conflict:
            onEditConflict(proposedSource, self)
        case let .failed(error):
            let alert = NSAlert(error: error)
            if let window = view.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            render()
        }
    }

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn range: NSRange,
        replacementString text: String?
    ) -> Bool {
        (textView as? MarkdownTextView)?.allowsChange(in: range, replacementString: text) ?? true
    }

}

@MainActor
private final class MarkdownTextView: NSTextView {
    enum InlineStyle: Int {
        case italic = 1
        case bold = 2
    }

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

    override func keyDown(with event: NSEvent) {
        guard isEditable else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "b" {
            toggleInlineStyle(.bold)
            return
        }
        if modifiers == .command, event.charactersIgnoringModifiers == "i" {
            toggleInlineStyle(.italic)
            return
        }
        switch event.keyCode {
        case 36, 76:
            if insertListNewline() { return }
        case 51:
            if deleteListMarkerOrItem() { return }
        default:
            break
        }
        super.keyDown(with: event)
    }

    func toggleInlineStyle(_ style: InlineStyle) {
        let bit = style.rawValue
        let range = selectedRange()
        if range.length == 0 {
            var attributes = typingAttributes
            let current = attributes[.markdownInlineStyle] as? Int ?? 0
            attributes[.markdownInlineStyle] = current ^ bit
            attributes[.markdownProtected] = false
            typingAttributes = attributes
            return
        }

        guard let textStorage else { return }
        var allHaveStyle = true
        textStorage.enumerateAttribute(.markdownInlineStyle, in: range) { value, _, _ in
            if ((value as? Int) ?? 0) & bit == 0 { allHaveStyle = false }
        }
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.markdownInlineStyle, in: range) { value, subrange, _ in
            let current = (value as? Int) ?? 0
            let updated = allHaveStyle ? current & ~bit : current | bit
            textStorage.addAttribute(.markdownInlineStyle, value: updated, range: subrange)
            if let font = textStorage.attribute(.font, at: subrange.location, effectiveRange: nil) as? NSFont {
                let converted = updated & 2 != 0
                    ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    : NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                let finalFont = updated & 1 != 0
                    ? NSFontManager.shared.convert(converted, toHaveTrait: .italicFontMask)
                    : NSFontManager.shared.convert(converted, toNotHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: finalFont, range: subrange)
            }
        }
        textStorage.endEditing()
        didChangeText()
    }

    func toggleList(ordered: Bool) {
        guard let textStorage else { return }
        let ranges = selectedParagraphRanges()
        guard !ranges.isEmpty else { return }
        let shouldRemove = ranges.allSatisfy { range in
            guard let marker = listMarker(at: range.location) else { return false }
            return marker.ordered == ordered
        }

        textStorage.beginEditing()
        for range in ranges.reversed() {
            if let marker = listMarker(at: range.location) {
                if shouldRemove {
                    removeListMarker(marker, in: range, textStorage: textStorage)
                } else if marker.ordered != ordered {
                    removeListMarker(marker, in: range, textStorage: textStorage)
                    addListMarker(ordered: ordered, in: range, textStorage: textStorage)
                }
            } else if blockKind(in: range) == "paragraph" {
                addListMarker(ordered: ordered, in: range, textStorage: textStorage)
            }
        }
        textStorage.endEditing()
        didChangeText()
    }

    private func insertListNewline() -> Bool {
        guard let context = listMarker(at: selectedRange().location) else { return false }
        let contentEnd = contentEnd(of: context.lineRange)
        let content = (string as NSString).substring(with: NSRange(
            location: context.contentStart,
            length: max(0, contentEnd - context.contentStart)
        ))
        allowProtectedMutation = true
        defer { allowProtectedMutation = false }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            super.insertText("\n", replacementRange: context.lineRange)
            return true
        }

        let attributes = textStorage?.attributes(at: context.contentStart, effectiveRange: nil) ?? [:]
        let prefix: NSAttributedString
        let prefixLength: Int
        if context.task {
            prefix = taskMarkerReplacement(checked: false, basedOn: attributes)
            prefixLength = prefix.length
        } else {
            let marker = context.ordered ? "\(context.ordinal + 1).  " : "•  "
            prefix = NSAttributedString(string: marker, attributes: attributes)
            prefixLength = (marker as NSString).length
        }
        let prefixAttributes = listAttributes(
            basedOn: attributes,
            ordered: context.ordered,
            depth: context.depth,
            ordinal: context.ordinal + 1,
            prefixLength: prefixLength,
            quoteDepth: context.quoteDepth,
            task: context.task,
            checked: false
        )
        let value = NSMutableAttributedString(string: "\n", attributes: attributes)
        value.append(prefix)
        value.addAttributes(prefixAttributes, range: NSRange(location: 1, length: prefixLength))
        value.addAttribute(.markdownProtected, value: true, range: NSRange(location: 1, length: prefixLength))
        value.addAttribute(.markdownInlineStyle, value: 0, range: NSRange(location: 1, length: prefixLength))
        super.insertText(value, replacementRange: selectedRange())
        return true
    }

    private func deleteListMarkerOrItem() -> Bool {
        let range = selectedRange()
        guard range.length == 0, let context = listMarker(at: range.location), range.location == context.contentStart else {
            return false
        }
        guard let textStorage else { return false }
        allowProtectedMutation = true
        defer { allowProtectedMutation = false }

        let contentEnd = contentEnd(of: context.lineRange)
        let content = (string as NSString).substring(with: NSRange(
            location: context.contentStart,
            length: max(0, contentEnd - context.contentStart)
        ))
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            super.insertText("", replacementRange: context.lineRange)
        } else {
            removeListMarker(context, in: context.lineRange, textStorage: textStorage)
            didChangeText()
        }
        return true
    }

    private var allowProtectedMutation = false

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

    private struct ListMarker {
        let lineRange: NSRange
        let markerStart: Int
        let contentStart: Int
        let prefixLength: Int
        let task: Bool
        let ordered: Bool
        let depth: Int
        let ordinal: Int
        let quoteDepth: Int
    }

    private func listMarker(at location: Int) -> ListMarker? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let safeLocation = min(max(location, 0), textStorage.length - 1)
        let lineRange = (string as NSString).paragraphRange(for: NSRange(location: safeLocation, length: 0))
        var markerStart = lineRange.location
        while markerStart < NSMaxRange(lineRange) {
            if textStorage.attribute(.markdownBlockKind, at: markerStart, effectiveRange: nil) as? String == "list" {
                break
            }
            markerStart += 1
        }
        guard markerStart < NSMaxRange(lineRange),
              textStorage.attribute(.markdownBlockKind, at: markerStart, effectiveRange: nil) as? String == "list"
        else { return nil }
        let prefix = textStorage.attribute(.markdownListPrefixLength, at: markerStart, effectiveRange: nil) as? Int ?? 0
        return ListMarker(
            lineRange: lineRange,
            markerStart: markerStart,
            contentStart: min(NSMaxRange(lineRange), markerStart + prefix),
            prefixLength: prefix,
            task: textStorage.attribute(.markdownListTask, at: markerStart, effectiveRange: nil) as? Bool ?? false,
            ordered: (textStorage.attribute(.markdownListKind, at: markerStart, effectiveRange: nil) as? String) == "ordered",
            depth: textStorage.attribute(.markdownListDepth, at: markerStart, effectiveRange: nil) as? Int ?? 0,
            ordinal: textStorage.attribute(.markdownListOrdinal, at: markerStart, effectiveRange: nil) as? Int ?? 1,
            quoteDepth: textStorage.attribute(.markdownQuoteDepth, at: markerStart, effectiveRange: nil) as? Int ?? 0
        )
    }

    func normalizeTypedMarkers() {
        guard let textStorage, textStorage.length > 0 else { return }

        var location = 0
        while location < textStorage.length {
            let lineRange = (string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let listMarker = self.listMarker(at: location)
            let start = listMarker?.contentStart ?? editableLineStart(lineRange)
            let contentEnd = contentEnd(of: lineRange)

            if let listMarker, !listMarker.task {
                if let taskToken = typedTaskToken(at: start, before: contentEnd) {
                    convertToTask(
                        token: taskToken,
                        at: start,
                        existingList: listMarker
                    )
                    let updatedLineRange = (string as NSString).paragraphRange(
                        for: NSRange(location: listMarker.markerStart, length: 0)
                    )
                    location = max(location + 1, NSMaxRange(updatedLineRange))
                    continue
                }
            } else if listMarker == nil,
                      blockKind(at: start) == "paragraph"
            {
                if let headingToken = typedHeadingToken(at: start, before: contentEnd) {
                    convertToHeading(
                        token: headingToken,
                        at: start,
                        lineRange: lineRange
                    )
                    let updatedLineRange = (string as NSString).paragraphRange(
                        for: NSRange(location: lineRange.location, length: 0)
                    )
                    location = max(location + 1, NSMaxRange(updatedLineRange))
                    continue
                }

                if let taskToken = typedTaskToken(at: start, before: contentEnd) {
                    convertToTask(token: taskToken, at: start, existingList: nil)
                    let updatedLineRange = (string as NSString).paragraphRange(
                        for: NSRange(location: lineRange.location, length: 0)
                    )
                    location = max(location + 1, NSMaxRange(updatedLineRange))
                    continue
                }

                if let listToken = typedListToken(at: start, before: contentEnd) {
                    convertToList(token: listToken, at: start, lineRange: lineRange)
                    let updatedLineRange = (string as NSString).paragraphRange(
                        for: NSRange(location: lineRange.location, length: 0)
                    )
                    location = max(location + 1, NSMaxRange(updatedLineRange))
                    continue
                }
            }

            location = max(location + 1, NSMaxRange(lineRange))
        }

        renumberTaskMarkers()
    }

    func removeEmptyRenderedElements() {
        guard let textStorage, textStorage.length > 0 else { return }

        var location = 0
        var emptyRanges: [NSRange] = []
        while location < textStorage.length {
            let lineRange = (string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0)
            )
            let listMarker = self.listMarker(at: location)
            let contentStart = listMarker?.contentStart ?? editableLineStart(lineRange)
            let kind = blockKind(at: contentStart)
            if kind == "heading" || kind == "list" {
                let contentEnd = contentEnd(of: lineRange)
                let content = (string as NSString).substring(
                    with: NSRange(
                        location: contentStart,
                        length: max(0, contentEnd - contentStart)
                    )
                )
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyRanges.append(lineRange)
                }
            }
            let next = NSMaxRange(lineRange)
            if next <= location { break }
            location = next
        }

        guard !emptyRanges.isEmpty else { return }
        textStorage.beginEditing()
        for range in emptyRanges.reversed() {
            textStorage.deleteCharacters(in: range)
        }
        textStorage.endEditing()
    }

    private struct TypedToken {
        let length: Int
        let ordered: Bool
        let ordinal: Int
        let checked: Bool
    }

    private struct TypedHeadingToken {
        let length: Int
        let level: Int
    }

    private func editableLineStart(_ lineRange: NSRange) -> Int {
        let end = contentEnd(of: lineRange)
        var start = lineRange.location
        while start + 2 <= end,
              (string as NSString).substring(with: NSRange(location: start, length: 2)) == "▍ "
        {
            start += 2
        }
        return start
    }

    private func blockKind(at location: Int) -> String? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        return textStorage.attribute(
            .markdownBlockKind,
            at: min(location, textStorage.length - 1),
            effectiveRange: nil
        ) as? String
    }

    private func typedHeadingToken(at location: Int, before end: Int) -> TypedHeadingToken? {
        guard let textStorage, location < end else { return nil }
        let remaining = (textStorage.string as NSString).substring(
            with: NSRange(location: location, length: end - location)
        )
        let hashes = remaining.prefix(while: { $0 == "#" })
        guard (1...3).contains(hashes.count), hashes.count < remaining.count else { return nil }
        let nextIndex = remaining.index(remaining.startIndex, offsetBy: hashes.count)
        guard remaining[nextIndex].isWhitespace else { return nil }
        return TypedHeadingToken(length: hashes.count + 1, level: hashes.count)
    }

    private func typedTaskToken(at location: Int, before end: Int) -> TypedToken? {
        guard let textStorage, location < end else { return nil }
        let remaining = (textStorage.string as NSString).substring(
            with: NSRange(location: location, length: end - location)
        )
        if remaining.hasPrefix("[ ]") {
            return TypedToken(length: remaining.hasPrefix("[ ] ") ? 4 : 3, ordered: false, ordinal: 1, checked: false)
        }
        if remaining.hasPrefix("[]") {
            return TypedToken(length: remaining.hasPrefix("[] ") ? 3 : 2, ordered: false, ordinal: 1, checked: false)
        }
        if remaining.hasPrefix("[x]") || remaining.hasPrefix("[X]") {
            return TypedToken(
                length: remaining.hasPrefix("[x] ") || remaining.hasPrefix("[X] ") ? 4 : 3,
                ordered: false,
                ordinal: 1,
                checked: true
            )
        }
        return nil
    }

    private func typedListToken(at location: Int, before end: Int) -> TypedToken? {
        guard let textStorage, location < end else { return nil }
        let remaining = (textStorage.string as NSString).substring(
            with: NSRange(location: location, length: end - location)
        )
        if remaining.hasPrefix("*") || remaining.hasPrefix("-") {
            let hasSpace = remaining.count > 1 && remaining[remaining.index(after: remaining.startIndex)].isWhitespace
            return TypedToken(length: hasSpace ? 2 : 1, ordered: false, ordinal: 1, checked: false)
        }
        let digits = remaining.prefix(while: { $0.isNumber })
        guard !digits.isEmpty,
              remaining.dropFirst(digits.count).first == ".",
              let ordinal = Int(digits)
        else { return nil }
        let markerLength = digits.count + 1
        let hasSpace = remaining.count > markerLength && remaining[remaining.index(remaining.startIndex, offsetBy: markerLength)].isWhitespace
        return TypedToken(length: hasSpace ? markerLength + 1 : markerLength, ordered: true, ordinal: ordinal, checked: false)
    }

    private func convertToTask(token: TypedToken, at location: Int, existingList: ListMarker?) {
        guard let textStorage else { return }
        let attributes = textStorage.attributes(at: location, effectiveRange: nil)
        let typedRange = NSRange(location: location, length: token.length)
        let replacement = taskMarkerReplacement(checked: token.checked, basedOn: attributes)
        textStorage.replaceCharacters(in: typedRange, with: replacement)

        let lineLocation = existingList?.markerStart ?? location
        let updatedLineRange = (string as NSString).paragraphRange(
            for: NSRange(location: lineLocation, length: 0)
        )
        let oldPrefixLength = existingList?.prefixLength ?? 0
        // The typed token was part of the item text, not the existing list
        // prefix. The replacement becomes a new prefix in addition to it.
        let prefixLength = oldPrefixLength + replacement.length
        var listAttributes: [NSAttributedString.Key: Any] = [
            .markdownBlockKind: "list",
            .markdownListKind: existingList?.ordered == true ? "ordered" : "unordered",
            .markdownListDepth: existingList?.depth ?? 0,
            .markdownListOrdinal: existingList?.ordinal ?? 1,
            .markdownListPrefixLength: prefixLength,
            .markdownListTask: true,
            .markdownListChecked: token.checked,
        ]
        if let quoteDepth = existingList?.quoteDepth {
            listAttributes[.markdownQuoteDepth] = quoteDepth
        }
        textStorage.addAttributes(listAttributes, range: updatedLineRange)
    }

    private func convertToHeading(
        token: TypedHeadingToken,
        at location: Int,
        lineRange: NSRange
    ) {
        guard let textStorage else { return }
        let attributes = textStorage.attributes(at: location, effectiveRange: nil)
        let bodyFont = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 17)
        textStorage.replaceCharacters(
            in: NSRange(location: location, length: token.length),
            with: ""
        )

        let updatedLineRange = (string as NSString).paragraphRange(
            for: NSRange(location: lineRange.location, length: 0)
        )
        let contentEnd = contentEnd(of: updatedLineRange)
        let contentRange = NSRange(
            location: location,
            length: max(0, contentEnd - location)
        )
        let headingFont = headingFont(for: bodyFont, level: token.level)
        if contentRange.length > 0 {
            textStorage.enumerateAttribute(.markdownInlineStyle, in: contentRange) { value, range, _ in
                let style = (value as? Int) ?? 0
                var styledFont = headingFont
                if style & InlineStyle.bold.rawValue != 0 {
                    styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .boldFontMask)
                }
                if style & InlineStyle.italic.rawValue != 0 {
                    styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .italicFontMask)
                }
                textStorage.addAttribute(.font, value: styledFont, range: range)
            }
            textStorage.addAttributes([
                .markdownBlockKind: "heading",
                .markdownHeadingLevel: token.level,
                .markdownProtected: false,
            ], range: updatedLineRange)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = token.level == 1 ? bodyFont.pointSize * 0.35 : bodyFont.pointSize * 0.2
        paragraphStyle.paragraphSpacing = bodyFont.pointSize * 0.35
        paragraphStyle.lineHeightMultiple = 1.2
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: updatedLineRange)

        var newTypingAttributes = attributes
        newTypingAttributes[.font] = headingFont
        newTypingAttributes[.markdownBlockKind] = "heading"
        newTypingAttributes[.markdownHeadingLevel] = token.level
        newTypingAttributes[.markdownInlineStyle] = 0
        newTypingAttributes[.markdownProtected] = false
        typingAttributes = newTypingAttributes
    }

    private func headingFont(for bodyFont: NSFont, level: Int) -> NSFont {
        let multiplier: CGFloat
        switch level {
        case 1: multiplier = 2.0
        case 2: multiplier = 1.6
        default: multiplier = 1.35
        }
        return NSFont.systemFont(
            ofSize: bodyFont.pointSize * multiplier,
            weight: level <= 2 ? .bold : .semibold
        )
    }

    private func convertToList(token: TypedToken, at location: Int, lineRange: NSRange) {
        guard let textStorage else { return }
        let marker = token.ordered ? "\(token.ordinal).  " : "•  "
        let attributes = textStorage.attributes(at: location, effectiveRange: nil)
        let replacement = NSAttributedString(string: marker, attributes: attributes.merging([
            .markdownBlockKind: "list",
            .markdownListKind: token.ordered ? "ordered" : "unordered",
            .markdownListDepth: 0,
            .markdownListOrdinal: token.ordinal,
            .markdownListPrefixLength: (marker as NSString).length,
            .markdownListTask: false,
            .markdownListChecked: false,
            .markdownProtected: true,
        ]) { _, new in new })
        textStorage.replaceCharacters(in: NSRange(location: location, length: token.length), with: replacement)
        let updatedLineRange = (string as NSString).paragraphRange(
            for: NSRange(location: lineRange.location, length: 0)
        )
        textStorage.addAttributes([
            .markdownBlockKind: "list",
            .markdownListKind: token.ordered ? "ordered" : "unordered",
            .markdownListDepth: 0,
            .markdownListOrdinal: token.ordinal,
            .markdownListPrefixLength: (marker as NSString).length,
            .markdownListTask: false,
            .markdownListChecked: false,
        ], range: updatedLineRange)
    }

    private func taskMarkerReplacement(
        checked: Bool,
        basedOn attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 17)
        let dimension = font.pointSize * 0.78
        let image = NSImage(
            systemSymbolName: checked ? "checkmark.square" : "square",
            accessibilityDescription: checked ? "Checked" : "Unchecked"
        )
        image?.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0,
            y: (font.pointSize - dimension) / 2,
            width: dimension,
            height: dimension
        )

        let replacement = NSMutableAttributedString(
            attributedString: NSAttributedString(attachment: attachment)
        )
        replacement.append(NSAttributedString(string: "\t", attributes: attributes))
        replacement.addAttributes([
            .font: font,
            .foregroundColor: attributes[.foregroundColor] as? NSColor ?? .secondaryLabelColor,
            .markdownProtected: true,
            .markdownInlineStyle: 0,
        ], range: NSRange(location: 0, length: replacement.length))
        replacement.addAttribute(
            .markdownTaskChecked,
            value: checked,
            range: NSRange(location: 0, length: 1)
        )
        replacement.addAttribute(.markdownTaskIndex, value: 0, range: NSRange(location: 0, length: 1))
        return replacement
    }

    private func renumberTaskMarkers() {
        guard let textStorage else { return }
        var nextIndex = 0
        textStorage.enumerateAttribute(
            .markdownTaskChecked,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, range, _ in
            guard value != nil else { return }
            textStorage.addAttribute(.markdownTaskIndex, value: nextIndex, range: range)
            nextIndex += 1
        }
    }

    private func blockKind(in range: NSRange) -> String? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let index = min(range.location, textStorage.length - 1)
        return textStorage.attribute(.markdownBlockKind, at: index, effectiveRange: nil) as? String
    }

    private func contentEnd(of range: NSRange) -> Int {
        guard let textStorage else { return range.location }
        let end = NSMaxRange(range)
        if end > range.location,
           (textStorage.string as NSString).character(at: end - 1) == 10
        { return end - 1 }
        return end
    }

    private func selectedParagraphRanges() -> [NSRange] {
        guard let textStorage, textStorage.length > 0 else { return [] }
        let selected = selectedRange()
        let start = min(selected.location, textStorage.length - 1)
        let end = min(max(selected.location + max(selected.length, 1) - 1, start), textStorage.length - 1)
        var ranges: [NSRange] = []
        var cursor = start
        while cursor <= end {
            let range = (string as NSString).paragraphRange(for: NSRange(location: cursor, length: 0))
            ranges.append(range)
            let next = NSMaxRange(range)
            if next <= cursor { break }
            cursor = next
        }
        return ranges
    }

    private func addListMarker(ordered: Bool, in range: NSRange, textStorage: NSTextStorage) {
        let start = range.location
        let existing = textStorage.attributes(at: min(start, textStorage.length - 1), effectiveRange: nil)
        let marker = ordered ? "1.  " : "•  "
        let value = NSAttributedString(string: marker, attributes: existing.merging([
            .markdownBlockKind: "list",
            .markdownListKind: ordered ? "ordered" : "unordered",
            .markdownListDepth: 0,
            .markdownListOrdinal: 1,
            .markdownListPrefixLength: (marker as NSString).length,
            .markdownListTask: false,
            .markdownListChecked: false,
            .markdownProtected: true,
            .markdownInlineStyle: 0,
        ]) { _, new in new })
        textStorage.insert(value, at: start)
        textStorage.addAttributes([
            .markdownBlockKind: "list",
            .markdownListKind: ordered ? "ordered" : "unordered",
            .markdownListDepth: 0,
            .markdownListOrdinal: 1,
            .markdownListPrefixLength: (marker as NSString).length,
            .markdownListTask: false,
            .markdownListChecked: false,
            .markdownProtected: true,
        ], range: NSRange(location: start, length: value.length))
    }

    private func removeListMarker(_ marker: ListMarker, in range: NSRange, textStorage: NSTextStorage) {
        textStorage.deleteCharacters(in: NSRange(location: marker.markerStart, length: marker.contentStart - marker.markerStart))
        let end = min(textStorage.length, contentEnd(of: range) - (marker.contentStart - marker.markerStart))
        guard end > marker.markerStart else { return }
        textStorage.addAttribute(.markdownBlockKind, value: "paragraph", range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.addAttribute(.markdownProtected, value: false, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownListKind, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownListDepth, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownListOrdinal, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownListPrefixLength, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownListTask, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownListChecked, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownTaskChecked, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
        textStorage.removeAttribute(.markdownTaskIndex, range: NSRange(location: marker.markerStart, length: end - marker.markerStart))
    }

    private func listAttributes(
        basedOn attributes: [NSAttributedString.Key: Any],
        ordered: Bool,
        depth: Int,
        ordinal: Int,
        prefixLength: Int,
        quoteDepth: Int,
        task: Bool = false,
        checked: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        attributes.merging([
            .markdownBlockKind: "list",
            .markdownListKind: ordered ? "ordered" : "unordered",
            .markdownListDepth: depth,
            .markdownListOrdinal: ordinal,
            .markdownListPrefixLength: prefixLength,
            .markdownListTask: task,
            .markdownListChecked: checked,
            .markdownQuoteDepth: quoteDepth,
            .markdownProtected: true,
        ]) { _, new in new }
    }

    func allowsChange(in range: NSRange, replacementString: String?) -> Bool {
        guard !allowProtectedMutation, let textStorage else { return true }
        // Deleting a selection is an intentional way to remove complete
        // rendered list items, including their protected bullet or checkbox
        // markers. Keep protection for typing or pasting over those markers.
        if range.length > 0, replacementString == nil || replacementString?.isEmpty == true {
            return true
        }
        if range.length > 0 {
            var blocked = false
            textStorage.enumerateAttribute(.markdownProtected, in: range) { value, _, stop in
                if value as? Bool == true {
                    blocked = true
                    stop.pointee = true
                }
            }
            if blocked { return false }
        }
        if range.location < textStorage.length,
           textStorage.attribute(.markdownProtected, at: range.location, effectiveRange: nil) as? Bool == true
        {
            return false
        }
        return true
    }

    private func updateReadingInsets() {
        let maximumWidth = CGFloat(
            MarkdownReadingLayout.maximumTextContainerWidth(fontScale: Double(fontScale))
        )
        let horizontal = max(34, (bounds.width - maximumWidth) / 2)
        textContainerInset = NSSize(width: horizontal, height: 38)
    }
}
