import AppKit
import CryptoKit
import Foundation

@MainActor
final class CSVDocument: ObservableObject {
    @Published private(set) var rows: [[String]] = []
    @Published private(set) var fileURL: URL?
    @Published private(set) var status = "Open a CSV file to begin"
    @Published private(set) var revision = 0

    private var lastDigest: SHA256.Digest?
    private var monitor: Timer?
    private var saveTask: Task<Void, Never>?
    private var isSecurityScoped = false

    var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a CSV file to edit"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        monitor?.invalidate()
        if isSecurityScoped { fileURL?.stopAccessingSecurityScopedResource() }

        fileURL = url
        isSecurityScoped = url.startAccessingSecurityScopedResource()

        do {
            let data = try Data(contentsOf: url)
            apply(data, message: "Loaded \(url.lastPathComponent)")
            startMonitoring()
        } catch {
            status = "Could not open file: \(error.localizedDescription)"
        }
    }

    func value(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    func setValue(_ value: String, row: Int, column: Int) {
        guard rows.indices.contains(row) else { return }
        while rows[row].count <= column { rows[row].append("") }
        rows[row][column] = value
        revision += 1
        status = "Editing…"
        scheduleSave()
    }

    func addRow() {
        guard fileURL != nil else { return }
        rows.append(Array(repeating: "", count: max(columnCount, 1)))
        revision += 1
        scheduleSave()
    }

    func addColumn() {
        guard fileURL != nil else { return }
        if rows.isEmpty { rows = [["Column 1"]] }
        else { for index in rows.indices { rows[index].append("") } }
        revision += 1
        scheduleSave()
    }

    func deleteRow(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
        revision += 1
        scheduleSave()
    }

    func deleteColumn(_ index: Int) {
        guard index >= 0, index < columnCount else { return }
        for rowIndex in rows.indices where rows[rowIndex].indices.contains(index) {
            rows[rowIndex].remove(at: index)
        }
        revision += 1
        scheduleSave()
    }

    func pasteValues(_ values: [[String]], startingAtRow startRow: Int, column startColumn: Int) {
        guard fileURL != nil, startRow >= 0, startColumn >= 0, !values.isEmpty else { return }
        let pastedWidth = values.map(\.count).max() ?? 0
        guard pastedWidth > 0 else { return }

        let requiredColumnCount = max(columnCount, startColumn + pastedWidth)
        while rows.count < startRow + values.count {
            rows.append(Array(repeating: "", count: requiredColumnCount))
        }

        for (rowOffset, pastedRow) in values.enumerated() {
            let rowIndex = startRow + rowOffset
            while rows[rowIndex].count < requiredColumnCount {
                rows[rowIndex].append("")
            }
            for (columnOffset, value) in pastedRow.enumerated() {
                rows[rowIndex][startColumn + columnOffset] = value
            }
        }

        revision += 1
        status = "Editing…"
        scheduleSave()
    }

    func saveNow() {
        saveTask?.cancel()
        guard let url = fileURL else { return }

        do {
            let data = Data(CSVCodec.encode(rows).utf8)
            try data.write(to: url, options: .atomic)
            lastDigest = SHA256.hash(data: data)
            status = "Saved \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func apply(_ data: Data, message: String) {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? ""
        rows = CSVCodec.decode(text)
        lastDigest = SHA256.hash(data: data)
        revision += 1
        status = message
    }

    private func startMonitoring() {
        monitor = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkForExternalChanges() }
        }
    }

    private func checkForExternalChanges() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let digest = SHA256.hash(data: data)
        guard digest != lastDigest else { return }
        saveTask?.cancel()
        apply(data, message: "Updated from disk \(Date.now.formatted(date: .omitted, time: .shortened))")
    }
}
