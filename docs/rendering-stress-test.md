# Markdown Rendering Stress  Test

This document exercises common Markdown structures, dense layouts, long content, and combinations that tend to expose rendering problems.

## Inline formatting

Plain text, **bold text**, *italic text*, ***bold italic text***, strikethrough, inline code, and a [local documentation link](design.md).

Formatting next to punctuation: (**bold**), “*italic*,” code, and **bold with an **[embedded link](architecture.md).

Escaped characters should remain literal: \*not italic\*, # not a heading, and \[not a link\].

Unicode should remain aligned: café, naïve, 日本語, مرحبا, 👩🏽‍💻, ✅, and →.

## Headings and spacing

### Third-level heading

Body text immediately after an H3 heading.

#### Fourth-level heading

Body text immediately after an H4 heading.

##### Fifth-level heading

###### Sixth-level heading

Text after adjacent H5 and H6 headings.

---

## Lists

- First bullet with **bold** and *italic* text
- Second bullet with a long sentence intended to wrap onto another visual line when the window is narrow enough to test hanging indentation and alignment beneath the first line of content
  - Nested bullet at depth two
    - Nested bullet at depth three
  - Another depth-two bullet after depth three
- Final top-level bullet
1. First numbered item
2. Second numbered item with enough text to wrap and verify that continuation lines align with the item content rather than with the number marker
  1. Nested numbered item
  2. Another nested numbered item
3. Final numbered item

Mixed nesting:

- Bullet parent
  1. Numbered child
  2. Numbered child with nested bullets
    - Deep bullet one
    - Deep bullet two
- Second bullet parent

## Tasks

- [ ] Unchecked task
- [x] Checked task
- [x] Uppercase checked task from source
- [ ] A long unchecked task that should wrap cleanly without colliding with the checkbox or aligning continuation text beneath the checkbox itself
  - [ ] Nested unchecked task
  - [x] Nested checked task
- Regular bullet after nested tasks

## Block quotes

> A single-line quotation.

> A multi-line quotation with **bold text**, *italic text*, and enough content to wrap onto another visual line so the quote indentation and continuation alignment can be inspected.

> A second paragraph in the same quote.

> - A bullet inside a quote
> - Another quoted bullet

> Outer quote

> Nested quote

> > Third-level quote

## Code

Inline code in a sentence should use compact padding: let answer = 42 without changing the paragraph line height dramatically.

```swift
struct Example {
    let title: String
    let values: [Int]

    func total() -> Int {
        values.reduce(0, +)
    }
}
```

Long code line:

```text
https://example.com/a/very/long/path/that/intentionally/continues/far/beyond/a/comfortable/reading/width/to/test/wrapping/or/clipping/behavior
```

## Tables

| Feature | Status | Owner | Notes |
| --- | --- | --- | --- |
| Text editing | Ready | Alex | Short value |
| Tables | Preview only | Priya | This is a longer note that should determine a sensible column width without overlapping adjacent cells |
| Checklists | Interactive | Morgan | **Bold note** and inline code |
| Unicode | Testing | 李雷 | café, 日本語, and 👩🏽‍💻 |

Narrow-value table:

| A | B | C |
| --- | --- | --- |
| 1 | 2 | 3 |
| 10 | 20 | 30 |

## Links and separators

[https://example.com](https://example.com) and [test@example.com](mailto:test@example.com)

Text before a separator.

---

Text after a separator.

## Final paragraph

The final line has no special structure, making it useful for checking bottom spacing and caret placement.