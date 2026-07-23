import AppKit
import CryptoKit
import Darwin
import Foundation

@MainActor
final class CSVDocument: ObservableObject {
    @Published private(set) var rows: [[String]] = []
    @Published private(set) var fileURL: URL?
    @Published private(set) var status = "Open a CSV file to begin"
    @Published private(set) var revision = 0

    let undoManager = UndoManager()

    private static let lastFileKey = "DonCSV.lastFilePath"
    private var lastDigest: SHA256.Digest?
    private var monitor: Timer?
    private var fileChangeWatcher: FileChangeWatcher?
    private var externalChangeTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var isSecurityScoped = false
    private var hasAttemptedRestore = false

    var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    var dataRowCount: Int {
        max(rows.count - 1, 0)
    }

    @discardableResult
    func load(_ url: URL) -> Bool {
        let newSecurityScope = url.startAccessingSecurityScopedResource()
        do {
            let data = try Data(contentsOf: url)
            monitor?.invalidate()
            if isSecurityScoped { fileURL?.stopAccessingSecurityScopedResource() }

            fileURL = url
            isSecurityScoped = newSecurityScope
            apply(data, message: "Loaded \(url.lastPathComponent)")
            undoManager.removeAllActions()
            UserDefaults.standard.set(url.path, forKey: Self.lastFileKey)
            startMonitoring()
            return true
        } catch {
            if newSecurityScope { url.stopAccessingSecurityScopedResource() }
            status = "Could not open file: \(error.localizedDescription)"
            return false
        }
    }

