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
        }
        .windowStyle(.automatic)
        .commands {
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
