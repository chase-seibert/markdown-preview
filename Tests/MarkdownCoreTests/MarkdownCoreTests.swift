import AppKit
import XCTest
@testable import MarkdownCore

final class MarkdownCoreTests: XCTestCase {
    func testParserRecognizesCommonBlocks() {
        let source = """
            # Heading

            A **bold** paragraph.

            - [x] Done
            - Pending

            > Quoted

            ```swift
            let value = 42
            ```

            | Name | Value |
            | --- | --- |
            | One | Two |
            """

        let blocks = MarkdownParser().parse(source)
        XCTAssertTrue(blocks.contains(.heading(level: 1, text: "Heading")))
        XCTAssertTrue(blocks.contains(.code(language: "swift", text: "let value = 42")))
        XCTAssertTrue(blocks.contains(.table(headers: ["Name", "Value"], rows: [["One", "Two"]])))
    }

    func testHTMLIsSemanticAndEscapesRawHTML() {
        let html = MarkdownHTMLRenderer().document(
            source: "# Hello\n\n<script>alert(1)</script> **world**"
        )
        XCTAssertTrue(html.contains("<h1>Hello</h1>"))
        XCTAssertTrue(html.contains("<strong>world</strong>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("color-scheme: light dark"))
    }

    @MainActor
    func testRenderedPlainTextRemovesMarkdownSyntax() {
        let text = MarkdownAttributedRenderer().plainText("# Heading\n\nThis is **bold**.\n\n- Item")
        XCTAssertTrue(text.contains("Heading"))
        XCTAssertTrue(text.contains("This is bold."))
        XCTAssertTrue(text.contains("•  Item"))
        XCTAssertFalse(text.contains("**"))
        XCTAssertFalse(text.contains("# Heading"))
    }

    @MainActor
    func testFirstFontScaleChangeCoversEveryCharacter() {
        let source = "# Heading\n\nBody with `code`.\n\n- List item\n\n> Quote"
        let small = MarkdownAttributedRenderer().render(source, options: .init(fontScale: 0.8))
        let large = MarkdownAttributedRenderer().render(source, options: .init(fontScale: 1.4))

        assertEveryCharacterHasFont(small)
        assertEveryCharacterHasFont(large)

        let bodyRange = (large.string as NSString).range(of: "Body")
        let smallBodyRange = (small.string as NSString).range(of: "Body")
        guard let smallFont = small.attribute(.font, at: smallBodyRange.location, effectiveRange: nil) as? NSFont,
              let largeFont = large.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont
        else {
            return XCTFail("Body text should always have an explicit font")
        }
        XCTAssertEqual(smallFont.pointSize, 13.6, accuracy: 0.01)
        XCTAssertEqual(largeFont.pointSize, 23.8, accuracy: 0.01)
    }

    func testFontScaleIsClampedAndRejectsNonFiniteValues() {
        XCTAssertEqual(MarkdownRenderOptions(fontScale: -10).fontScale, MarkdownRenderOptions.minimumScale)
        XCTAssertEqual(MarkdownRenderOptions(fontScale: 100).fontScale, MarkdownRenderOptions.maximumScale)
        XCTAssertEqual(MarkdownRenderOptions(fontScale: .nan).fontScale, MarkdownRenderOptions.defaultScale)
    }

    @MainActor
    func testRichTextAndPDFExportsProduceData() throws {
        let rendered = MarkdownAttributedRenderer().render("# Export\n\nA **rich** document.", options: .init(palette: .print))
        XCTAssertGreaterThan(try MarkdownExporter().rtf(from: rendered).count, 100)
        XCTAssertGreaterThan(try MarkdownExporter().pdf(from: rendered, title: "Export").count, 100)
    }

    @MainActor
    private func assertEveryCharacterHasFont(_ value: NSAttributedString) {
        var covered = 0
        value.enumerateAttribute(.font, in: NSRange(location: 0, length: value.length)) { attribute, range, _ in
            XCTAssertNotNil(attribute as? NSFont)
            covered += range.length
        }
        XCTAssertEqual(covered, value.length)
    }
}
