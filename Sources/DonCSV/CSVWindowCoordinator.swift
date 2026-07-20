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
    private var windows: [UUID: WeakWindow] = [:]
    private var pendingTabParents: [UUID: WeakWindow] = [:]
    private var didAttemptInitialRestore = false

    func document(for sessionID: UUID) -> CSVDocument {
        if let document = documents[sessionID] {
            return document
        }

        let document = CSVDocument()
        documents[sessionID] = document
        return document
    }

    func restoreInitialFileIfNeeded(into document: CSVDocument) {
        guard !didAttemptInitialRestore else { return }
        didAttemptInitialRestore = true
        document.restoreLastFileIfAvailable()
    }

    func presentOpenPanel(
        from sessionID: UUID?,
        openSession: (UUID) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose one or more CSV files to edit"

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
                focusWindow(for: existingSessionID)
                continue
            }

            if canReuseSource,
               let sourceSessionID,
               let sourceDocument = documents[sourceSessionID],
               sourceDocument.load(url) {
                canReuseSource = false
                focusWindow(for: sourceSessionID)
                continue
            }

            let sessionID = UUID()
            let document = CSVDocument()
            guard document.load(url) else { continue }
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
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return windows.first(where: { $0.value.value === keyWindow })?.key
    }

    func register(window: NSWindow, for sessionID: UUID) {
        windows[sessionID] = WeakWindow(window)
        window.tabbingIdentifier = "com.alexfraser.DonCSV.document"
        window.tabbingMode = .preferred

        guard let parent = pendingTabParents.removeValue(forKey: sessionID)?.value,
              parent !== window else { return }

        parent.addTabbedWindow(window, ordered: .above)
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func unregister(window: NSWindow, for sessionID: UUID) {
        guard windows[sessionID]?.value === window else { return }
        windows.removeValue(forKey: sessionID)
        pendingTabParents.removeValue(forKey: sessionID)
        documents.removeValue(forKey: sessionID)?.close()
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
}

private struct FocusedCSVDocumentKey: FocusedValueKey {
    typealias Value = CSVDocument
}

extension FocusedValues {
    var csvDocument: CSVDocument? {
        get { self[FocusedCSVDocumentKey.self] }
        set { self[FocusedCSVDocumentKey.self] = newValue }
    }
}

struct CSVAppCommands: Commands {
    @ObservedObject var coordinator: CSVWindowCoordinator
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.csvDocument) private var document

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { document?.undoManager.undo() }
                .keyboardShortcut("z")
                .disabled(document?.undoManager.canUndo != true)
            Button("Redo") { document?.undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(document?.undoManager.canRedo != true)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                coordinator.openNewWindow { openWindow(value: $0) }
            }
            .keyboardShortcut("n")

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

            Button("Save") { document?.saveNow() }
                .keyboardShortcut("s")
                .disabled(document?.fileURL == nil)
        }

        CommandMenu("Table") {
            Button("Add Row") { document?.addRow() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(document?.fileURL == nil)
            Button("Add Column") { document?.addColumn() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(document?.fileURL == nil)
        }
    }
}

