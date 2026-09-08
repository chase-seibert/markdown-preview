import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let markdownPathBarVisibilityDidChange = Notification.Name(
        "MarkdownPathBarVisibilityDidChange"
    )
}

@MainActor
final class PathBarController: NSObject, ObservableObject {
    static let shared = PathBarController()

    @Published private(set) var showsPathBar: Bool

    private let defaultsKey = "ShowPathBar"

    private override init() {
        let stored = UserDefaults.standard.object(forKey: defaultsKey) as? NSNumber
        showsPathBar = stored?.boolValue ?? false
        super.init()
    }

    @objc func toggle(_ sender: Any?) {
        setShowsPathBar(!showsPathBar)
    }

    func setShowsPathBar(_ showsPathBar: Bool) {
        guard showsPathBar != self.showsPathBar else { return }
        self.showsPathBar = showsPathBar
        UserDefaults.standard.set(showsPathBar, forKey: defaultsKey)
        NotificationCenter.default.post(
            name: .markdownPathBarVisibilityDidChange,
            object: self
        )
    }
}

@MainActor
private final class DocumentPathControl: NSPathControl {
    var onOpenPath: ((URL) -> Void)?
    var onCopyPath: ((URL) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let url = url(at: point) else {
            super.rightMouseDown(with: event)
            return
        }

        let menu = NSMenu()
        let openItem = menu.addItem(
            withTitle: "Open",
            action: #selector(openContextPath(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        let copyItem = menu.addItem(
            withTitle: "Copy Path",
            action: #selector(copyContextPath(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        contextURL = url
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private var contextURL: URL?

    @objc private func openContextPath(_ sender: Any?) {
        guard let contextURL else { return }
        onOpenPath?(contextURL)
    }

    @objc private func copyContextPath(_ sender: Any?) {
        guard let contextURL else { return }
        onCopyPath?(contextURL)
    }

    private func url(at point: NSPoint) -> URL? {
        guard let pathCell = cell as? NSPathCell else { return nil }
        return pathCell.pathComponentCells.first { componentCell in
            let rect = pathCell.rect(of: componentCell, withFrame: bounds, in: self)
            return rect.contains(point)
        }?.url
    }
}

@MainActor
final class DocumentPathBar: NSView {
    private let pathControl = DocumentPathControl()
    private let copyButton: NSButton
    private var pathBarHeightConstraint: NSLayoutConstraint!

    init(documentURL: URL?) {
        let copyImage = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy Full Path"
        )
        copyButton = NSButton(image: copyImage ?? NSImage(), target: nil, action: nil)
        super.init(frame: .zero)

        pathBarHeightConstraint = heightAnchor.constraint(equalToConstant: 30)
        NSLayoutConstraint.activate([pathBarHeightConstraint])

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        pathControl.pathStyle = .standard
        pathControl.backgroundColor = .clear
        pathControl.isEditable = false
        pathControl.url = documentURL
        pathControl.toolTip = documentURL?.standardizedFileURL.path
        pathControl.target = self
        pathControl.action = #selector(openPathComponent(_:))
        pathControl.onOpenPath = { url in
            Self.openInFinder(url)
        }
        pathControl.onCopyPath = { url in
            Self.copyPath(url)
        }
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pathControl)

        copyButton.setButtonType(.momentaryPushIn)
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.toolTip = "Copy Full Path"
        copyButton.target = self
        copyButton.action = #selector(copyFullPath(_:))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),

            pathControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pathControl.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            pathControl.topAnchor.constraint(equalTo: separator.bottomAnchor),
            pathControl.bottomAnchor.constraint(equalTo: bottomAnchor),

            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            copyButton.centerYAnchor.constraint(equalTo: pathControl.centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pathBarVisibilityDidChange(_:)),
            name: .markdownPathBarVisibilityDidChange,
            object: nil
        )
        updateVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateDocumentURL(_ documentURL: URL?) {
        pathControl.url = documentURL
        pathControl.toolTip = documentURL?.standardizedFileURL.path
    }

    @objc private func pathBarVisibilityDidChange(_ notification: Notification) {
        updateVisibility()
    }

    @objc private func openPathComponent(_ sender: NSPathControl) {
        guard let url = sender.clickedPathItem?.url,
              Self.isDirectory(url) else { return }
        Self.openInFinder(url)
    }

    @objc private func copyFullPath(_ sender: Any?) {
        guard let path = pathControl.url?.standardizedFileURL.path else { return }
        Self.copyPath(URL(fileURLWithPath: path))
    }

    private static func copyPath(_ url: URL) {
        let path = url.standardizedFileURL.path
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true
    }

    private static func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
    }

    private func updateVisibility() {
        let isVisible = PathBarController.shared.showsPathBar
        isHidden = !isVisible
    }
}
