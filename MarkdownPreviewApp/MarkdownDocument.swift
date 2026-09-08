import AppKit
import Darwin
import Foundation

@MainActor
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    enum EditWriteResult {
        case saved
        case conflict
        case failed(Error)
    }

    // NSDocument's read/write overrides are imported as nonisolated in Swift 6.
    // AppKit serializes document loading before window creation, so this storage
    // is safe to bridge into the otherwise main-actor document object.
    nonisolated(unsafe) private(set) var source = ""
    private var lastLoadedFileSignature: FileSignature?
    private var pendingSelfWrite: SelfWriteExpectation?
    private var externalReloadTask: Task<Void, Never>?
    private var fileWatcher: MarkdownFileWatcher?
    private var pathBars: [DocumentPathBar] = []
    private var isPresentingConflict = false

    override class var autosavesInPlace: Bool { false }
    override var isDocumentEdited: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        source = try Self.decodedSource(from: data).value
    }

    private nonisolated static func decodedSource(
        from data: Data
    ) throws -> (value: String, encoding: String.Encoding) {
        if let utf8 = String(data: data, encoding: .utf8) {
            return (utf8, .utf8)
        }

        var converted: NSString?
        var lossy = ObjCBool(false)
        let rawEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: nil,
            convertedString: &converted,
            usedLossyConversion: &lossy
        )
        guard rawEncoding != 0, let converted
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return (converted as String, String.Encoding(rawValue: rawEncoding))
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(source.utf8)
    }

    override func makeWindowControllers() {
        let contentController = MarkdownViewController(
            source: source,
            documentURL: fileURL,
            onTaskToggle: { [weak self] taskIndex in
                self?.toggleTask(at: taskIndex)
            },
            onSourceChange: { [weak self] proposedSource in
                self?.writeEditedSource(proposedSource) ?? .failed(CocoaError(.fileNoSuchFile))
            },
            onEditConflict: { [weak self] proposedSource, controller in
                self?.presentEditConflict(proposedSource: proposedSource, controller: controller)
            }
        )
        let pathBar = DocumentPathBar(documentURL: fileURL)
        let containerController = NSViewController()
        let containerView = NSView()
        containerController.view = containerView
        containerController.addChild(contentController)
        let stackView = NSStackView(views: [contentController.view, pathBar])
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 0
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        pathBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            contentController.view.widthAnchor.constraint(equalTo: containerView.widthAnchor),
            pathBar.widthAnchor.constraint(equalTo: containerView.widthAnchor),
        ])
        pathBars.append(pathBar)

        let window = NSWindow(contentViewController: containerController)
        window.setContentSize(NSSize(width: 780, height: 760))
        window.minSize = NSSize(width: 460, height: 320)
        window.styleMask.insert([.resizable, .miniaturizable, .closable, .titled, .fullSizeContentView])
        window.titlebarAppearsTransparent = false
        window.tabbingMode = .disallowed
        window.representedURL = fileURL
        window.title = displayName
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        addWindowController(controller)
        beginExternalChangeObservation()
    }

    func writeEditedSource(_ proposedSource: String) -> EditWriteResult {
        guard proposedSource != source else { return .saved }
        return writeSource(proposedSource, requireUnchanged: true)
    }

    private func writeSource(_ proposedSource: String, requireUnchanged: Bool) -> EditWriteResult {
        guard let fileURL else { return .failed(CocoaError(.fileNoSuchFile)) }
        externalReloadTask?.cancel()

        var result: EditWriteResult = .failed(CocoaError(.fileWriteUnknown))
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: self)
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let data = try Data(contentsOf: coordinatedURL)
                let decoded = try Self.decodedSource(from: data)
                // Metadata can lag behind an atomic replacement, especially
                // when the editor changes the file size. Compare the decoded
                // contents that would actually be overwritten instead of
                // treating a stale modification date or size as a conflict.
                if requireUnchanged, decoded.value != source {
                    result = .conflict
                    return
                }
                guard let encoded = proposedSource.data(
                    using: decoded.encoding,
                    allowLossyConversion: false
                ) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                try encoded.write(to: coordinatedURL, options: .atomic)
                source = proposedSource
                result = .saved
            } catch {
                result = .failed(error)
            }
        }
        if let coordinationError {
            return .failed(coordinationError)
        }
        if case .saved = result {
            recordSuccessfulWrite(proposedSource, at: fileURL)
        }
        return result
    }

    private func recordSuccessfulWrite(_ newSource: String, at url: URL) {
        let signature = Self.fileSignature(for: url)
        lastLoadedFileSignature = signature
        pendingSelfWrite = SelfWriteExpectation(
            source: newSource,
            retriesRemaining: 3
        )
    }

    private func toggleTask(at taskIndex: Int) {
        guard let fileURL else { return }
        externalReloadTask?.cancel()

        var updatedSource: String?
        var operationError: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: self)
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let data = try Data(contentsOf: coordinatedURL)
                let decoded = try Self.decodedSource(from: data)
                guard let toggled = MarkdownTaskListEditor.togglingTask(
                    at: taskIndex,
                    in: decoded.value
                ) else {
                    return
                }
                guard let encoded = toggled.data(
                    using: decoded.encoding,
                    allowLossyConversion: false
                ) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                try encoded.write(to: coordinatedURL, options: .atomic)
                updatedSource = toggled
            } catch {
                operationError = error
            }
        }

        if let operationError {
            presentTaskWriteError(operationError)
            return
        }
        if let coordinationError {
            presentTaskWriteError(coordinationError)
            return
        }
        guard let updatedSource else {
            scheduleExternalReload()
            return
        }

        source = updatedSource
        recordSuccessfulWrite(updatedSource, at: fileURL)
        for controller in windowControllers {
            (controller.contentViewController as? MarkdownViewController)?.updateSource(source)
        }
    }

    private func presentTaskWriteError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = windowControllers.first?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentEditConflict(proposedSource: String, controller: MarkdownViewController) {
        guard !isPresentingConflict else { return }
        isPresentingConflict = true
        defer { isPresentingConflict = false }

        let alert = NSAlert()
        alert.messageText = "This Markdown file changed outside Markdown Preview."
        alert.informativeText = "Choose whether to keep your edit or reload the version saved by another app."
        alert.addButton(withTitle: "Keep My Changes")
        alert.addButton(withTitle: "Reload File")
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            switch writeSource(proposedSource, requireUnchanged: false) {
            case .saved:
                controller.updateSource(proposedSource)
            case let .failed(error):
                presentTaskWriteError(error)
            case .conflict:
                break
            }
        case .alertSecondButtonReturn:
            reloadFile(controller: controller)
        default:
            break
        }
    }

    private func reloadFile(controller: MarkdownViewController) {
        guard let fileURL,
              let snapshot = Self.coordinatedSnapshot(for: fileURL)
        else { return }
        source = (try? Self.decodedSource(from: snapshot.data).value) ?? source
        lastLoadedFileSignature = snapshot.signature
        pendingSelfWrite = nil
        controller.updateSource(source)
    }

    nonisolated override func presentedItemDidChange() {
        super.presentedItemDidChange()
        Task { @MainActor [weak self] in
            self?.scheduleExternalReload()
        }
    }

    nonisolated override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        Task { @MainActor [weak self] in
            self?.fileWatcher?.update(url: newURL)
            self?.scheduleExternalReload()
            self?.updateWindowURL(newURL)
        }
    }

    var renderedText: NSAttributedString {
        MarkdownAttributedRenderer().render(
            source,
            options: .init(fontScale: FontScaleController.shared.scale)
        )
    }

    var printableText: NSAttributedString {
        MarkdownAttributedRenderer().render(
            source,
            options: .init(fontScale: FontScaleController.shared.scale, palette: .print)
        )
    }

    private func beginExternalChangeObservation() {
        guard let fileURL else { return }
        lastLoadedFileSignature = Self.fileSignature(for: fileURL)
        fileWatcher = MarkdownFileWatcher(url: fileURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleExternalReload()
            }
        }
    }

    private func scheduleExternalReload() {
        guard fileURL != nil else { return }
        externalReloadTask?.cancel()
        externalReloadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }

            guard let self, let url = self.fileURL else { return }
            let snapshot = await Task.detached(priority: .utility) {
                Self.coordinatedSnapshot(for: url)
            }.value

            guard !Task.isCancelled else { return }
            self.applyExternalSnapshot(snapshot)
        }
    }

    private func applyExternalSnapshot(_ snapshot: FileSnapshot?) {
        guard let snapshot, snapshot.signature != lastLoadedFileSignature else { return }

        // Atomic writes can notify both NSFilePresenter and the vnode watcher
        // before all metadata has settled. If the content is already the
        // source we just saved, this is our own write rather than a conflict.
        if let decoded = try? Self.decodedSource(from: snapshot.data),
           decoded.value == source
        {
            lastLoadedFileSignature = snapshot.signature
            pendingSelfWrite = nil
            return
        }

        if var pendingSelfWrite,
           pendingSelfWrite.source == source,
           pendingSelfWrite.retriesRemaining > 0
        {
            pendingSelfWrite.retriesRemaining -= 1
            self.pendingSelfWrite = pendingSelfWrite
            scheduleExternalReload()
            return
        }
        pendingSelfWrite = nil

        if let controller = windowControllers.first?.contentViewController as? MarkdownViewController {
            presentEditConflict(proposedSource: source, controller: controller)
            return
        }

        do {
            try read(from: snapshot.data, ofType: "net.daringfireball.markdown")
        } catch {
            return
        }

        lastLoadedFileSignature = snapshot.signature
        for controller in windowControllers {
            (controller.contentViewController as? MarkdownViewController)?.updateSource(source)
        }
    }

    private func updateWindowURL(_ url: URL) {
        for controller in windowControllers {
            controller.window?.representedURL = url
            controller.window?.title = displayName
            (controller.contentViewController as? MarkdownViewController)?.updateDocumentURL(url)
        }
        pathBars.forEach { $0.updateDocumentURL(url) }
    }

    private struct FileSignature: Equatable, Sendable {
        let modificationDate: Date?
        let fileSize: Int64?
    }

    private struct FileSnapshot: Sendable {
        let data: Data
        let signature: FileSignature
    }

    private struct SelfWriteExpectation {
        let source: String
        var retriesRemaining: Int
    }

    private nonisolated static func fileSignature(for url: URL) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
        ]) else {
            return nil
        }
        return FileSignature(
            modificationDate: values.contentModificationDate,
            fileSize: values.fileSize.map(Int64.init)
        )
    }

    private nonisolated static func coordinatedSnapshot(for url: URL) -> FileSnapshot? {
        guard let before = fileSignature(for: url) else { return nil }

        var data: Data?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            data = try? Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
        }

        guard let data, let after = fileSignature(for: url), before == after else { return nil }
        return FileSnapshot(data: data, signature: after)
    }
}

