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

    func testTaskListEditorTogglesOnlyTheSelectedSourceMarker() throws {
        let source = "- [ ] First\r\n1. [X] Second\r\n> - [x] Quoted\r\n```\r\n- [ ] Example\r\n```\r\n"

        XCTAssertEqual(
            try XCTUnwrap(MarkdownTaskListEditor.togglingTask(at: 0, in: source)),
            "- [x] First\r\n1. [X] Second\r\n> - [x] Quoted\r\n```\r\n- [ ] Example\r\n```\r\n"
        )
        XCTAssertEqual(
            try XCTUnwrap(MarkdownTaskListEditor.togglingTask(at: 1, in: source)),
            "- [ ] First\r\n1. [ ] Second\r\n> - [x] Quoted\r\n```\r\n- [ ] Example\r\n```\r\n"
        )
        XCTAssertEqual(
            try XCTUnwrap(MarkdownTaskListEditor.togglingTask(at: 2, in: source)),
            "- [ ] First\r\n1. [X] Second\r\n> - [ ] Quoted\r\n```\r\n- [ ] Example\r\n```\r\n"
        )
        XCTAssertNil(MarkdownTaskListEditor.togglingTask(at: 3, in: source))
        XCTAssertNil(MarkdownTaskListEditor.togglingTask(at: -1, in: source))
    }

    @MainActor
    func testRenderedTaskMarkersCarrySourceIndices() {
        let rendered = MarkdownAttributedRenderer().render(
            "- [ ] First\n- Ordinary\n> 1. [x] Second"
        )
        var indices: [Int] = []
        var markers: [String] = []
        var states: [Bool] = []
        rendered.enumerateAttribute(
            .markdownTaskIndex,
            in: NSRange(location: 0, length: rendered.length)
        ) { value, range, _ in
            guard let index = value as? Int else { return }
            indices.append(index)
            markers.append((rendered.string as NSString).substring(with: range))
            states.append(rendered.attribute(.markdownTaskChecked, at: range.location, effectiveRange: nil) as? Bool ?? false)
        }

        XCTAssertEqual(indices, [0, 1])
        XCTAssertEqual(markers, ["\u{FFFC}", "\u{FFFC}"])
        XCTAssertEqual(states, [false, true])
    }

    @MainActor
    func testCheckedAndUncheckedTaskTextUsesTheSameHorizontalPosition() {
        let rendered = MarkdownAttributedRenderer().render(
            "- [ ] First task\n- [x] Second task"
        )
        let storage = NSTextStorage(attributedString: rendered)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 1_000, height: 1_000))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let firstRange = (rendered.string as NSString).range(of: "First task")
        let secondRange = (rendered.string as NSString).range(of: "Second task")
        let firstGlyphRange = layoutManager.glyphRange(
            forCharacterRange: firstRange,
            actualCharacterRange: nil
        )
        let secondGlyphRange = layoutManager.glyphRange(
            forCharacterRange: secondRange,
            actualCharacterRange: nil
        )
        let firstRect = layoutManager.boundingRect(forGlyphRange: firstGlyphRange, in: textContainer)
        let secondRect = layoutManager.boundingRect(forGlyphRange: secondGlyphRange, in: textContainer)

        XCTAssertEqual(firstRect.minX, secondRect.minX, accuracy: 0.01)
    }

    @MainActor
    func testCheckedAndUncheckedTaskRowsUseTheSameLineHeight() {
        func lineHeight(for source: String, text: String) -> CGFloat {
            let rendered = MarkdownAttributedRenderer().render(source)
            let storage = NSTextStorage(attributedString: rendered)
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(size: NSSize(width: 1_000, height: 1_000))
            storage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(textContainer)
            layoutManager.ensureLayout(for: textContainer)
            let range = (rendered.string as NSString).range(of: text)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            return layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            ).height
        }

        XCTAssertEqual(
            lineHeight(for: "- [ ] First task", text: "First task"),
            lineHeight(for: "- [x] First task", text: "First task"),
            accuracy: 0.01
        )
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

    func testChatHTMLUsesBoldHeadingsAndConservativeSectionSpacing() {
        let html = MarkdownHTMLRenderer().chatFragment(
            source: """
                # Title

                An **intro** paragraph.

                ## Section

                - First
                - Second

                Continuation paragraph.

                ```text
                code
                ```

                ## Next

                Final paragraph.
                """
        )

        XCTAssertTrue(html.contains("<div><strong>Title</strong></div>"))
        XCTAssertTrue(html.contains("<div><strong>Section</strong></div>"))
        XCTAssertTrue(html.contains("<div><strong>Next</strong></div>"))
        XCTAssertTrue(html.contains("<div>An <strong>intro</strong> paragraph.</div>"))
        XCTAssertTrue(html.contains("<ul><li>First</li><li>Second</li></ul>"))
        XCTAssertEqual(html.components(separatedBy: "<div><br></div>").count - 1, 3)
        XCTAssertTrue(html.contains("<strong>Title</strong></div>\n<div><br></div>\n<div>An"))
        XCTAssertTrue(html.contains("paragraph.</div>\n<div><br></div>\n<div><strong>Section"))
        XCTAssertTrue(html.contains("<strong>Section</strong></div>\n<ul>"))
        XCTAssertTrue(html.contains("</ul>\n<div>Continuation paragraph.</div>\n<pre>"))
        XCTAssertTrue(html.contains("</pre>\n<div><br></div>\n<div><strong>Next"))
        XCTAssertTrue(html.contains("<strong>Next</strong></div>\n<div>Final paragraph.</div>"))
        XCTAssertFalse(html.contains("<h1>"))
        XCTAssertFalse(html.contains("<h2>"))
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
    func testRenderedPlainTextPreservesTaskMarkerStates() {
        let text = MarkdownAttributedRenderer().plainText("- [ ] First\n- [x] Second")
        XCTAssertTrue(text.contains("☐\tFirst"))
        XCTAssertTrue(text.contains("☑︎\tSecond"))
        XCTAssertFalse(text.contains("\u{FFFC}"))
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

    func testMaximumReadingWidthScalesWithFontSize() {
        XCTAssertEqual(MarkdownReadingLayout.maximumTextContainerWidth(fontScale: 1), 900)
        XCTAssertEqual(MarkdownReadingLayout.maximumTextContainerWidth(fontScale: 0.8), 720)
        XCTAssertEqual(MarkdownReadingLayout.maximumTextContainerWidth(fontScale: 1.4), 1_260)
        XCTAssertEqual(
            MarkdownReadingLayout.maximumTextContainerWidth(fontScale: 100),
            900 * MarkdownFontScalePreference.maximumScale
        )
    }

    func testLocalMarkdownLinksResolveRelativeToPreviewedDocument() throws {
        let documentURL = URL(fileURLWithPath: "/tmp/project/docs/marketing.md")

        let sibling = try XCTUnwrap(URL(string: "social.md"))
        XCTAssertEqual(
            MarkdownLinkResolver.localMarkdownURL(for: sibling, relativeTo: documentURL),
            URL(fileURLWithPath: "/tmp/project/docs/social.md")
        )

        let nested = try XCTUnwrap(URL(string: "social-media-manager/README.md#setup"))
        XCTAssertEqual(
            MarkdownLinkResolver.localMarkdownURL(for: nested, relativeTo: documentURL),
            URL(fileURLWithPath: "/tmp/project/docs/social-media-manager/README.md")
        )

        XCTAssertNil(
            MarkdownLinkResolver.localMarkdownURL(
                for: try XCTUnwrap(URL(string: "https://example.com/guide.md")),
                relativeTo: documentURL
            )
        )
        XCTAssertNil(
            MarkdownLinkResolver.localMarkdownURL(
                for: try XCTUnwrap(URL(string: "../notes.txt")),
                relativeTo: documentURL
            )
        )

        let destinationURL = URL(fileURLWithPath: "/tmp/project/docs/social.md")
        let navigationURL = try XCTUnwrap(
            MarkdownLinkResolver.navigationURL(for: destinationURL, relativeTo: documentURL)
        )
        XCTAssertEqual(
            MarkdownLinkResolver.navigationRequest(from: navigationURL),
            MarkdownLinkNavigationRequest(
                fileURL: destinationURL,
                accessDirectoryURL: URL(fileURLWithPath: "/tmp/project/docs", isDirectory: true)
            )
        )
        XCTAssertNil(
            MarkdownLinkResolver.navigationRequest(
                from: try XCTUnwrap(URL(string: "markdown-preview://open?url=https://example.com/a.md"))
            )
        )
    }

    func testFontScalePreferencePersistsAndClampsValues() throws {
        let suiteName = "com.cseibert.MarkdownPreviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(MarkdownFontScalePreference.storedValue(in: defaults))

        MarkdownFontScalePreference.save(1.2, in: defaults)
        XCTAssertEqual(MarkdownFontScalePreference.storedValue(in: defaults), 1.2)

        defaults.set(100, forKey: MarkdownFontScalePreference.defaultsKey)
        XCTAssertEqual(
            MarkdownFontScalePreference.storedValue(in: defaults),
            MarkdownFontScalePreference.maximumScale
        )
        XCTAssertEqual(
            MarkdownFontScalePreference.clamped(.nan),
            MarkdownFontScalePreference.defaultScale
        )

        let domain = "\(suiteName).shared"
        defer {
            CFPreferencesSetAppValue(
                MarkdownFontScalePreference.defaultsKey as CFString,
                nil,
                domain as CFString
            )
            CFPreferencesAppSynchronize(domain as CFString)
        }
        XCTAssertTrue(MarkdownFontScalePreference.save(1.4, inDomain: domain))
        XCTAssertEqual(MarkdownFontScalePreference.storedValue(inDomain: domain), 1.4)
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
