import AppKit
import Foundation

public extension NSAttributedString.Key {
    static let markdownTaskIndex = NSAttributedString.Key("MarkdownPreviewTaskIndex")
    static let markdownTaskChecked = NSAttributedString.Key("MarkdownPreviewTaskChecked")
    static let markdownBlockKind = NSAttributedString.Key("MarkdownPreviewBlockKind")
    static let markdownListKind = NSAttributedString.Key("MarkdownPreviewListKind")
    static let markdownListDepth = NSAttributedString.Key("MarkdownPreviewListDepth")
    static let markdownListOrdinal = NSAttributedString.Key("MarkdownPreviewListOrdinal")
    static let markdownListPrefixLength = NSAttributedString.Key("MarkdownPreviewListPrefixLength")
    static let markdownListTask = NSAttributedString.Key("MarkdownPreviewListTask")
    static let markdownListChecked = NSAttributedString.Key("MarkdownPreviewListChecked")
    static let markdownHeadingLevel = NSAttributedString.Key("MarkdownPreviewHeadingLevel")
    static let markdownCodeLanguage = NSAttributedString.Key("MarkdownPreviewCodeLanguage")
    static let markdownQuoteDepth = NSAttributedString.Key("MarkdownPreviewQuoteDepth")
    static let markdownTableHeader = NSAttributedString.Key("MarkdownPreviewTableHeader")
    static let markdownInlineStyle = NSAttributedString.Key("MarkdownPreviewInlineStyle")
    static let markdownProtected = NSAttributedString.Key("MarkdownPreviewProtected")
}

public struct MarkdownRenderOptions: Sendable {
    public enum Palette: Sendable {
        case screen
        case print
    }

    public static let minimumScale = CGFloat(MarkdownFontScalePreference.minimumScale)
    public static let maximumScale = CGFloat(MarkdownFontScalePreference.maximumScale)
    public static let defaultScale = CGFloat(MarkdownFontScalePreference.defaultScale)

    public let fontScale: CGFloat
    public let palette: Palette

    public init(fontScale: CGFloat = defaultScale, palette: Palette = .screen) {
        if fontScale.isFinite {
            self.fontScale = min(max(fontScale, Self.minimumScale), Self.maximumScale)
        } else {
            self.fontScale = Self.defaultScale
        }
        self.palette = palette
    }
}

public struct MarkdownAttributedRenderer: Sendable {
    private let parser = MarkdownParser()

    public init() {}

    @MainActor
    public func render(_ source: String, options: MarkdownRenderOptions = .init()) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let bodySize = 17 * options.fontScale
        let colors = Colors(options.palette)
        var nextTaskIndex = 0

        for block in parser.parse(source) {
            append(
                block,
                to: output,
                bodySize: bodySize,
                colors: colors,
                nextTaskIndex: &nextTaskIndex,
                quoteDepth: 0
            )
        }