private final class MarkdownFileWatcher: @unchecked Sendable {
    private let queueKey = DispatchSpecificKey<Void>()
    private let queue = DispatchQueue(
        label: "com.cseibert.MarkdownPreview.file-watcher",
        qos: .utility
    )
    private var url: URL
    private var source: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var onChange: (() -> Void)?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: ())
        queue.async { [weak self] in
            self?.startSourcesIfNeeded()
        }
    }

    func update(url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.url = url
            self.cancelSources()
            self.startSourcesIfNeeded()
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync {
                stopOnQueue()
            }
        }
    }

    deinit {
        stop()
    }

    private func stopOnQueue() {
        cancelSources()
        onChange = nil
    }

    private func startSourcesIfNeeded() {
        startDirectorySourceIfNeeded()
        startFileSourceIfNeeded()
    }

    private func startFileSourceIfNeeded() {
        guard source == nil, onChange != nil else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let fileSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        fileSource.setEventHandler { [weak self] in
            self?.handleEvent(fileSource.data)
        }
        fileSource.setCancelHandler {
            close(descriptor)
        }
        source = fileSource
        fileSource.resume()
    }

    private func startDirectorySourceIfNeeded() {
        guard directorySource == nil, onChange != nil else { return }
        let directoryURL = url.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        directorySource.setEventHandler { [weak self] in
            self?.handleDirectoryEvent(directorySource.data)
        }
        directorySource.setCancelHandler {
            close(descriptor)
        }
        self.directorySource = directorySource
        directorySource.resume()
    }

    private func handleEvent(_ flags: DispatchSource.FileSystemEvent) {
        guard source != nil else { return }
        onChange?()

        if flags.contains(.rename) || flags.contains(.delete) {
            cancelFileSource()
        }
    }

    private func handleDirectoryEvent(_ flags: DispatchSource.FileSystemEvent) {
        guard flags.contains(.write) else { return }
        if source == nil {
            startFileSourceIfNeeded()
            onChange?()
        }
    }

    private func cancelSources() {
        cancelFileSource()
        directorySource?.setEventHandler {}
        directorySource?.cancel()
        directorySource = nil
    }

    private func cancelFileSource() {
        source?.setEventHandler {}
        source?.cancel()
        source = nil
    }
}