    func restoreLastFileIfAvailable() {
        guard !hasAttemptedRestore else { return }
        hasAttemptedRestore = true
        guard fileURL == nil,
              let path = UserDefaults.standard.string(forKey: Self.lastFileKey) else { return }

        let url = URL(fileURLWithPath: path)
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url)
                }.value
                guard let self, !Task.isCancelled, self.fileURL == nil else { return }

                let newSecurityScope = url.startAccessingSecurityScopedResource()
                self.fileURL = url
                self.isSecurityScoped = newSecurityScope
                self.apply(data, message: "Loaded \(url.lastPathComponent)")
                self.undoManager.removeAllActions()
                self.startMonitoring()
            } catch {
                guard let self, !Task.isCancelled else { return }
                UserDefaults.standard.removeObject(forKey: Self.lastFileKey)
                self.status = "Open a CSV file to begin"
            }
        }
    }

    func close() {
        restoreTask?.cancel()
        saveTask?.cancel()
        stopMonitoring()
        if isSecurityScoped { fileURL?.stopAccessingSecurityScopedResource() }
        isSecurityScoped = false
    }

    func value(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    func setValue(_ value: String, row: Int, column: Int) {
        guard rows.indices.contains(row) else { return }
        mutate(actionName: row == 0 ? "Rename Column" : "Edit Cell") {
            while rows[row].count <= column { rows[row].append("") }
            rows[row][column] = value
        }
    }

    func addRow() {
        guard fileURL != nil else { return }
        mutate(actionName: "Add Row") {
            rows.append(Array(repeating: "", count: max(columnCount, 1)))
        }
    }

    func addColumn() {
        guard fileURL != nil else { return }
        mutate(actionName: "Add Column") {
            if rows.isEmpty { rows = [["Column 1"]] }
            else { for index in rows.indices { rows[index].append("") } }
        }
    }

    func deleteRow(_ index: Int) {
        deleteRows([index])
    }

    func deleteColumn(_ index: Int) {
        deleteColumns([index])
    }

    /// Deletes data or header rows by absolute document index. Indices are removed highest-first.
    func deleteRows(_ indices: [Int]) {
        let uniqueSorted = Set(indices)
            .filter { rows.indices.contains($0) }
            .sorted(by: >)
        guard !uniqueSorted.isEmpty else { return }

        let actionName = uniqueSorted.count == 1 ? "Delete Row" : "Delete Rows"
        mutate(actionName: actionName) {
            for index in uniqueSorted {
                rows.remove(at: index)
            }
        }
    }

    /// Deletes columns by index across every row. Indices are removed highest-first.
    func deleteColumns(_ indices: [Int]) {
        let uniqueSorted = Set(indices)
            .filter { $0 >= 0 && $0 < columnCount }
            .sorted(by: >)
        guard !uniqueSorted.isEmpty else { return }

        let actionName = uniqueSorted.count == 1 ? "Delete Column" : "Delete Columns"
        mutate(actionName: actionName) {
            for index in uniqueSorted {
                for rowIndex in rows.indices where rows[rowIndex].indices.contains(index) {
                    rows[rowIndex].remove(at: index)
                }
            }
        }
    }

    /// Mirrored from the active table so menu commands can delete the current selection.
    var selectedDocumentRowsForEditing: [Int] = []
    var selectedColumnsForEditing: [Int] = []

    func pasteValues(
        _ values: [[String]],
        startingAtRow startRow: Int,
        column startColumn: Int,
        selectedRowCount: Int = 1,
        selectedColumnCount: Int = 1
    ) {
        guard fileURL != nil, startRow >= 0, startColumn >= 0, !values.isEmpty else { return }
        let pastedWidth = values.map(\.count).max() ?? 0
        guard pastedWidth > 0 else { return }

        mutate(actionName: "Paste Cells") {
            let targetHeight = max(values.count, selectedRowCount)
            let targetWidth = max(pastedWidth, selectedColumnCount)
            let requiredColumnCount = max(columnCount, startColumn + targetWidth)
            while rows.count < startRow + targetHeight {
                rows.append(Array(repeating: "", count: requiredColumnCount))
            }

            for rowOffset in 0..<targetHeight {
                let rowIndex = startRow + rowOffset
                while rows[rowIndex].count < requiredColumnCount {
                    rows[rowIndex].append("")
                }
                let pastedRow = values[rowOffset % values.count]
                for columnOffset in 0..<targetWidth {
                    let sourceColumn = columnOffset % pastedWidth
                    let value = pastedRow.indices.contains(sourceColumn) ? pastedRow[sourceColumn] : ""
                    rows[rowIndex][startColumn + columnOffset] = value
                }
            }
        }
    }

    func pasteValues(
        _ values: [[String]],
        intoRows targetRows: [Int],
        column startColumn: Int,
        selectedColumnCount: Int = 1
    ) {
        guard fileURL != nil, startColumn >= 0, !values.isEmpty else { return }
        let pastedWidth = values.map(\.count).max() ?? 0
        guard pastedWidth > 0 else { return }

        mutate(actionName: "Paste Cells") {
            let validTargetRows = targetRows.filter { rows.indices.contains($0) && $0 > 0 }
            let targetHeight = max(values.count, validTargetRows.count)
            guard targetHeight > 0 else { return }

            let targetWidth = max(pastedWidth, selectedColumnCount)
            let requiredColumnCount = max(columnCount, startColumn + targetWidth)
            var rowIndexes = validTargetRows
            while rowIndexes.count < targetHeight {
                rows.append(Array(repeating: "", count: requiredColumnCount))
                rowIndexes.append(rows.count - 1)
            }

            for rowOffset in 0..<targetHeight {
                let rowIndex = rowIndexes[rowOffset]
                while rows[rowIndex].count < requiredColumnCount {
                    rows[rowIndex].append("")
                }
                let pastedRow = values[rowOffset % values.count]
                for columnOffset in 0..<targetWidth {
                    let sourceColumn = columnOffset % pastedWidth
                    let value = pastedRow.indices.contains(sourceColumn) ? pastedRow[sourceColumn] : ""
                    rows[rowIndex][startColumn + columnOffset] = value
                }
            }
        }
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

    private func mutate(actionName: String, change: () -> Void) {
        let previousRows = rows
        change()
        guard rows != previousRows else { return }
        registerUndo(restoring: previousRows, actionName: actionName)
        documentDidChange()
    }

    private func registerUndo(restoring snapshot: [[String]], actionName: String) {
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restoreRows(snapshot, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    private func restoreRows(_ snapshot: [[String]], actionName: String) {
        let currentRows = rows
        rows = snapshot
        registerUndo(restoring: currentRows, actionName: actionName)
        documentDidChange()
    }

    private func documentDidChange() {
        revision += 1
        status = "Editing…"
        scheduleSave()
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
        stopMonitoring()
        guard let url = fileURL else { return }

        fileChangeWatcher = FileChangeWatcher(fileURL: url) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleExternalChangeCheck()
            }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkForExternalChanges() }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitor = timer
    }

    private func stopMonitoring() {
        externalChangeTask?.cancel()
        externalChangeTask = nil
        monitor?.invalidate()
        monitor = nil
        fileChangeWatcher?.cancel()
        fileChangeWatcher = nil
    }

    private func scheduleExternalChangeCheck() {
        externalChangeTask?.cancel()
        externalChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.checkForExternalChanges()
        }
    }

    private func checkForExternalChanges() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let digest = SHA256.hash(data: data)
        guard digest != lastDigest else { return }
        saveTask?.cancel()
        apply(data, message: "Updated from disk \(Date.now.formatted(date: .omitted, time: .shortened))")
        undoManager.removeAllActions()
    }
}

private final class FileChangeWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private var isCancelled = false

    init?(fileURL: URL, onChange: @escaping @Sendable () -> Void) {
        let directoryURL = fileURL.deletingLastPathComponent()
        let descriptor = Darwin.open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        source.resume()
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        source.cancel()
    }

    deinit {
        cancel()
    }
}
