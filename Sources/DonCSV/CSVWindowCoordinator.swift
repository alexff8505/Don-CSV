import AppKit
import SwiftUI

@MainActor
final class CSVWindowCoordinator: ObservableObject {
    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow?) {
            self.value = value
        }
    }

    private var documents: [UUID: CSVDocument] = [:]
    private var tableEditingHelpers: [UUID: CSVTableEditingHelper] = [:]
    private var windows: [UUID: WeakWindow] = [:]
    private var pendingTabParents: [UUID: WeakWindow] = [:]
    private var separateWindowSessions: Set<UUID> = []
    private var lastActiveWindow: WeakWindow?
    private var handledExternalOpenRequests: Set<UUID> = []
    private var didAttemptInitialRestore = false
    @Published private(set) var recentDocumentURLs: [URL] = []

    init() {
        refreshRecentDocuments()
    }

    func document(for sessionID: UUID) -> CSVDocument {
        if let document = documents[sessionID] {
            return document
        }

        let document = CSVDocument()
        documents[sessionID] = document
        return document
    }

    func tableEditingHelper(for sessionID: UUID) -> CSVTableEditingHelper {
        if let helper = tableEditingHelpers[sessionID] {
            return helper
        }

        let helper = CSVTableEditingHelper()
        tableEditingHelpers[sessionID] = helper
        return helper
    }

    func restoreInitialFileIfNeeded(into document: CSVDocument) {
        guard !didAttemptInitialRestore else { return }
        didAttemptInitialRestore = true
        document.restoreLastFileIfAvailable { [weak self] url in
            self?.rememberRecentDocument(url)
        }
    }

    func presentNewCSVPanel(
        from sessionID: UUID?,
        openSession: (UUID) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Untitled.csv"
        panel.title = "New CSV"
        panel.prompt = "Create"
        panel.message = "Choose where to create the new CSV file."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let initialRows = [["Column 1"], [""]]
            try Data(CSVCodec.encode(initialRows).utf8).write(to: url, options: .atomic)
            open([url], from: sessionID, openSession: openSession)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Could Not Create CSV"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func presentOpenPanel(
        from sessionID: UUID?,
        openSession: (UUID) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Open in Tabs"
        panel.message = "Select several CSV files with Command-click or Shift-click to open each in its own tab."

        guard panel.runModal() == .OK else { return }
        open(panel.urls, from: sessionID, openSession: openSession)
    }

    func open(
        _ urls: [URL],
        from sourceSessionID: UUID?,
        openSession: (UUID) -> Void
    ) {
        let uniqueURLs = urls.reduce(into: [URL]()) { result, url in
            let canonicalURL = canonical(url)
            guard !result.contains(where: { canonical($0) == canonicalURL }) else { return }
            result.append(url)
        }
        guard !uniqueURLs.isEmpty else { return }

        let sourceWindow = sourceSessionID.flatMap { windows[$0]?.value } ?? NSApp.keyWindow
        var canReuseSource = sourceSessionID
            .flatMap { documents[$0] }
            .map { $0.fileURL == nil } ?? false

        for url in uniqueURLs {
            if let existingSessionID = sessionID(for: url) {
                rememberRecentDocument(url)
                focusWindow(for: existingSessionID)
                continue
            }

            if canReuseSource,
               let sourceSessionID,
               let sourceDocument = documents[sourceSessionID],
               sourceDocument.load(url) {
                rememberRecentDocument(url)
                canReuseSource = false
                focusWindow(for: sourceSessionID)
                continue
            }

            let sessionID = UUID()
            let document = CSVDocument()
            guard document.load(url) else { continue }
            rememberRecentDocument(url)
            documents[sessionID] = document
            if let sourceWindow {
                pendingTabParents[sessionID] = WeakWindow(sourceWindow)
            }
            openSession(sessionID)
        }
    }

    func openNewWindow(openSession: (UUID) -> Void) {
        let sessionID = UUID()
        documents[sessionID] = CSVDocument()
        separateWindowSessions.insert(sessionID)
        openSession(sessionID)
    }

    func openNewTab(from sourceSessionID: UUID?, openSession: (UUID) -> Void) {
        let sessionID = UUID()
        documents[sessionID] = CSVDocument()
        let parent = sourceSessionID.flatMap { windows[$0]?.value } ?? NSApp.keyWindow
        if let parent {
            pendingTabParents[sessionID] = WeakWindow(parent)
        }
        openSession(sessionID)
    }

    func activeSessionID() -> UUID? {
        if let keyWindow = NSApp.keyWindow,
           let sessionID = windows.first(where: { $0.value.value === keyWindow })?.key {
            return sessionID
        }
        guard let lastActiveWindow = lastActiveWindow?.value else { return nil }
        return windows.first(where: { $0.value.value === lastActiveWindow })?.key
    }

    func activeDocument() -> CSVDocument? {
        activeSessionID().flatMap { documents[$0] }
    }

    func activeTableEditingHelper() -> CSVTableEditingHelper? {
        activeSessionID().flatMap { tableEditingHelpers[$0] }
    }

    func clearRecentDocuments() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecentDocuments()
    }

    func handleExternalOpen(
        requestID: UUID,
        urls: [URL],
        openSession: (UUID) -> Void
    ) {
        if handledExternalOpenRequests.count >= 256 {
            handledExternalOpenRequests.removeAll(keepingCapacity: true)
        }
        guard handledExternalOpenRequests.insert(requestID).inserted else { return }
        open(urls, from: activeSessionID(), openSession: openSession)
    }

    func register(window: NSWindow, for sessionID: UUID) {
        let defaultParent = lastActiveWindow?.value
            ?? windows.values.compactMap(\.value).first
        windows[sessionID] = WeakWindow(window)
        window.tabbingIdentifier = "com.alexfraser.DonCSV.document"
        window.tabbingMode = .preferred

        if separateWindowSessions.contains(sessionID) {
            lastActiveWindow = WeakWindow(window)
            return
        }

        let parent = pendingTabParents.removeValue(forKey: sessionID)?.value ?? defaultParent
        guard let parent, parent !== window else {
            lastActiveWindow = WeakWindow(window)
            return
        }

        parent.addTabbedWindow(window, ordered: .above)
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        lastActiveWindow = WeakWindow(window)
    }

    func activate(window: NSWindow) {
        lastActiveWindow = WeakWindow(window)
    }

    func unregister(window: NSWindow, for sessionID: UUID) {
        guard windows[sessionID]?.value === window else { return }
        windows.removeValue(forKey: sessionID)
        pendingTabParents.removeValue(forKey: sessionID)
        separateWindowSessions.remove(sessionID)
        if lastActiveWindow?.value === window {
            lastActiveWindow = windows.values.first(where: { $0.value != nil })
        }
        documents.removeValue(forKey: sessionID)?.close()
        tableEditingHelpers.removeValue(forKey: sessionID)
    }

    private func sessionID(for url: URL) -> UUID? {
        let requestedURL = canonical(url)
        return documents.first { _, document in
            guard let fileURL = document.fileURL else { return false }
            return canonical(fileURL) == requestedURL
        }?.key
    }

    private func focusWindow(for sessionID: UUID) {
        guard let window = windows[sessionID]?.value else { return }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func rememberRecentDocument(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecentDocuments()
    }

    private func refreshRecentDocuments() {
        recentDocumentURLs = Array(NSDocumentController.shared.recentDocumentURLs.prefix(10))
    }
}