        while output.string.hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
        return NSAttributedString(attributedString: output)
    }

    @MainActor
    public func plainText(_ source: String) -> String {
        let rendered = render(source)
        var result = ""
        rendered.enumerateAttributes(
            in: NSRange(location: 0, length: rendered.length)
        ) { attributes, range, _ in
            if let checked = attributes[.markdownTaskChecked] as? Bool {
                result += checked ? "☑︎" : "☐"
            } else {
                result += (rendered.string as NSString).substring(with: range)
            }
        }
        return result
    }

    @MainActor
    private func append(
        _ block: MarkdownBlock,
        to output: NSMutableAttributedString,
        bodySize: CGFloat,
        colors: Colors,
        nextTaskIndex: inout Int,
        quoteDepth: Int
    ) {
        switch block {
        case let .heading(level, text):
            let multipliers: [CGFloat] = [2.0, 1.6, 1.35, 1.2, 1.1, 1.0]
            let size = bodySize * multipliers[level - 1]
            let font = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
            let value = inline(text, font: font, colors: colors)
            addBlockAttributes(to: value, kind: "heading", quoteDepth: quoteDepth)
            value.addAttribute(.markdownProtected, value: false, range: NSRange(location: 0, length: value.length))
            applyParagraphStyle(to: value, before: level == 1 ? bodySize * 0.35 : bodySize * 0.2, after: bodySize * 0.35)
            value.addAttribute(.markdownHeadingLevel, value: level, range: NSRange(location: 0, length: value.length))
            output.append(value)
            appendNewline(
                to: output,
                font: font,
                attributes: [
                    .markdownBlockKind: "heading",
                    .markdownHeadingLevel: level,
                    .markdownQuoteDepth: quoteDepth,
                ]
            )

        case let .paragraph(text):
            let font = NSFont.systemFont(ofSize: bodySize)
            let value = inline(text, font: font, colors: colors)
            addBlockAttributes(to: value, kind: "paragraph", quoteDepth: quoteDepth)
            applyParagraphStyle(to: value, after: bodySize * 0.75, lineHeight: 1.32)
            output.append(value)
            appendNewline(to: output, font: font)

        case let .unorderedList(items):
            appendList(
                items,
                ordered: false,
                to: output,
                bodySize: bodySize,
                colors: colors,
                nextTaskIndex: &nextTaskIndex,
                quoteDepth: quoteDepth
            )

        case let .orderedList(items):
            appendList(
                items,
                ordered: true,
                to: output,
                bodySize: bodySize,
                colors: colors,
                nextTaskIndex: &nextTaskIndex,
                quoteDepth: quoteDepth
            )

        case let .blockquote(blocks):
            let start = output.length
            for quotedBlock in blocks {
                output.append(NSAttributedString(
                    string: "▍ ",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: bodySize),
                        .foregroundColor: colors.secondary,
                        .markdownQuoteDepth: quoteDepth + 1,
                        .markdownProtected: true,
                    ]
                ))
                append(
                    quotedBlock,
                    to: output,
                    bodySize: bodySize,
                    colors: colors,
                    nextTaskIndex: &nextTaskIndex,
                    quoteDepth: quoteDepth + 1
                )
            }
            if output.length > start {
                let range = NSRange(location: start, length: output.length - start)
                output.addAttribute(.foregroundColor, value: colors.secondary, range: range)
            }

        case let .code(language, text):
            let font = NSFont.monospacedSystemFont(ofSize: bodySize * 0.9, weight: .regular)
            let label = language.map { "\($0)\n" } ?? ""
            let value = NSMutableAttributedString(
                string: label + text,
                attributes: [
                    .font: font,
                    .foregroundColor: colors.code,
                    .backgroundColor: colors.codeBackground,
                ]
            )
            addBlockAttributes(to: value, kind: "code", quoteDepth: quoteDepth)
            value.addAttribute(.markdownCodeLanguage, value: language ?? "", range: NSRange(location: 0, length: value.length))
            if !label.isEmpty {
                value.addAttribute(
                    .markdownProtected,
                    value: true,
                    range: NSRange(location: 0, length: (label as NSString).length)
                )
            }
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = bodySize * 0.25
            style.paragraphSpacing = bodySize * 0.8
            style.lineSpacing = bodySize * 0.25
            style.headIndent = bodySize * 0.75
            style.firstLineHeadIndent = bodySize * 0.75
            style.tailIndent = -bodySize * 0.75
            value.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: value.length))
            output.append(value)
            appendNewline(to: output, font: font)

        case .thematicBreak:
            let font = NSFont.systemFont(ofSize: bodySize)
            let value = NSMutableAttributedString(
                string: "━━━━━━━━━━━━━━━━━━━━━━━━",
                attributes: [.font: font, .foregroundColor: colors.separator]
            )
            addBlockAttributes(to: value, kind: "thematicBreak", quoteDepth: quoteDepth)
            value.addAttribute(.markdownProtected, value: true, range: NSRange(location: 0, length: value.length))
            applyParagraphStyle(to: value, before: bodySize * 0.4, after: bodySize * 0.7)
            output.append(value)
            appendNewline(to: output, font: font)

        case let .table(headers, rows):
            appendTable(
                headers: headers,
                rows: rows,
                to: output,
                bodySize: bodySize,
                colors: colors,
                quoteDepth: quoteDepth
            )
        }
    }

    @MainActor
    private func addBlockAttributes(to value: NSMutableAttributedString, kind: String, quoteDepth: Int) {
        guard value.length > 0 else { return }
        value.addAttribute(.markdownBlockKind, value: kind, range: NSRange(location: 0, length: value.length))
        value.addAttribute(.markdownQuoteDepth, value: quoteDepth, range: NSRange(location: 0, length: value.length))
    }

    @MainActor
    private func appendList(
        _ items: [MarkdownBlock.ListItem],
        ordered: Bool,
        to output: NSMutableAttributedString,
        bodySize: CGFloat,
        colors: Colors,
        nextTaskIndex: inout Int,
        quoteDepth: Int
    ) {
        let font = NSFont.systemFont(ofSize: bodySize)
        for (index, item) in items.enumerated() {
            let marker: String
            if item.checkbox != nil {
                marker = "\u{FFFC}"
            } else if ordered {
                marker = "\(item.ordinal ?? index + 1)."
            } else {
                marker = item.depth.isMultiple(of: 2) ? "•" : "◦"
            }
            let indentation = String(repeating: "    ", count: item.depth)
            let prefix = indentation + marker + (item.checkbox == nil ? "  " : "\t")
            let value = NSMutableAttributedString(
                string: prefix,
                attributes: [
                    .font: font,
                    .foregroundColor: colors.secondary,
                    .markdownProtected: true,
                ]
            )
            if item.checkbox != nil {
                let markerLocation = (indentation as NSString).length
                let markerRange = NSRange(location: markerLocation, length: 1)
                let markerImage = taskMarkerImage(
                    checked: item.checkbox == true,
                    size: bodySize * 0.78,
                    color: colors.secondary
                )
                let attachment = NSTextAttachment()
                attachment.image = markerImage
                let markerDimension = bodySize * 0.78
                attachment.bounds = NSRect(
                    x: 0,
                    y: (bodySize - markerDimension) / 2,
                    width: markerDimension,
                    height: markerDimension
                )
                value.replaceCharacters(
                    in: markerRange,
                    with: NSAttributedString(attachment: attachment)
                )
                value.addAttribute(
                    .markdownTaskIndex,
                    value: nextTaskIndex,
                    range: markerRange
                )
                value.addAttribute(
                    .markdownTaskChecked,
                    value: item.checkbox == true,
                    range: markerRange
                )
                nextTaskIndex += 1
            }
            value.append(inline(item.text, font: font, colors: colors))
            addBlockAttributes(to: value, kind: "list", quoteDepth: quoteDepth)
            value.addAttributes([
                .markdownListKind: ordered ? "ordered" : "unordered",
                .markdownListDepth: item.depth,
                .markdownListOrdinal: item.ordinal ?? index + 1,
                .markdownListPrefixLength: (prefix as NSString).length,
                .markdownListTask: item.checkbox != nil,
                .markdownListChecked: item.checkbox == true,
            ], range: NSRange(location: 0, length: value.length))
            let style = NSMutableParagraphStyle()
            let indent = bodySize * CGFloat(1.7 + Double(item.depth) * 1.25)
            style.firstLineHeadIndent = bodySize * CGFloat(Double(item.depth) * 1.25)
            style.headIndent = indent
            if item.checkbox != nil {
                let indentationWidth = NSAttributedString(
                    string: indentation,
                    attributes: [.font: font]
                ).size().width
                let markerWidth = max(
                    bodySize * 0.78,
                    bodySize * 0.78
                )
                let spacingWidth = NSAttributedString(
                    string: "  ",
                    attributes: [.font: font]
                ).size().width
                style.tabStops = [
                    NSTextTab(
                        textAlignment: .left,
                        location: style.firstLineHeadIndent + indentationWidth + markerWidth + spacingWidth
                    ),
                ]
            }
            style.paragraphSpacing = index == items.count - 1 ? bodySize * 0.75 : bodySize * 0.2
            style.lineHeightMultiple = 1.28
            value.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: value.length))
            output.append(value)
            appendNewline(to: output, font: font)
        }
    }

    @MainActor
    private func appendTable(
        headers: [String],
        rows: [[String]],
        to output: NSMutableAttributedString,
        bodySize: CGFloat,
        colors: Colors,
        quoteDepth: Int
    ) {
        let font = NSFont.systemFont(ofSize: bodySize * 0.95)
        let bold = NSFont.systemFont(ofSize: bodySize * 0.95, weight: .semibold)
        let tabs = (1..<max(headers.count, 2)).map {
            NSTextTab(textAlignment: .left, location: CGFloat($0) * bodySize * 10)
        }

        for (rowIndex, row) in ([headers] + rows).enumerated() {
            let value = NSMutableAttributedString()
            for (cellIndex, cell) in row.enumerated() {
                if cellIndex > 0 { value.append(NSAttributedString(string: "\t")) }
                value.append(inline(cell, font: rowIndex == 0 ? bold : font, colors: colors))
            }
            let style = NSMutableParagraphStyle()
            style.tabStops = tabs
            style.paragraphSpacing = rowIndex == rows.count ? bodySize * 0.75 : bodySize * 0.25
            style.lineHeightMultiple = 1.25
            value.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: value.length))
            addBlockAttributes(to: value, kind: "table", quoteDepth: quoteDepth)
            value.addAttribute(.markdownTableHeader, value: rowIndex == 0, range: NSRange(location: 0, length: value.length))
            value.addAttribute(.markdownProtected, value: false, range: NSRange(location: 0, length: value.length))
            if rowIndex == 0 {
                value.addAttribute(.backgroundColor, value: colors.tableHeader, range: NSRange(location: 0, length: value.length))
            }
            output.append(value)
            appendNewline(to: output, font: font)
        }
    }

    @MainActor
    private func inline(_ markdown: String, font: NSFont, colors: Colors) -> NSMutableAttributedString {
        let parsed: NSAttributedString
        do {
            parsed = try NSAttributedString(
                markdown: Data(markdown.utf8),
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
                baseURL: nil
            )
        } catch {
            parsed = NSAttributedString(string: markdown)
        }

        let value = NSMutableAttributedString(attributedString: parsed)
        let fullRange = NSRange(location: 0, length: value.length)
        value.addAttributes([.font: font, .foregroundColor: colors.text], range: fullRange)
        value.addAttribute(.markdownInlineStyle, value: 0, range: fullRange)
        value.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { attribute, range, _ in
            guard let rawValue = attribute as? Int else { return }
            var style = 0
            if rawValue & 1 != 0 { style |= 1 }
            if rawValue & 2 != 0 { style |= 2 }
            if rawValue & 8 != 0 { style |= 4 }
            value.addAttribute(.markdownInlineStyle, value: style, range: range)
            var styledFont = font
            if rawValue & 2 != 0 {
                styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .boldFontMask)
            }
            if rawValue & 1 != 0 {
                styledFont = NSFontManager.shared.convert(styledFont, toHaveTrait: .italicFontMask)
            }
            if rawValue & 8 != 0 {
                styledFont = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.93, weight: .regular)
                value.addAttribute(.backgroundColor, value: colors.codeBackground, range: range)
            }
            value.addAttribute(.font, value: styledFont, range: range)
            if rawValue & 4 != 0 {
                value.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        value.enumerateAttribute(.link, in: fullRange) { attribute, range, _ in
            guard attribute != nil else { return }
            value.addAttributes([
                .foregroundColor: colors.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        }
        return value
    }

    @MainActor
    private func taskMarkerImage(checked: Bool, size: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.setStroke()

        let strokeWidth = max(1, size * 0.1)
        let box = NSRect(
            x: strokeWidth / 2,
            y: strokeWidth / 2,
            width: size - strokeWidth,
            height: size - strokeWidth
        )
        let boxPath = NSBezierPath(
            roundedRect: box,
            xRadius: size * 0.15,
            yRadius: size * 0.15
        )
        boxPath.lineWidth = strokeWidth
        boxPath.stroke()

        if checked {
            let checkPath = NSBezierPath()
            checkPath.lineWidth = strokeWidth
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            checkPath.move(to: NSPoint(x: size * 0.24, y: size * 0.52))
            checkPath.line(to: NSPoint(x: size * 0.44, y: size * 0.3))
            checkPath.line(to: NSPoint(x: size * 0.78, y: size * 0.7))
            checkPath.stroke()
        }

        image.unlockFocus()
        return image
    }

    private func appendNewline(
        to output: NSMutableAttributedString,
        font: NSFont,
        attributes: [NSAttributedString.Key: Any] = [:]
    ) {
        var newlineAttributes = attributes
        newlineAttributes[.font] = font
        output.append(NSAttributedString(string: "\n", attributes: newlineAttributes))
    }

    private func applyParagraphStyle(
        to value: NSMutableAttributedString,
        before: CGFloat = 0,
        after: CGFloat,
        lineHeight: CGFloat = 1.2
    ) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineHeightMultiple = lineHeight
        value.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: value.length))
    }
}

