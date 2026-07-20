import AppKit
import SwiftUI

@main
struct DonCSVApp: App {
    @StateObject private var coordinator = CSVWindowCoordinator()
    @NSApplicationDelegateAdaptor(DonCSVAppDelegate.self) private var appDelegate

    init() {
        // Don CSV groups files explicitly so Open/New Tab are predictable while
        // New Window remains a genuinely separate window.
        NSWindow.allowsAutomaticWindowTabbing = false
        if let url = Bundle.main.url(forResource: "DonCSVIcon-1024", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("Don CSV", for: UUID.self) { $requestedSessionID in
            CSVSessionScene(
                requestedSessionID: requestedSessionID,
                appDelegate: appDelegate
            )
                .environmentObject(coordinator)
        }
        .handlesExternalEvents(matching: [])
        .windowStyle(.automatic)
        .commands {
            CSVAppCommands(coordinator: coordinator)
        }
    }
}

@MainActor
private final class DonCSVAppDelegate: NSObject, NSApplicationDelegate {
    static let openURLsNotification = Notification.Name("DonCSV.openURLs")

    private var pendingRequests: [CSVOpenRequest] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        let request = CSVOpenRequest(urls: urls)
        pendingRequests.append(request)
        NotificationCenter.default.post(
            name: Self.openURLsNotification,
            object: request
        )
    }

    func takePendingOpenRequests() -> [CSVOpenRequest] {
        defer { pendingRequests.removeAll() }
        return pendingRequests
    }

    func markOpenRequestHandled(_ requestID: UUID) {
        pendingRequests.removeAll { $0.id == requestID }
    }
}

private final class CSVOpenRequest: NSObject {
    let id = UUID()
    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }
}

private struct CSVSessionScene: View {
    let requestedSessionID: UUID?
    let appDelegate: DonCSVAppDelegate

    @EnvironmentObject private var coordinator: CSVWindowCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var fallbackSessionID = UUID()

    private var sessionID: UUID {
        requestedSessionID ?? fallbackSessionID
    }

    var body: some View {
        let document = coordinator.document(for: sessionID)

        ContentView(
            document: document,
            openFiles: {
                coordinator.presentOpenPanel(from: sessionID) {
                    openWindow(value: $0)
                }
            },
            openURLs: { urls in
                coordinator.open(urls, from: sessionID) {
                    openWindow(value: $0)
                }
            }
        )
        .frame(minWidth: 760, minHeight: 480)
        .background(WindowFrameAutosaver())
        .background(
            WindowSessionAccessor(
                sessionID: sessionID,
                register: { coordinator.register(window: $0, for: sessionID) },
                activate: { coordinator.activate(window: $0) },
                unregister: { coordinator.unregister(window: $0, for: sessionID) }
            )
        )
        .onAppear {
            coordinator.restoreInitialFileIfNeeded(into: document)
            for request in appDelegate.takePendingOpenRequests() {
                handleExternalOpen(request)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: DonCSVAppDelegate.openURLsNotification)) {
            guard let request = $0.object as? CSVOpenRequest else { return }
            handleExternalOpen(request)
        }
    }

    private func handleExternalOpen(_ request: CSVOpenRequest) {
        coordinator.handleExternalOpen(requestID: request.id, urls: request.urls) {
            openWindow(value: $0)
        }
        appDelegate.markOpenRequestHandled(request.id)
    }
}

private struct WindowSessionAccessor: NSViewRepresentable {
    let sessionID: UUID
    let register: (NSWindow) -> Void
    let activate: (NSWindow) -> Void
    let unregister: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowSessionView {
        let view = WindowSessionView()
        view.register = register
        view.activate = activate
        view.unregister = unregister
        return view
    }

    func updateNSView(_ nsView: WindowSessionView, context: Context) {
        nsView.register = register
        nsView.activate = activate
        nsView.unregister = unregister
        nsView.registerCurrentWindowIfNeeded()
    }
}

private final class WindowSessionView: NSView {
    var register: ((NSWindow) -> Void)?
    var activate: ((NSWindow) -> Void)?
    var unregister: ((NSWindow) -> Void)?
    private weak var registeredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerCurrentWindowIfNeeded()
    }

    func registerCurrentWindowIfNeeded() {
        guard let window, window !== registeredWindow else { return }
        if let registeredWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: registeredWindow
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: registeredWindow
            )
        }

        registeredWindow = window
        register?(window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        if window.isKeyWindow {
            activate?(window)
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        activate?(window)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        unregister?(window)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