struct CSVAppCommands: Commands {
    @ObservedObject var coordinator: CSVWindowCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { coordinator.activeDocument()?.undoManager.undo() }
                .keyboardShortcut("z")
            Button("Redo") { coordinator.activeDocument()?.undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button("New CSV…") {
                coordinator.presentNewCSVPanel(from: coordinator.activeSessionID()) {
                    openWindow(value: $0)
                }
            }
            .keyboardShortcut("n")

            Divider()

            Button("New Window") {
                coordinator.openNewWindow { openWindow(value: $0) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Tab") {
                coordinator.openNewTab(from: coordinator.activeSessionID()) {
                    openWindow(value: $0)
                }
            }
            .keyboardShortcut("t")

            Divider()

            Button("Open…") {
                coordinator.presentOpenPanel(from: coordinator.activeSessionID()) {
                    openWindow(value: $0)
                }
            }
            .keyboardShortcut("o")

            Menu("Open Recent") {
                if coordinator.recentDocumentURLs.isEmpty {
                    Button("No Recent Documents") {}
                        .disabled(true)
                } else {
                    ForEach(coordinator.recentDocumentURLs, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            coordinator.open([url], from: coordinator.activeSessionID()) {
                                openWindow(value: $0)
                            }
                        }
                        .help(url.path)
                    }

                    Divider()

                    Button("Clear Menu") {
                        coordinator.clearRecentDocuments()
                    }
                }
            }

            Divider()

            Button("Save") { coordinator.activeDocument()?.saveNow() }
                .keyboardShortcut("s")
        }

        CommandMenu("Table") {
            Button("Add Row") { coordinator.activeDocument()?.addRow() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Add Column") { coordinator.activeDocument()?.addColumn() }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Delete Rows") {
                guard let document = coordinator.activeDocument(),
                      let helper = coordinator.activeTableEditingHelper() else { return }
                helper.deleteSelectedRows(from: document)
            }
            .keyboardShortcut(.delete, modifiers: [.command])

            Button("Delete Columns") {
                guard let document = coordinator.activeDocument(),
                      let helper = coordinator.activeTableEditingHelper() else { return }
                helper.deleteSelectedColumns(from: document)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
        }
    }
}
