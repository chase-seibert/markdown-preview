import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    public struct ListItem: Equatable, Sendable {
        public let depth: Int
        public let ordinal: Int?
        public let checkbox: Bool?
        public let text: String

        public init(depth: Int, ordinal: Int? = nil, checkbox: Bool? = nil, text: String) {
            self.depth = depth
            self.ordinal = ordinal
            self.checkbox = checkbox
            self.text = text
        }
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([ListItem])
    case orderedList([ListItem])
    case blockquote([MarkdownBlock])
    case code(language: String?, text: String)
    case thematicBreak
    case table(headers: [String], rows: [[String]])
}

public struct MarkdownParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.enumerated().map { position, line in
                if position > 0, paragraph[position - 1].hasSuffix("  ") {
                    return "\n" + line
                }
                return position == 0 ? line : " " + line
            }.joined()
            blocks.append(.paragraph(text.trimmingCharacters(in: .whitespaces)))
            paragraph.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = codeFence(in: line) {
                flushParagraph()
                let language = fence.info.isEmpty ? nil : fence.info
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !isClosingFence(lines[index], marker: fence.marker) {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: language, text: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(in: line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isThematicBreak(line) {
                flushParagraph()
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var value = String(candidate.dropFirst())
                    if value.hasPrefix(" ") { value.removeFirst() }
                    quoted.append(value)
                    index += 1
                }
                blocks.append(.blockquote(parse(quoted.joined(separator: "\n"))))
                continue
            }

            if let item = listItem(in: line) {
                flushParagraph()
                var items = [item]
                let ordered = item.ordinal != nil
                index += 1
                while index < lines.count, let next = listItem(in: lines[index]), (next.ordinal != nil) == ordered {
                    items.append(next)
                    index += 1
                }
                blocks.append(ordered ? .orderedList(items) : .unorderedList(items))
                continue
            }

            if index + 1 < lines.count,
               isTableRow(line),
               isTableDivider(lines[index + 1])
            {
                flushParagraph()
                let headers = tableCells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, isTableRow(lines[index]), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[index]))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private func heading(in line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let count = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count) else { return nil }
        let remainder = trimmed.dropFirst(count)
        guard remainder.first?.isWhitespace == true else { return nil }
        return (count, remainder.trimmingCharacters(in: .whitespaces))
    }

    private func codeFence(in line: String) -> (marker: String, info: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }
        let character = trimmed.first!
        let count = trimmed.prefix(while: { $0 == character }).count
        guard count >= 3 else { return nil }
        let marker = String(repeating: character, count: count)
        let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        return (marker, info)
    }

    private func isClosingFence(_ line: String, marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(marker)
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let value = line.filter { !$0.isWhitespace }
        guard value.count >= 3, let first = value.first, first == "-" || first == "*" || first == "_" else {
            return false
        }
        return value.allSatisfy { $0 == first }
    }

    private func listItem(in line: String) -> MarkdownBlock.ListItem? {
        let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { partial, character in
            partial + (character == "\t" ? 4 : 1)
        }
        let depth = leadingSpaces / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var ordinal: Int?
        var body: String

        if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first?.isWhitespace == true {
            body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else {
            let digits = trimmed.prefix(while: { $0.isNumber })
            guard !digits.isEmpty,
                  let separator = trimmed.dropFirst(digits.count).first,
                  separator == "." || separator == ")"
            else { return nil }
            let remainder = trimmed.dropFirst(digits.count + 1)
            guard remainder.first?.isWhitespace == true else { return nil }
            ordinal = Int(digits)
            body = remainder.trimmingCharacters(in: .whitespaces)
        }

        var checkbox: Bool?
        if body.count >= 3, body.first == "[", body.dropFirst(2).first == "]" {
            let state = body[body.index(after: body.startIndex)]
            if state == " " || state == "x" || state == "X" {
                checkbox = state != " "
                body = String(body.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        return .init(depth: depth, ordinal: ordinal, checkbox: checkbox, text: body)
    }

    private func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private func isTableDivider(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            return value.count >= 3 && value.allSatisfy { $0 == "-" }
        }
    }

    private func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}