/// Converts the small, rendered editing surface back into Markdown.
///
/// The renderer places structural attributes on each visible block so this
/// serializer can keep headings, quotes, code blocks, tables, and list rows
/// intact while the user edits their visible text.
public struct MarkdownSourceSerializer: Sendable {
    public init() {}

    @MainActor
    public func serialize(_ rendered: NSAttributedString) -> String {
        guard rendered.length > 0 else { return "" }

        let string = rendered.string as NSString
        var paragraphs: [NSRange] = []
        var location = 0
        while location < rendered.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(range)
            location = NSMaxRange(range)
        }

        var entries: [(kind: String, quoteDepth: Int, text: String)] = []
        var index = 0
        while index < paragraphs.count {
            let paragraph = paragraphs[index]
            let start = firstVisibleIndex(in: rendered, paragraph: paragraph)
            let metadataStart = blockMetadataStart(in: rendered, paragraph: paragraph)
            let kind = rendered.attribute(.markdownBlockKind, at: metadataStart, effectiveRange: nil) as? String

            if kind == "code" {
                let language = rendered.attribute(.markdownCodeLanguage, at: metadataStart, effectiveRange: nil) as? String ?? ""
                let quoteDepth = quoteDepth(in: rendered, at: start)
                var end = NSMaxRange(paragraph)
                var next = index + 1
                while next < paragraphs.count {
                    let nextStart = blockMetadataStart(in: rendered, paragraph: paragraphs[next])
                    guard rendered.attribute(.markdownBlockKind, at: nextStart, effectiveRange: nil) as? String == "code"
                    else { break }
                    end = NSMaxRange(paragraphs[next])
                    next += 1
                }
                if end > paragraph.location,
                   rendered.attribute(.markdownBlockKind, at: end - 1, effectiveRange: nil) == nil
                {
                    end -= 1
                }
                var code = string.substring(with: NSRange(location: paragraph.location, length: max(0, end - paragraph.location)))
                if let newline = code.firstIndex(of: "\n") {
                    code = String(code[code.index(after: newline)...])
                } else {
                    code = ""
                }
                let fence = language.isEmpty ? "```" : "```\(language)"
                let quoted = quoteLines("\(fence)\n\(code)\n```", depth: quoteDepth)
                entries.append(("code", quoteDepth, quoted))
                index = next
                continue
            }

            if kind == "table" {
                let quoteDepth = quoteDepth(in: rendered, at: start)
                var rows: [String] = []
                var next = index
                while next < paragraphs.count {
                    let nextStart = blockMetadataStart(in: rendered, paragraph: paragraphs[next])
                    guard rendered.attribute(.markdownBlockKind, at: nextStart, effectiveRange: nil) as? String == "table"
                    else { break }
                    rows.append(serializeParagraph(rendered, range: paragraphs[next]))
                    next += 1
                }
                if let header = rows.first {
                    let columnCount = max(1, header.split(separator: "|", omittingEmptySubsequences: true).count)
                    let divider = quoteLines(
                        "| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |",
                        depth: quoteDepth
                    )
                    rows.insert(divider, at: 1)
                }
                entries.append(("table", quoteDepth, rows.joined(separator: "\n")))
                index = next
                continue
            }

            let line = serializeParagraph(rendered, range: paragraph)
            let lineKind = kind ?? "paragraph"
            entries.append((lineKind, quoteDepth(in: rendered, at: start), line))
            index += 1
        }

