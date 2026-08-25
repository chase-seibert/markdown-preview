import AppKit
import Darwin
import Foundation

@MainActor
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    // NSDocument's read/write overrides are imported as nonisolated in Swift 6.
    // AppKit serializes document loading before window creation, so this storage
    // is safe to bridge into the otherwise main-actor document object.
    nonisolated(unsafe) private(set) var source = ""
    private var lastLoadedFileSignature: FileSignature?
    private var externalReloadTask: Task<Void, Never>?
    private var fileWatcher: MarkdownFileWatcher?

    override class var autosavesInPlace: Bool { false }
    override var isDocumentEdited: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        if let utf8 = String(data: data, encoding: .utf8) {
            source = utf8
            return
        }

        var converted: NSString?
        var lossy = ObjCBool(false)
        guard NSString.stringEncoding(
            for: data,
            encodingOptions: nil,
            convertedString: &converted,
            usedLossyConversion: &lossy
        ) != 0, let converted
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        source = converted as String
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(source.utf8)
    }

    override func makeWindowControllers() {
        let contentController = MarkdownViewController(source: source)
        let window = NSWindow(contentViewController: contentController)
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
        }
    }

    private struct FileSignature: Equatable, Sendable {
        let modificationDate: Date?
        let fileSize: Int64?
    }

    private struct FileSnapshot: Sendable {
        let data: Data
        let signature: FileSignature
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
