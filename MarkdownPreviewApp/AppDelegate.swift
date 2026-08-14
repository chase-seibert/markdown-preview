import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private static var retainedDelegate: AppDelegate?
    private var settingsController: SettingsWindowController?
    private var receivedOpenRequest = false
    private let logger = Logger(subsystem: "com.cseibert.MarkdownPreview", category: "DocumentLifecycle")

    static func main() {
        let delegate = AppDelegate()
        retainedDelegate = delegate
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        AppearanceController.shared.apply()
        NSApp.mainMenu = makeMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application finished launching")
        let commandLineURLs = CommandLine.arguments.dropFirst().compactMap { argument -> URL? in
            guard !argument.hasPrefix("-") else { return nil }
            let url = URL(fileURLWithPath: argument)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if !commandLineURLs.isEmpty {
            receivedOpenRequest = true
            open(commandLineURLs)
        }
        // Finder's open-document event arrives just after didFinishLaunching.
        // Give it priority so a file launch never gets covered by an open panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard !self.receivedOpenRequest, NSDocumentController.shared.documents.isEmpty else { return }
            self.openDocument(nil)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("Received URL open request for \(urls.count, privacy: .public) file(s)")
        receivedOpenRequest = true
        open(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        logger.info("Received open request for \(filenames.count, privacy: .public) file(s)")
        receivedOpenRequest = true
        open(filenames.map(URL.init(fileURLWithPath:))) { openedAny in
            sender.reply(toOpenOrPrint: openedAny ? .success : .failure)
        }
    }

    private func open(_ urls: [URL], completion: ((Bool) -> Void)? = nil) {
        let controller = NSDocumentController.shared
        var openedAny = false
        for url in urls {
            if let existing = controller.documents.first(where: {
                $0.fileURL?.standardizedFileURL == url.standardizedFileURL
            }) {
                existing.showWindows()
                openedAny = true
                continue
            }

            do {
                // Construct the concrete viewer directly. This avoids relying on
                // Launch Services' dynamic UTI-to-class lookup for Markdown,
                // which is not a system-declared type on every macOS release.
                let document = try MarkdownDocument(
                    contentsOf: url,
                    ofType: "net.daringfireball.markdown"
                )
                controller.addDocument(document)
                document.makeWindowControllers()
                document.showWindows()
                controller.noteNewRecentDocumentURL(url)
                openedAny = true
            } catch {
                logger.error("Could not open \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
                NSAlert(error: error).runModal()
            }
        }
        completion?(openedAny)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = markdownTypes + [.plainText]
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                fontScale: .shared,
                appearance: .shared
            )
        }
        settingsController?.showWindow(sender)
        settingsController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func copySource(_ sender: Any?) {
        guard let document = currentDocument else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(document.source, forType: .string)
    }

    @objc func copy(_ sender: Any?) {
        guard let document = currentDocument else { return }
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.selectedRange().length > 0
        {
            textView.copy(sender)
            return
        }
        writeRichText(document)
    }

    @objc func copyPlainText(_ sender: Any?) {
        guard let document = currentDocument else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(document.renderedText.string, forType: .string)
    }

    @objc func copyRichText(_ sender: Any?) {
        guard let document = currentDocument else { return }
        writeRichText(document)
    }

    @objc func copyForChat(_ sender: Any?) {
        guard let document = currentDocument else { return }
        let pasteboard = NSPasteboard.general
        let html = MarkdownHTMLRenderer().chatFragment(source: document.source)
        pasteboard.clearContents()
        pasteboard.setString(document.renderedText.string, forType: .string)
        pasteboard.setData(Data(html.utf8), forType: .html)
    }

    private func writeRichText(_ document: MarkdownDocument) {
        let attributed = document.renderedText
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(attributed.string, forType: .string)
        if let rtf = try? MarkdownExporter().rtf(from: attributed) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        let html = MarkdownHTMLRenderer().fragment(source: document.source)
        pasteboard.setData(Data(html.utf8), forType: .html)
    }

    @objc func exportMarkdown(_ sender: Any?) { export(.markdown) }
    @objc func exportPlainText(_ sender: Any?) { export(.plainText) }
    @objc func exportRichText(_ sender: Any?) { export(.richText) }
    @objc func exportHTML(_ sender: Any?) { export(.html) }
    @objc func exportPDF(_ sender: Any?) { export(.pdf) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let actionsRequiringDocument: [Selector] = [
            #selector(copy(_:)), #selector(copySource(_:)), #selector(copyPlainText(_:)),
            #selector(copyRichText(_:)), #selector(copyForChat(_:)),
            #selector(exportMarkdown(_:)), #selector(exportPlainText(_:)), #selector(exportRichText(_:)),
            #selector(exportHTML(_:)), #selector(exportPDF(_:)),
        ]
        if let action = menuItem.action, actionsRequiringDocument.contains(action) {
            return currentDocument != nil
        }
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier == NSUserInterfaceItemIdentifier("OpenRecentMenu") else { return }
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for url in urls {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
                item.representedObject = url
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "").target = self
        }
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open([url])
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    private var currentDocument: MarkdownDocument? {
        let controller = NSDocumentController.shared
        return (controller.currentDocument as? MarkdownDocument)
            ?? (NSApp.keyWindow?.windowController?.document as? MarkdownDocument)
            ?? (controller.documents.last as? MarkdownDocument)
    }

    private var markdownTypes: [UTType] {
        ["md", "markdown", "mdown", "mkd"].compactMap { UTType(filenameExtension: $0) }
    }

    private enum ExportFormat {
        case markdown, plainText, richText, html, pdf

        var extensionName: String {
            switch self {
            case .markdown: "md"
            case .plainText: "txt"
            case .richText: "rtf"
            case .html: "html"
            case .pdf: "pdf"
            }
        }

        var contentType: UTType {
            switch self {
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            case .plainText: .plainText
            case .richText: .rtf
            case .html: .html
            case .pdf: .pdf
            }
        }
    }

    private func export(_ format: ExportFormat) {
        guard let document = currentDocument, let window = document.windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        let stem = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(stem).\(format.extensionName)"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data: Data
                switch format {
                case .markdown:
                    data = Data(document.source.utf8)
                case .plainText:
                    data = Data(document.renderedText.string.utf8)
                case .richText:
                    data = try MarkdownExporter().rtf(from: document.renderedText)
                case .html:
                    let html = MarkdownHTMLRenderer().document(
                        source: document.source,
                        fontScale: Double(FontScaleController.shared.scale),
                        title: document.displayName
                    )
                    data = Data(html.utf8)
                case .pdf:
                    data = try MarkdownExporter().pdf(from: document.printableText, title: document.displayName)
                }
                try data.write(to: url, options: .atomic)
            } catch {
                window.presentError(error)
            }
        }
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Markdown Preview")
        appMenu.addItem(withTitle: "About Markdown Preview", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = NSMenu(title: "Services")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Markdown Preview", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Markdown Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Markdown Preview", action: nil, keyEquivalent: "").submenu = appMenu

        let file = NSMenu(title: "File")
        let open = file.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        open.target = self
        open.image = nil
        let recent = NSMenu(title: "Open Recent")
        recent.identifier = NSUserInterfaceItemIdentifier("OpenRecentMenu")
        recent.delegate = self
        file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recent
        file.addItem(.separator())
        let export = NSMenu(title: "Export")
        addItem("Markdown…", action: #selector(exportMarkdown(_:)), to: export)
        addItem("Plain Text…", action: #selector(exportPlainText(_:)), to: export)
        addItem("Rich Text…", action: #selector(exportRichText(_:)), to: export)
        addItem("HTML…", action: #selector(exportHTML(_:)), to: export)
        addItem("PDF…", action: #selector(exportPDF(_:)), to: export)
        file.addItem(withTitle: "Export", action: nil, keyEquivalent: "").submenu = export
        file.addItem(.separator())
        let close = file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.image = nil
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = file

        let edit = NSMenu(title: "Edit")
        let copy = edit.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        copy.target = self
        edit.addItem(.separator())
        addItem("Copy Source Markdown", action: #selector(copySource(_:)), key: "c", modifiers: [.command, .shift], to: edit)
        addItem("Copy All as Plain Text", action: #selector(copyPlainText(_:)), key: "c", modifiers: [.command, .option], to: edit)
        addItem("Copy All as Rich Text", action: #selector(copyRichText(_:)), to: edit)
        addItem("Copy for Chat", action: #selector(copyForChat(_:)), key: "c", modifiers: [.command, .control], to: edit)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let find = NSMenu(title: "Find")
        let findItem = find.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        findItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        let next = find.addItem(withTitle: "Find Next", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g")
        next.tag = Int(NSFindPanelAction.next.rawValue)
        let previous = find.addItem(withTitle: "Find Previous", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g")
        previous.keyEquivalentModifierMask = [.command, .shift]
        previous.tag = Int(NSFindPanelAction.previous.rawValue)
        edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let view = NSMenu(title: "View")
        addItem("Increase Text Size", action: #selector(FontScaleController.increaseFontSize(_:)), key: "+", modifiers: [.command], target: FontScaleController.shared, to: view)
        addItem("Decrease Text Size", action: #selector(FontScaleController.decreaseFontSize(_:)), key: "-", modifiers: [.command], target: FontScaleController.shared, to: view)
        addItem("Actual Text Size", action: #selector(FontScaleController.resetFontSize(_:)), key: "0", modifiers: [.command], target: FontScaleController.shared, to: view)
        view.addItem(.separator())
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = view

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        let helpItem = help.addItem(withTitle: "Markdown Preview Help", action: #selector(showHelp(_:)), keyEquivalent: "?")
        helpItem.target = self
        main.addItem(withTitle: "Help", action: nil, keyEquivalent: "").submenu = help
        NSApp.helpMenu = help

        return main
    }

    @objc private func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Markdown Preview"
        alert.informativeText = "Open a Markdown file from Finder or File > Open. Use Command-+, Command--, and Command-0 to change reading size. Export and copy formats are available from the File and Edit menus."
        alert.runModal()
    }

    private func addItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil,
        to menu: NSMenu
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
    }
}