        var output: [String] = []
        var previousKind: String?
        for entry in entries {
            if let previous = output.last,
               !previous.isEmpty,
               !canShareListSpacing(with: entry.kind, previousKind: previousKind)
            {
                output.append("")
            }
            output.append(entry.text)
            previousKind = entry.kind
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    @MainActor
    private func serializeParagraph(_ rendered: NSAttributedString, range: NSRange) -> String {
        let string = rendered.string as NSString
        var end = NSMaxRange(range)
        if end > range.location, string.character(at: end - 1) == 10 { end -= 1 }
        guard end > range.location else { return "" }

        let quoteDepth = quoteDepth(in: rendered, at: range.location)
        var contentStart = range.location
        var prefixLength = 0
        let visible = string.substring(with: NSRange(location: range.location, length: end - range.location))
        var quotePrefix = visible
        while quotePrefix.hasPrefix("▍ ") {
            prefixLength += 2
            quotePrefix.removeFirst(2)
        }
        contentStart += prefixLength

        let kind = rendered.attribute(.markdownBlockKind, at: min(contentStart, end - 1), effectiveRange: nil) as? String
        let body: String
        switch kind {
        case "heading":
            let level = rendered.attribute(.markdownHeadingLevel, at: contentStart, effectiveRange: nil) as? Int ?? 1
            body = String(repeating: "#", count: min(max(level, 1), 6)) + " " + serializeInline(
                rendered,
                range: NSRange(location: contentStart, length: end - contentStart)
            )
        case "list":
            let listKind = rendered.attribute(.markdownListKind, at: contentStart, effectiveRange: nil) as? String ?? "unordered"
            let depth = rendered.attribute(.markdownListDepth, at: contentStart, effectiveRange: nil) as? Int ?? 0
            let ordinal = rendered.attribute(.markdownListOrdinal, at: contentStart, effectiveRange: nil) as? Int ?? 1
            let prefix = rendered.attribute(.markdownListPrefixLength, at: contentStart, effectiveRange: nil) as? Int ?? 0
            let itemStart = min(end, contentStart + prefix)
            let marker: String
            if let isTask = rendered.attribute(.markdownListTask, at: contentStart, effectiveRange: nil) as? Bool,
               isTask,
               let checked = rendered.attribute(.markdownListChecked, at: contentStart, effectiveRange: nil) as? Bool
            {
                let listMarker = listKind == "ordered" ? "\(ordinal)." : "-"
                marker = "\(listMarker) [\(checked ? "x" : " ")]"
            } else if listKind == "ordered" {
                marker = "\(ordinal)."
            } else {
                marker = "-"
            }
            body = String(repeating: "  ", count: max(depth, 0)) + marker + " " + serializeInline(
                rendered,
                range: NSRange(location: itemStart, length: end - itemStart)
            )
        case "table":
            var cells: [String] = []
            var cellStart = contentStart
            while cellStart <= end {
                let tab = string.range(of: "\t", options: [], range: NSRange(location: cellStart, length: end - cellStart))
                let cellEnd = tab.location == NSNotFound ? end : tab.location
                cells.append(serializeInline(
                    rendered,
                    range: NSRange(location: cellStart, length: max(0, cellEnd - cellStart))
                ))
                guard tab.location != NSNotFound else { break }
                cellStart = tab.location + tab.length
            }
            body = "| " + cells.joined(separator: " | ") + " |"
        case "code":
            body = string.substring(with: NSRange(location: contentStart, length: end - contentStart))
        case "thematicBreak":
            body = "---"
        default:
            body = serializeInline(
                rendered,
                range: NSRange(location: contentStart, length: end - contentStart)
            )
        }

        return quoteLines(body, depth: quoteDepth)
    }

    @MainActor
    private func serializeInline(_ rendered: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        let string = rendered.string as NSString
        var result = ""
        rendered.enumerateAttributes(in: range) { attributes, subrange, _ in
            var value = string.substring(with: subrange)
            let style = attributes[.markdownInlineStyle] as? Int ?? 0
            if let link = attributes[.link] {
                let destination = (link as? URL)?.absoluteString ?? String(describing: link)
                value = "[\(value)](\(destination))"
            } else if style & 4 != 0 {
                value = "`\(value)`"
            } else {
                value = escapePlainInline(value)
                if style & 2 != 0 { value = "**\(value)**" }
                if style & 1 != 0 { value = "*\(value)*" }
            }
            result += value
        }
        return result
    }

    private func quoteDepth(in rendered: NSAttributedString, at location: Int) -> Int {
        guard rendered.length > 0 else { return 0 }
        return rendered.attribute(.markdownQuoteDepth, at: min(location, rendered.length - 1), effectiveRange: nil) as? Int ?? 0
    }

    private func firstVisibleIndex(in rendered: NSAttributedString, paragraph: NSRange) -> Int {
        let string = rendered.string as NSString
        var index = paragraph.location
        while index < NSMaxRange(paragraph), string.character(at: index) == 10 { index += 1 }
        return min(index, max(paragraph.location, NSMaxRange(paragraph) - 1))
    }

    private func blockMetadataStart(in rendered: NSAttributedString, paragraph: NSRange) -> Int {
        let start = firstVisibleIndex(in: rendered, paragraph: paragraph)
        var index = start
        while index < NSMaxRange(paragraph) {
            if rendered.attribute(.markdownBlockKind, at: index, effectiveRange: nil) != nil {
                return index
            }
            index += 1
        }
        return start
    }

    private func quoteLines(_ value: String, depth: Int) -> String {
        guard depth > 0 else { return value }
        let prefix = String(repeating: "> ", count: depth)
        return value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private func canShareListSpacing(with kind: String, previousKind: String?) -> Bool {
        kind == "list" && previousKind == "list"
    }

    private func escapePlainInline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

private struct Colors {
    let text: NSColor
    let secondary: NSColor
    let link: NSColor
    let code: NSColor
    let codeBackground: NSColor
    let separator: NSColor
    let tableHeader: NSColor

    init(_ palette: MarkdownRenderOptions.Palette) {
        switch palette {
        case .screen:
            text = .labelColor
            secondary = .secondaryLabelColor
            link = .linkColor
            code = .labelColor
            codeBackground = .quaternaryLabelColor
            separator = .separatorColor
            tableHeader = .quaternaryLabelColor
        case .print:
            text = .black
            secondary = .darkGray
            link = .systemBlue
            code = .black
            codeBackground = NSColor(white: 0.94, alpha: 1)
            separator = .lightGray
            tableHeader = NSColor(white: 0.92, alpha: 1)
        }
    }
}

public enum MarkdownLinkResolver {
    private static let markdownExtensions = Set(["md", "markdown", "mdown", "mkd"])
    private static let navigationScheme = "markdown-preview"
    private static let navigationHost = "open"

    public static func localMarkdownURL(for linkURL: URL, relativeTo documentURL: URL) -> URL? {
        guard linkURL.scheme == nil || linkURL.isFileURL else { return nil }
        guard !linkURL.relativeString.hasPrefix("#") else { return nil }

        let resolvedURL: URL
        if linkURL.isFileURL {
            resolvedURL = linkURL
        } else {
            let directoryURL = documentURL.deletingLastPathComponent()
            guard let relativeURL = URL(string: linkURL.relativeString, relativeTo: directoryURL) else {
                return nil
            }
            resolvedURL = relativeURL.absoluteURL
        }

        var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        guard let fileURL = components?.url?.standardizedFileURL,
              markdownExtensions.contains(fileURL.pathExtension.lowercased())
        else {
            return nil
        }
        return fileURL
    }

    public static func navigationURL(for fileURL: URL, relativeTo documentURL: URL) -> URL? {
        guard let fileURL = supportedMarkdownFileURL(fileURL) else { return nil }
        let accessDirectoryURL = commonAncestorDirectory(
            of: documentURL.deletingLastPathComponent(),
            and: fileURL.deletingLastPathComponent()
        )
        var components = URLComponents()
        components.scheme = navigationScheme
        components.host = navigationHost
        components.queryItems = [
            URLQueryItem(name: "url", value: fileURL.absoluteString),
            URLQueryItem(name: "directory", value: accessDirectoryURL.absoluteString),
        ]
        return components.url
    }

    public static func navigationRequest(from navigationURL: URL) -> MarkdownLinkNavigationRequest? {
        guard navigationURL.scheme == navigationScheme,
              navigationURL.host == navigationHost,
              let components = URLComponents(url: navigationURL, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let directoryValue = components.queryItems?.first(where: { $0.name == "directory" })?.value,
              let fileURL = URL(string: value),
              let validatedFileURL = supportedMarkdownFileURL(fileURL),
              let directoryURL = URL(string: directoryValue),
              directoryURL.isFileURL,
              contains(validatedFileURL, in: directoryURL)
        else {
            return nil
        }
        return MarkdownLinkNavigationRequest(
            fileURL: validatedFileURL,
            accessDirectoryURL: directoryURL.standardizedFileURL
        )
    }

    private static func supportedMarkdownFileURL(_ url: URL) -> URL? {
        guard url.isFileURL,
              markdownExtensions.contains(url.pathExtension.lowercased())
        else {
            return nil
        }
        return url.standardizedFileURL
    }

    private static func commonAncestorDirectory(of firstURL: URL, and secondURL: URL) -> URL {
        var candidate = firstURL.standardizedFileURL
        let secondURL = secondURL.standardizedFileURL
        while candidate.path != "/", !contains(secondURL, in: candidate) {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    private static func contains(_ fileURL: URL, in directoryURL: URL) -> Bool {
        var directoryPath = directoryURL.standardizedFileURL.path
        while directoryPath.count > 1, directoryPath.hasSuffix("/") {
            directoryPath.removeLast()
        }
        let filePath = fileURL.standardizedFileURL.path
        if directoryPath == "/" { return filePath.hasPrefix("/") }
        return filePath == directoryPath || filePath.hasPrefix(directoryPath + "/")
    }
}

public struct MarkdownLinkNavigationRequest: Equatable, Sendable {
    public let fileURL: URL
    public let accessDirectoryURL: URL
}
