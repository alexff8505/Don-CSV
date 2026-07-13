import AppKit
import SwiftUI

@main
struct DonCSVApp: App {
    @StateObject private var document = CSVDocument()

    init() {
        if let url = Bundle.main.url(forResource: "DonCSVIcon-1024", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(document: document)
                .frame(minWidth: 760, minHeight: 480)
                .background(WindowFrameAutosaver())
                .onAppear { document.restoreLastFileIfAvailable() }
                .onOpenURL { document.load($0) }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { document.undoManager.undo() }
                    .keyboardShortcut("z")
                    .disabled(!document.undoManager.canUndo)
                Button("Redo") { document.undoManager.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!document.undoManager.canRedo)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open…") { document.open() }
                    .keyboardShortcut("o")
                Button("Save") { document.saveNow() }
                    .keyboardShortcut("s")
                    .disabled(document.fileURL == nil)
            }

            CommandMenu("Table") {
                Button("Add Row") { document.addRow() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(document.fileURL == nil)
                Button("Add Column") { document.addColumn() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(document.fileURL == nil)
            }
        }
    }
}

private struct WindowFrameAutosaver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowFrameAutosaveView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowFrameAutosaveView: NSView {
    private static let frameKey = "DonCSV.mainWindowFrame"

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        NotificationCenter.default.removeObserver(self)
        let savedFrame = UserDefaults.standard.string(forKey: Self.frameKey)

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            if let savedFrame {
                let frame = NSRectFromString(savedFrame)
                if frame.width >= 760, frame.height >= 480,
                   NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                    window.setFrame(frame, display: true)
                }
            }
            self.startObserving(window)
        }
    }

    private func startObserving(_ window: NSWindow) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveWindowFrame(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveWindowFrame(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
    }

    @objc private func saveWindowFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameKey)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
