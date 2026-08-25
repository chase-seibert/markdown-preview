# Design

Markdown Preview uses a standard macOS document window. The title bar shows the
file name and proxy icon; the body is a single native, read-only text view with
normal selection, link interaction, scrolling, Find, and Services behavior.

There is intentionally no sidebar, project switcher, status bar, or custom
window chrome. Files always use separate windows: automatic window tabbing is
disabled, and document windows reject tabbing. File operations live in the File
menu, copy variants in the Edit menu, and reading size in the View menu. A
compact Settings window provides persistent appearance and text-size controls.
It also lets users hide the application icon from the Dock and app switcher;
opening a Markdown file brings the app forward when the icon is hidden.

Document colors are semantic system colors. The appearance setting can follow
the system or force Light or Dark across the application. Headings, body text,
lists, quotes, links, and code all scale from one clamped setting, preserving
their relative hierarchy. The centered reading column's maximum width scales by
the same factor, keeping roughly the same number of characters on each line at
every reading size. The Quick Look extension uses the same persisted text scale,
responsive reading width, and native attributed-text renderer. Its view is
recreated for each preview, so a cached preview cannot preserve an obsolete
scale.

Relative links to other Markdown files resolve from the displayed document's
folder. Activating one opens the destination in Markdown Preview, whether the
link starts in a document window or a Finder Quick Look preview. Web links keep
their standard system behavior. The first local navigation into a folder asks
the reader to allow that folder; subsequent links covered by the saved access
open directly.

Standard Copy preserves a selected range. With no selection, Command-C copies
the complete rendered document as rich HTML/RTF plus a plain-text fallback.
Copy for Chat uses a deliberately simpler HTML dialect for Slack and similar
editors: headings are bold lines rather than heading tags. It adds an explicit
blank line after the document title and before later headings, while keeping
paragraphs, lists, code blocks, and section contents compact.
