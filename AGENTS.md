# Repository Guide

Also load the user-level instructions at `/Users/cseibert/.codex/AGENTS.md`.

## Repository map

- `MarkdownPreviewApp/`: AppKit document viewer and app commands.
- `MarkdownPreviewQuickLook/`: Finder Quick Look preview extension.
- `MarkdownCore/`: shared Markdown parsing, rendering, and export code.
- `Tests/MarkdownCoreTests/`: Swift Package unit tests for shared behavior.
- `Resources/`: app assets and metadata.
- `docs/`: product, design, architecture, and installation notes.
- `MarkdownPreview.xcodeproj/`: Xcode project for the app and extension.

## Commands

Prefer the common commands exposed as Makefile targets. Add new repeatable
workflows to the Makefile instead of documenting one-off shell commands.

- `make setup`: resolve Swift package metadata.
- `make format`: format Swift sources with the installed Swift toolchain.
- `make lint`: compile-check the package and validate project metadata.
- `make test`: run unit tests.
- `make build`: build the app and embedded Quick Look extension.
- `make run`: build and launch the app.
- `make install`: install the app in the user's Applications folder.
- `make clean`: remove local build outputs.

## Documentation

- `docs/product-requirements.md`
- `docs/design.md`
- `docs/architecture.md`
- `docs/setup-install.md`
- `docs/initial-brainstorm.md`

