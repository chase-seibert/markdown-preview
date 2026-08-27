# Markdown Preview

A small, native macOS document viewer for Markdown. Each file opens in its own window, with no project or folder model.

Markdown *Preview* showing a rendered *README*

# Highlights

- Opens .md, .markdown, .mdown, and .mkd files from Finder's \*\*Open

With\*\* menu.

- Includes a Quick Look preview extension for Finder's Spacebar preview.
- Automatically refreshes open previews when the source file changes on disk.
- Native selectable rendering with persistent System, Light, and Dark modes.
- Separate, non-tabbed windows for every open file.
- Safe, persistent font scaling with **Command-+**, **Command--**, and

**Command-0**.

- Copies source Markdown, rendered plain text, or rich HTML/RTF; Command-C

copies the full rich document when there is no selection.

- **Copy for Chat** (Control-Command-C) produces Slack-friendly rich text

with bold headings, space after the title, and space before later headings.

- Lightweight WYSIWYG editing directly in the preview; changes save immediately

and support native undo/redo.

- Exports Markdown, plain text, rich text, HTML, and PDF.

## Build and run

Requires Xcode 26 or later.

```sh
make test
make run
```

For Finder integration and Quick Look, install a built copy into Applications:

```sh
make install
```

See [docs/setup-install.md](docs/setup-install.md) for registration and default application instructions.