import Foundation

public struct MarkdownHTMLRenderer: Sendable {
    private let parser = MarkdownParser()

    public init() {}

    public func document(
        source: String,
        fontScale: Double = 1,
        title: String = "Markdown Preview"
    ) -> String {
        let scale = fontScale.isFinite ? min(max(fontScale, 0.65), 2.5) : 1
        let body = blocks(parser.parse(source))
        return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>\(escape(title))</title>
              <style>
                :root { color-scheme: light dark; --base: \(17 * scale)px; }
                html { background: Canvas; color: CanvasText; }
                body { box-sizing: border-box; max-width: 860px; margin: 0 auto; padding: 42px 48px 64px;
                       font: var(--base)/1.55 -apple-system, BlinkMacSystemFont, sans-serif; }
                h1,h2,h3,h4,h5,h6 { line-height: 1.2; margin: 1.25em 0 .45em; }
                h1 { font-size: 2em; } h2 { font-size: 1.6em; } h3 { font-size: 1.35em; }
                h4 { font-size: 1.2em; } h5 { font-size: 1.1em; } h6 { font-size: 1em; }
                p { margin: 0 0 .9em; } ul,ol { margin: 0 0 .9em; padding-left: 1.8em; }
                li { margin: .18em 0; } a { color: LinkText; } img { max-width: 100%; height: auto; }
                code,pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
                code { font-size: .93em; background: color-mix(in srgb, CanvasText 9%, transparent); padding: .12em .32em; border-radius: 4px; }
                pre { overflow: auto; padding: 1em 1.1em; border-radius: 8px; background: color-mix(in srgb, CanvasText 8%, transparent); }
                pre code { padding: 0; background: transparent; }
                blockquote { margin: 0 0 1em; padding: .1em 0 .1em 1em; color: GrayText; border-left: 4px solid color-mix(in srgb, CanvasText 25%, transparent); }
                table { width: 100%; border-collapse: collapse; margin: 0 0 1em; }
                th,td { text-align: left; padding: .45em .65em; border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); }
                th { background: color-mix(in srgb, CanvasText 8%, transparent); }
                hr { border: 0; border-top: 1px solid color-mix(in srgb, CanvasText 25%, transparent); margin: 1.5em 0; }
                .task { list-style: none; margin-left: -1.4em; } .taskmark { display: inline-block; width: 1.4em; }
                @media (max-width: 560px) { body { padding: 25px 24px 40px; } }
              </style>
            </head>
            <body>\(body)</body>
            </html>
            """
    }

    public func fragment(source: String) -> String {
        blocks(parser.parse(source))
    }

    /// Rich HTML tailored to chat composers that discard heading elements and
    /// CSS margins. Headings become bold lines. Explicit blank lines appear
    /// only after the document title and before later section headings.
    public func chatFragment(source: String) -> String {
        let values = parser.parse(source)
        var elements: [String] = []
        for (index, block) in values.enumerated() {
            if index > 0,
               shouldAddChatSpacer(
                   before: block,
                   after: values[index - 1],
                   at: index
               )
            {
                elements.append("<div><br></div>")
            }
            elements.append(chatBlock(block))
        }
        let content = elements.joined(separator: "\n")
        return "<div data-markdown-preview-chat=\"true\">\(content)</div>"
    }

    private func shouldAddChatSpacer(
        before current: MarkdownBlock,
        after previous: MarkdownBlock,
        at index: Int
    ) -> Bool {
        if index == 1,
           case let .heading(level, _) = previous,
           level == 1
        {
            return true
        }
        if case .heading = current {
            return true
        }
        return false
    }

    private func blocks(_ values: [MarkdownBlock]) -> String {
        values.map { block in
            switch block {
            case let .heading(level, text):
                return "<h\(level)>\(inline(text))</h\(level)>"
            case let .paragraph(text):
                return "<p>\(inline(text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
            case let .unorderedList(items):
                return list(items, ordered: false)
            case let .orderedList(items):
                return list(items, ordered: true)
            case let .blockquote(children):
                return "<blockquote>\(blocks(children))</blockquote>"
            case let .code(language, text):
                let className = language.map { " class=\"language-\(attribute($0))\"" } ?? ""
                return "<pre><code\(className)>\(escape(text))</code></pre>"
            case .thematicBreak:
                return "<hr>"
            case let .table(headers, rows):
                let heading = headers.map { "<th>\(inline($0))</th>" }.joined()
                let body = rows.map { row in
                    "<tr>" + row.map { "<td>\(inline($0))</td>" }.joined() + "</tr>"
                }.joined()
                return "<table><thead><tr>\(heading)</tr></thead><tbody>\(body)</tbody></table>"
            }
        }.joined(separator: "\n")
    }

    private func chatBlock(_ block: MarkdownBlock) -> String {
        switch block {
        case let .heading(_, text):
            return "<div><strong>\(inline(text))</strong></div>"
        case let .paragraph(text):
            return "<div>\(inline(text).replacingOccurrences(of: "\n", with: "<br>"))</div>"
        case let .unorderedList(items):
            return list(items, ordered: false)
        case let .orderedList(items):
            return list(items, ordered: true)
        case let .blockquote(children):
            let content = children.map(chatBlock).joined(separator: "<br>")
            return "<blockquote>\(content)</blockquote>"
        case let .code(language, text):
            let className = language.map { " class=\"language-\(attribute($0))\"" } ?? ""
            return "<pre><code\(className)>\(escape(text))</code></pre>"
        case .thematicBreak:
            return "<div>────────────</div>"
        case let .table(headers, rows):
            let heading = headers.map { "<th>\(inline($0))</th>" }.joined()
            let body = rows.map { row in
                "<tr>" + row.map { "<td>\(inline($0))</td>" }.joined() + "</tr>"
            }.joined()
            return "<table><thead><tr>\(heading)</tr></thead><tbody>\(body)</tbody></table>"
        }
    }

    private func list(_ items: [MarkdownBlock.ListItem], ordered: Bool) -> String {
        let tag = ordered ? "ol" : "ul"
        let body = items.map { item in
            let taskClass = item.checkbox == nil ? "" : " class=\"task\""
            let marker = item.checkbox.map { "<span class=\"taskmark\">\($0 ? "☑︎" : "☐")</span>" } ?? ""
            return "<li\(taskClass)>\(marker)\(inline(item.text))</li>"
        }.joined()
        return "<\(tag)>\(body)</\(tag)>"
    }

    private func inline(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    result += escape(String(text[next]))
                    index = text.index(after: next)
                    continue
                }
            }

            if text[index] == "`", let end = text[text.index(after: index)...].firstIndex(of: "`") {
                result += "<code>\(escape(String(text[text.index(after: index)..<end])))</code>"
                index = text.index(after: end)
                continue
            }

            if text[index...].hasPrefix("!["),
               let labelEnd = text[index...].firstIndex(of: "]"),
               text.index(after: labelEnd) < text.endIndex,
               text[text.index(after: labelEnd)] == "(",
               let targetEnd = text[text.index(labelEnd, offsetBy: 2)...].firstIndex(of: ")")
            {
                let alt = String(text[text.index(index, offsetBy: 2)..<labelEnd])
                result += "<span aria-label=\"Image: \(attribute(alt))\">🖼 \(escape(alt))</span>"
                index = text.index(after: targetEnd)
                continue
            }

            if text[index] == "[",
               let labelEnd = text[index...].firstIndex(of: "]"),
               text.index(after: labelEnd) < text.endIndex,
               text[text.index(after: labelEnd)] == "(",
               let targetEnd = text[text.index(labelEnd, offsetBy: 2)...].firstIndex(of: ")")
            {
                let label = String(text[text.index(after: index)..<labelEnd])
                let target = String(text[text.index(labelEnd, offsetBy: 2)..<targetEnd])
                if safeLink(target) {
                    result += "<a href=\"\(attribute(target))\">\(inline(label))</a>"
                } else {
                    result += inline(label)
                }
                index = text.index(after: targetEnd)
                continue
            }

            let pairs: [(String, String, String)] = [
                ("**", "**", "strong"), ("__", "__", "strong"), ("~~", "~~", "del"),
                ("*", "*", "em"), ("_", "_", "em"),
            ]
            var matched = false
            for (opening, closing, tag) in pairs where text[index...].hasPrefix(opening) {
                let contentStart = text.index(index, offsetBy: opening.count)
                if let range = text.range(of: closing, range: contentStart..<text.endIndex), range.lowerBound > contentStart {
                    result += "<\(tag)>\(inline(String(text[contentStart..<range.lowerBound])))</\(tag)>"
                    index = range.upperBound
                    matched = true
                    break
                }
            }
            if matched { continue }

            result += escape(String(text[index]))
            index = text.index(after: index)
        }
        return result
    }

    private func safeLink(_ value: String) -> Bool {
        guard let components = URLComponents(string: value) else { return false }
        guard let scheme = components.scheme?.lowercased() else {
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("//")
        }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func attribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "'", with: "&#39;")
    }
}
