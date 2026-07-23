import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: CSVDocument
    let openFiles: () -> Void
    let openURLs: ([URL]) -> Void
    @State private var selectedDocumentRows: [Int] = []
    @State private var selectedColumns: [Int] = []
    @State private var hiddenColumns: Set<Int> = []
    @State private var isColumnInspectorPresented = false
    @State private var filterColumn = 0
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            if document.fileURL == nil {
                ContentUnavailableView {
                    Label("No CSV Open", systemImage: "tablecells")
                } description: {
                    Text("Open a comma-separated values file to view and edit it.")
                } actions: {
                    Button("Open CSV…") { openFiles() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                CSVTableView(
                    document: document,
                    selectedDocumentRows: $selectedDocumentRows,
                    selectedColumns: $selectedColumns,
                    hiddenColumns: $hiddenColumns,
                    filterColumn: $filterColumn,
                    filterText: filterText
                )
                .id(document.fileURL)
            }

            if document.fileURL != nil {
                Divider()

                HStack(spacing: 12) {
                    Label(document.status, systemImage: statusSymbol)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(tableSummary)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { openFiles() } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open CSV files")

                if document.fileURL != nil {
                    Button { document.saveNow() } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .help("Save")

                    Divider()

                    Menu {
                        Button("Add Row", systemImage: "plus.rectangle.on.rectangle") {
                            document.addRow()
                        }
                        Button("Add Column", systemImage: "rectangle.split.3x1") {
                            document.addColumn()
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .help("Add a row or column")

                    Menu {
                        Button("Rename Column…", systemImage: "pencil") {
                            renameSelectedColumn()
                        }
                        .disabled(selectedColumns.count != 1
                            || selectedColumns[0] >= document.columnCount)

                        Divider()

                        Button(deleteRowsTitle, systemImage: "minus") {
                            deleteSelectedRows()
                        }
                        .disabled(selectedDocumentRows.isEmpty)

                        Button(deleteColumnsTitle, systemImage: "rectangle.split.1x2") {
                            deleteSelectedColumns()
                        }
                        .disabled(selectedColumns.isEmpty)
                    } label: {
                        Label("Table Actions", systemImage: "ellipsis.circle")
                    }
                    .help("Table actions")

                    Divider()

                    Button {
                        isColumnInspectorPresented.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help(isColumnInspectorPresented ? "Hide Inspector" : "Show Inspector")
                }
            }
        }
        .inspector(isPresented: $isColumnInspectorPresented) {
            TableInspector(
                document: document,
                hiddenColumns: $hiddenColumns,
                filterColumn: $filterColumn,
                filterText: $filterText
            )
            .inspectorColumnWidth(min: 210, ideal: 240, max: 320)
        }
        .navigationTitle(document.fileURL?.lastPathComponent ?? "Don CSV")
        .onChange(of: document.fileURL) {
            clearSelection()
            hiddenColumns.removeAll()
            filterColumn = 0
            filterText = ""
            if document.fileURL == nil {
                isColumnInspectorPresented = false
            }
        }
        .onChange(of: document.columnCount) {
            hiddenColumns = hiddenColumns.filter { $0 < document.columnCount }
            if document.columnCount == 0 {
                filterColumn = 0
                filterText = ""
            } else if filterColumn >= document.columnCount {
                filterColumn = document.columnCount - 1
            }
            selectedColumns = selectedColumns.filter { $0 < document.columnCount }
            selectedDocumentRows = selectedDocumentRows.filter {
                $0 > 0 && $0 < document.rows.count
            }
            syncSelectionToDocument()
        }
        .onChange(of: selectedDocumentRows) { syncSelectionToDocument() }
        .onChange(of: selectedColumns) { syncSelectionToDocument() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard !providers.isEmpty else { return false }
            let collector = DroppedURLCollector(count: providers.count, completion: openURLs)
            for (index, provider) in providers.enumerated() {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    Task { @MainActor in
                        collector.receive(url, at: index)
                    }
                }
            }
            return true
        }
    }

    private var deleteRowsTitle: String {
        selectedDocumentRows.count > 1
            ? "Delete \(selectedDocumentRows.count) Rows"
            : "Delete Row"
    }

    private var deleteColumnsTitle: String {
        selectedColumns.count > 1
            ? "Delete \(selectedColumns.count) Columns"
            : "Delete Column"
    }

    private func deleteSelectedRows() {
        guard !selectedDocumentRows.isEmpty else { return }
        document.deleteRows(selectedDocumentRows)
        clearSelection()
    }

    private func deleteSelectedColumns() {
        guard !selectedColumns.isEmpty else { return }
        let deleted = selectedColumns
        document.deleteColumns(deleted)
        hiddenColumns = remappedColumnIndices(hiddenColumns, afterDeleting: deleted)
        if !deleted.contains(filterColumn) {
            filterColumn -= deleted.filter { $0 < filterColumn }.count
        } else if document.columnCount > 0 {
            filterColumn = min(filterColumn, document.columnCount - 1)
        } else {
            filterColumn = 0
        }
        clearSelection()
    }

    private func remappedColumnIndices(
        _ columns: Set<Int>,
        afterDeleting deleted: [Int]
    ) -> Set<Int> {
        let deletedSet = Set(deleted)
        return Set(columns.compactMap { column in
            guard !deletedSet.contains(column) else { return nil }
            return column - deletedSet.filter { $0 < column }.count
        })
    }

    private func clearSelection() {
        selectedDocumentRows = []
        selectedColumns = []
        syncSelectionToDocument()
    }

    private func syncSelectionToDocument() {
        document.selectedDocumentRowsForEditing = selectedDocumentRows
        document.selectedColumnsForEditing = selectedColumns
    }

    private func renameSelectedColumn() {
        guard selectedColumns.count == 1 else { return }
        let selectedColumn = selectedColumns[0]
        guard selectedColumn >= 0, selectedColumn < document.columnCount else { return }

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = document.value(row: 0, column: selectedColumn)
        input.placeholderString = "Column \(selectedColumn + 1)"

        let alert = NSAlert()
        alert.messageText = "Rename Column"
        alert.informativeText = "Enter the name for column \(selectedColumn + 1)."
        alert.alertStyle = .informational
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        document.setValue(input.stringValue, row: 0, column: selectedColumn)
    }

    private var matchingRowCount: Int {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, filterColumn < document.columnCount else {
            return document.dataRowCount
        }
        return document.rows.indices.dropFirst().filter { row in
            document.value(row: row, column: filterColumn).range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }.count
    }

    private var tableSummary: String {
        let rowSummary = filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(document.dataRowCount) rows"
            : "\(matchingRowCount) of \(document.dataRowCount) rows"
        let visibleColumns = max(document.columnCount - hiddenColumns.count, 0)
        let columnSummary = hiddenColumns.isEmpty
            ? "\(document.columnCount) columns"
            : "\(visibleColumns) of \(document.columnCount) columns"
        return "\(rowSummary)  •  \(columnSummary)"
    }

    private var statusIsError: Bool {
        document.status.localizedCaseInsensitiveContains("could not")
    }

    private var statusSymbol: String {
        if statusIsError { return "exclamationmark.triangle.fill" }
        if document.status.hasPrefix("Editing") { return "pencil" }
        if document.status.localizedCaseInsensitiveContains("disk") {
            return "arrow.triangle.2.circlepath"
        }
        return "checkmark.circle"
    }
}

private struct TableInspector: View {
    @ObservedObject var document: CSVDocument
    @Binding var hiddenColumns: Set<Int>
    @Binding var filterColumn: Int
    @Binding var filterText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filter")
                .font(.headline)

            if document.columnCount > 0 {
                Picker("Filter by", selection: $filterColumn) {
                    ForEach(0..<document.columnCount, id: \.self) { column in
                        Text(title(for: column)).tag(column)
                    }
                }
                .pickerStyle(.menu)

                NativeSearchField(text: $filterText)
                    .frame(height: 24)

                if !filterText.isEmpty {
                    Text("\(matchingRowCount) of \(document.dataRowCount) rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Columns")
                    .font(.headline)

                Spacer()

                Button("Show All") {
                    hiddenColumns.removeAll()
                }
                .disabled(hiddenColumns.isEmpty)
            }

            if document.columnCount == 0 {
                ContentUnavailableView("No Columns", systemImage: "rectangle.split.3x1")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<document.columnCount, id: \.self) { column in
                            Toggle(isOn: visibilityBinding(for: column)) {
                                Text(title(for: column))
                                    .lineLimit(1)
                                    .help(title(for: column))
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
    }

    private func visibilityBinding(for column: Int) -> Binding<Bool> {
        Binding(
            get: { !hiddenColumns.contains(column) },
            set: { isVisible in
                if isVisible {
                    hiddenColumns.remove(column)
                } else {
                    hiddenColumns.insert(column)
                }
            }
        )
    }

    private func title(for column: Int) -> String {
        let heading = document.value(row: 0, column: column)
        return heading.isEmpty ? "Column \(column + 1)" : heading
    }

    private var matchingRowCount: Int {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, filterColumn < document.columnCount else {
            return document.dataRowCount
        }
        return document.rows.indices.dropFirst().filter { row in
            document.value(row: row, column: filterColumn).range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }.count
    }
}

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Filter rows"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Filter rows")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

@MainActor
private final class DroppedURLCollector {
    private var urls: [URL?]
    private var remainingCount: Int
    private let completion: ([URL]) -> Void

    init(count: Int, completion: @escaping ([URL]) -> Void) {
        urls = Array(repeating: nil, count: count)
        remainingCount = count
        self.completion = completion
    }

    func receive(_ url: URL?, at index: Int) {
        guard urls.indices.contains(index), remainingCount > 0 else { return }
        urls[index] = url
        remainingCount -= 1
        if remainingCount == 0 {
            completion(urls.compactMap { $0 })
        }
    }
}

struct CSVTableView: NSViewRepresentable {
    @ObservedObject var document: CSVDocument
    @Binding var selectedDocumentRows: [Int]
    @Binding var selectedColumns: [Int]
    @Binding var hiddenColumns: Set<Int>
    @Binding var filterColumn: Int
    let filterText: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = SpreadsheetTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 30
        table.gridStyleMask = []
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.backgroundColor = .textBackgroundColor
        table.style = .plain

        let header = SpreadsheetHeaderView()
        header.renameHandler = { [weak coordinator = context.coordinator] column in
            coordinator?.promptToRenameHeader(column)
        }
        table.headerView = header

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        context.coordinator.tableView = table
        table.selectionHandler = { [weak coordinator = context.coordinator] rows, columns in
            coordinator?.updateSelection(visibleRows: rows, columns: columns)
        }
        table.editHandler = { [weak coordinator = context.coordinator] row, column, replacement in
            coordinator?.beginEditing(row: row, column: column, replacement: replacement)
        }
        table.clearHandler = { [weak coordinator = context.coordinator] rows, columns in
            coordinator?.clearCells(rows: rows, columns: columns)
        }
        table.copyHandler = { [weak coordinator = context.coordinator] rows, columns in
            coordinator?.copyValues(rows: rows, columns: columns) ?? ""
        }
        table.pasteHandler = { [weak coordinator = context.coordinator] rows, columns, text in
            coordinator?.paste(text, intoRows: rows, columns: columns)
        }
        table.deleteRowsHandler = { [weak coordinator = context.coordinator] rows in
            coordinator?.deleteRows(rows)
        }
        table.deleteColumnsHandler = { [weak coordinator = context.coordinator] columns in
            coordinator?.deleteColumns(columns)
        }
        context.coordinator.rebuildColumns()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = context.coordinator.tableView else { return }

        if table.numberOfColumns != document.columnCount + 1 {
            context.coordinator.rebuildColumns()
            return
        }

        if context.coordinator.lastHiddenColumns != hiddenColumns {
            context.coordinator.updateColumnVisibility()
        }

        if context.coordinator.lastFilterColumn != context.coordinator.parent.filterColumn
            || context.coordinator.lastFilterText != filterText {
            context.coordinator.reloadForFilterChange()
        }

        if context.coordinator.lastRevision != document.revision {
            context.coordinator.refreshDisplayedRows()
            context.coordinator.updateColumnTitlesAndWidths()
            (table as? SpreadsheetTableView)?.clearCellSelection()
            table.reloadData()
            context.coordinator.lastRevision = document.revision
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: CSVTableView
        weak var tableView: NSTableView?
        var lastRevision = -1
        var lastHiddenColumns: Set<Int> = []
        var lastFilterColumn: Int = 0
        var lastFilterText = ""
        private var displayedDocumentRows: [Int] = []
        private var sortColumn: Int?
        private var sortAscending = false

        init(_ parent: CSVTableView) { self.parent = parent }

        private var activeFilterColumn: Int? {
            parent.document.columnCount > 0 ? parent.filterColumn : nil
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            displayedDocumentRows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }

            guard let documentRow = documentRow(forVisibleRow: row) else { return nil }

            if tableColumn.identifier.rawValue == "rowNumber" {
                let identifier = NSUserInterfaceItemIdentifier("RowNumberCell")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? RowNumberCellView)
                    ?? RowNumberCellView(identifier: identifier)
                cell.number = documentRow + 1
                cell.isRangeSelected = (tableView as? SpreadsheetTableView)?.rowIsSelected(row) ?? false
                return cell
            }

            guard
                  let column = Int(tableColumn.identifier.rawValue.dropFirst()) else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("CSVCellContainer")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? CSVCellView)
                ?? CSVCellView(identifier: identifier)
            let field = cell.editor
            field.stringValue = parent.document.value(row: documentRow, column: column)
            field.tag = row * 100_000 + column
            field.delegate = self
            field.isEditable = false
            field.activationHandler = { [weak self] field, event in
                self?.handleCellClick(field, event: event) ?? false
            }
            if let spreadsheet = tableView as? SpreadsheetTableView {
                cell.isCellSelected = spreadsheet.selectionContains(row: row, column: column)
            }
            return cell
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let physicalColumn = tableView.tableColumns.firstIndex(of: tableColumn) else { return }
            if physicalColumn == 0 {
                resetSort()
            } else {
                toggleSort(column: physicalColumn - 1)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? CSVTextField else { return }
            field.isEditable = false
            field.isSelectable = false

            if field.isCancellingEdit {
                field.stringValue = field.originalValue
                field.isCancellingEdit = false
                return
            }

            let row = field.tag / 100_000
            let column = field.tag % 100_000
            guard let documentRow = documentRow(forVisibleRow: row) else { return }
            parent.document.setValue(field.stringValue, row: documentRow, column: column)
            refreshAfterMutation()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let field = control as? CSVTextField else { return false }
            let row = field.tag / 100_000
            let column = field.tag % 100_000

            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                finishEditing(field, moveToRow: row + 1, column: column)
                return true
            case #selector(NSResponder.insertTab(_:)):
                finishEditing(field, tabbingForwardFromRow: row, column: column)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                finishEditing(field, tabbingBackwardFromRow: row, column: column)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                field.isCancellingEdit = true
                field.window?.makeFirstResponder(tableView)
                moveSelection(toRow: row, column: column)
                return true
            default:
                return false
            }
        }

        private func moveSelection(toRow row: Int, column: Int) {
            guard let tableView = tableView as? SpreadsheetTableView,
                  row >= 0, row < displayedDocumentRows.count,
                  column >= 0, column < parent.document.columnCount else { return }

            tableView.selectCell(row: row, column: column)
            tableView.window?.makeFirstResponder(tableView)
        }

        func selectCell(row: Int, column: Int) {
            updateSelection(visibleRows: row...row, columns: column...column)
        }

        func updateSelection(visibleRows: ClosedRange<Int>?, columns: ClosedRange<Int>?) {
            if let visibleRows {
                parent.selectedDocumentRows = documentRows(forVisibleRows: visibleRows)
            } else {
                parent.selectedDocumentRows = []
            }
            parent.selectedColumns = columns.map(Array.init) ?? []
        }

        func beginEditing(row: Int, column: Int, replacement: String?) {
            guard let tableView = tableView as? SpreadsheetTableView,
                  let documentRow = documentRow(forVisibleRow: row),
                  column >= 0, column < parent.document.columnCount,
                  let cell = tableView.view(
                    atColumn: column + 1,
                    row: row,
                    makeIfNecessary: true
                  ) as? CSVCellView else { return }

            tableView.selectCell(row: row, column: column)
            let field = cell.editor
            field.originalValue = parent.document.value(row: documentRow, column: column)
            field.isEditable = true
            field.isSelectable = true

            if let replacement {
                field.stringValue = replacement
            }

            field.selectText(nil)
            if replacement != nil, let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
            }
        }

        func clearCells(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
            parent.document.pasteValues(
                [[""]],
                intoRows: documentRows(forVisibleRows: rows),
                column: columns.lowerBound,
                selectedColumnCount: columns.count
            )
            refreshAfterMutation()
        }

        func copyValues(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> String {
            let values = documentRows(forVisibleRows: rows).map { row in
                columns.map { column in
                    parent.document.value(row: row, column: column)
                }
            }
            return ClipboardGrid.encode(values)
        }

        func paste(
            _ text: String,
            intoRows rows: ClosedRange<Int>,
            columns: ClosedRange<Int>
        ) {
            let values = ClipboardGrid.decode(text)
            let targetHeight = max(values.count, rows.count)
            let lastVisibleRow = min(
                rows.lowerBound + targetHeight - 1,
                max(displayedDocumentRows.count - 1, 0)
            )
            let targetRows = displayedDocumentRows.isEmpty
                ? []
                : documentRows(forVisibleRows: rows.lowerBound...lastVisibleRow)
            parent.document.pasteValues(
                values,
                intoRows: targetRows,
                column: columns.lowerBound,
                selectedColumnCount: columns.count
            )
            refreshAfterMutation()
        }

        func deleteRows(_ visibleRows: ClosedRange<Int>) {
            let documentRows = documentRows(forVisibleRows: visibleRows)
            guard !documentRows.isEmpty else { return }
            parent.document.deleteRows(documentRows)
            parent.selectedDocumentRows = []
            parent.selectedColumns = []
            refreshAfterMutation()
        }

        func deleteColumns(_ columns: ClosedRange<Int>) {
            let columnIndices = Array(columns)
            guard !columnIndices.isEmpty else { return }
            let deletedSet = Set(columnIndices)
            parent.document.deleteColumns(columnIndices)
            parent.hiddenColumns = Set(parent.hiddenColumns.compactMap { column in
                guard !deletedSet.contains(column) else { return nil }
                return column - deletedSet.filter { $0 < column }.count
            })
            if deletedSet.contains(parent.filterColumn) {
                parent.filterColumn = max(min(parent.filterColumn, parent.document.columnCount - 1), 0)
            } else {
                parent.filterColumn -= deletedSet.filter { $0 < parent.filterColumn }.count
            }
            parent.selectedDocumentRows = []
            parent.selectedColumns = []
            refreshAfterMutation()
        }

        private func handleCellClick(_ field: CSVTextField, event: NSEvent) -> Bool {
            guard let tableView = tableView as? SpreadsheetTableView else { return false }
            let row = field.tag / 100_000
            let column = field.tag % 100_000

            if event.clickCount >= 2, !event.modifierFlags.contains(.shift) {
                beginEditing(row: row, column: column, replacement: nil)
                return false
            }

            tableView.selectCell(
                row: row,
                column: column,
                extending: event.modifierFlags.contains(.shift)
            )

            tableView.window?.makeFirstResponder(tableView)
            return false
        }

        private func finishEditing(_ field: CSVTextField, moveToRow row: Int, column: Int) {
            field.window?.makeFirstResponder(tableView)
            moveSelection(toRow: row, column: column)
        }

        private func finishEditing(
            _ field: CSVTextField,
            tabbingForwardFromRow row: Int,
            column: Int
        ) {
            field.window?.makeFirstResponder(tableView)
            guard let target = tabTarget(fromRow: row, column: column, forward: true) else { return }
            moveSelection(toRow: target.row, column: target.column)
        }

        private func finishEditing(
            _ field: CSVTextField,
            tabbingBackwardFromRow row: Int,
            column: Int
        ) {
            field.window?.makeFirstResponder(tableView)
            guard let target = tabTarget(fromRow: row, column: column, forward: false) else { return }
            moveSelection(toRow: target.row, column: target.column)
        }

        private func tabTarget(fromRow row: Int, column: Int, forward: Bool) -> (row: Int, column: Int)? {
            let visibleColumns = (0..<parent.document.columnCount).filter {
                !parent.hiddenColumns.contains($0)
            }
            guard !displayedDocumentRows.isEmpty, !visibleColumns.isEmpty else { return nil }

            let currentIndex = visibleColumns.firstIndex(of: column) ?? 0
            if forward {
                if currentIndex < visibleColumns.count - 1 {
                    return (row, visibleColumns[currentIndex + 1])
                }
                return (min(row + 1, displayedDocumentRows.count - 1), visibleColumns[0])
            }

            if currentIndex > 0 {
                return (row, visibleColumns[currentIndex - 1])
            }
            return (max(row - 1, 0), visibleColumns[visibleColumns.count - 1])
        }

        func setHeaderValue(_ value: String, for column: Int) {
            guard column >= 0, column < parent.document.columnCount else { return }
            parent.document.setValue(value, row: 0, column: column)
            lastRevision = parent.document.revision
            if let tableColumn = tableView?.tableColumns[column + 1] {
                setHeaderTitle(value.isEmpty ? "Column \(column + 1)" : value, for: tableColumn)
            }
        }

        func promptToRenameHeader(_ column: Int) {
            guard column >= 0, column < parent.document.columnCount else { return }
            parent.selectedColumns = [column]

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            input.stringValue = parent.document.value(row: 0, column: column)
            input.placeholderString = "Column \(column + 1)"

            let alert = NSAlert()
            alert.messageText = "Rename Column"
            alert.informativeText = "Enter the name for column \(column + 1)."
            alert.alertStyle = .informational
            alert.accessoryView = input
            alert.addButton(withTitle: "Rename")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = input

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            setHeaderValue(input.stringValue, for: column)
        }

        func refreshDisplayedRows() {
            if let sortColumn, sortColumn >= parent.document.columnCount {
                self.sortColumn = nil
                sortAscending = false
            }

            displayedDocumentRows = Array(parent.document.rows.indices.dropFirst())
            let query = parent.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let filterColumn = activeFilterColumn,
               filterColumn < parent.document.columnCount,
               !query.isEmpty {
                displayedDocumentRows = displayedDocumentRows.filter { row in
                    parent.document.value(row: row, column: filterColumn).range(
                        of: query,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) != nil
                }
            }
            if let sortColumn {
                displayedDocumentRows.sort { leftRow, rightRow in
                    let left = parent.document.value(row: leftRow, column: sortColumn)
                    let right = parent.document.value(row: rightRow, column: sortColumn)
                    let comparison = left.localizedStandardCompare(right)
                    if comparison == .orderedSame { return leftRow < rightRow }
                    return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }
            updateSortIndicators()
            lastFilterColumn = parent.filterColumn
            lastFilterText = parent.filterText
        }

        private func documentRow(forVisibleRow row: Int) -> Int? {
            guard displayedDocumentRows.indices.contains(row) else { return nil }
            return displayedDocumentRows[row]
        }

        private func documentRows(forVisibleRows rows: ClosedRange<Int>) -> [Int] {
            rows.compactMap(documentRow(forVisibleRow:))
        }

        private func toggleSort(column: Int) {
            guard column >= 0, column < parent.document.columnCount else { return }
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = false
            }
            reloadForSortChange()
        }

        private func resetSort() {
            sortColumn = nil
            sortAscending = false
            reloadForSortChange()
        }

        private func reloadForSortChange() {
            refreshDisplayedRows()
            (tableView as? SpreadsheetTableView)?.clearCellSelection()
            tableView?.reloadData()
        }

        func reloadForFilterChange() {
            refreshDisplayedRows()
            (tableView as? SpreadsheetTableView)?.clearCellSelection()
            tableView?.reloadData()
        }

        private func refreshAfterMutation() {
            lastRevision = parent.document.revision
            refreshDisplayedRows()
            (tableView as? SpreadsheetTableView)?.clearCellSelection()
            tableView?.reloadData()
        }

        private func updateSortIndicators() {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                tableView.setIndicatorImage(nil, in: column)
            }
            guard let sortColumn,
                  tableView.tableColumns.indices.contains(sortColumn + 1) else { return }
            let symbolName = sortAscending ? "chevron.up" : "chevron.down"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            tableView.setIndicatorImage(image, in: tableView.tableColumns[sortColumn + 1])
        }

        func rebuildColumns() {
            guard let tableView else { return }
            sortColumn = nil
            sortAscending = false
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let rowNumberColumn = NSTableColumn(identifier: .init("rowNumber"))
            setHeaderTitle("#", for: rowNumberColumn)
            rowNumberColumn.headerToolTip = "Restore original row order"
            rowNumberColumn.minWidth = 38
            rowNumberColumn.maxWidth = 38
            rowNumberColumn.width = 38
            rowNumberColumn.resizingMask = []
            tableView.addTableColumn(rowNumberColumn)

            for index in 0..<parent.document.columnCount {
                let column = NSTableColumn(identifier: .init("c\(index)"))
                setHeaderTitle(title(for: index), for: column)
                column.headerToolTip = "Click to sort; right-click to rename"
                column.minWidth = 60
                column.width = preferredWidth(for: index)
                column.resizingMask = .userResizingMask
                tableView.addTableColumn(column)
            }
            updateColumnVisibility()
            refreshDisplayedRows()
            tableView.reloadData()
            lastRevision = parent.document.revision
        }

        func updateColumnVisibility() {
            guard let tableView else { return }
            for (index, column) in tableView.tableColumns.dropFirst().enumerated() {
                column.isHidden = parent.hiddenColumns.contains(index)
            }
            if let spreadsheet = tableView as? SpreadsheetTableView {
                spreadsheet.hiddenDataColumns = parent.hiddenColumns
            }
            lastHiddenColumns = parent.hiddenColumns
        }

        func updateColumnTitlesAndWidths() {
            guard let tableView else { return }
            for (index, column) in tableView.tableColumns.dropFirst().enumerated() {
                setHeaderTitle(title(for: index), for: column)
                column.width = max(column.width, preferredWidth(for: index))
            }
        }

        private func setHeaderTitle(_ title: String, for column: NSTableColumn) {
            column.headerCell.attributedStringValue = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize + 0.5, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        }

        private func title(for column: Int) -> String {
            let header = parent.document.value(row: 0, column: column)
            return header.isEmpty ? "Column \(column + 1)" : header
        }

        private func preferredWidth(for column: Int) -> CGFloat {
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let values = parent.document.rows.map { row in
                row.indices.contains(column) ? row[column] : ""
            } + [title(for: column)]
            let widest = values.map {
                ($0 as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 60
            return max(80, ceil(widest) + 28)
        }

    }
}

private enum ClipboardGrid {
    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: "\t") }
            .joined(separator: "\n")
    }

    static func decode(_ text: String) -> [[String]] {
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == "\t", !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !quoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty || rows.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func escape(_ value: String) -> String {
        guard value.contains("\t") || value.contains("\n") || value.contains("\r") || value.contains("\"") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

@MainActor
private final class SpreadsheetHeaderView: NSTableHeaderView {
    var renameHandler: ((Int) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let physicalColumn = column(at: location)
        guard physicalColumn > 0 else {
            super.rightMouseDown(with: event)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.renameHandler?(physicalColumn - 1)
        }
    }
}

@MainActor
private final class SpreadsheetTableView: NSTableView {
    var selectionHandler: ((ClosedRange<Int>?, ClosedRange<Int>?) -> Void)?
    var editHandler: ((Int, Int, String?) -> Void)?
    var clearHandler: ((ClosedRange<Int>, ClosedRange<Int>) -> Void)?
    var copyHandler: ((ClosedRange<Int>, ClosedRange<Int>) -> String)?
    var pasteHandler: ((ClosedRange<Int>, ClosedRange<Int>, String) -> Void)?
    var deleteRowsHandler: ((ClosedRange<Int>) -> Void)?
    var deleteColumnsHandler: ((ClosedRange<Int>) -> Void)?
    private(set) var selectedCellRow = -1
    private(set) var selectedCellColumn = -1
    private var anchorRow = -1
    private var anchorColumn = -1
    var hiddenDataColumns: Set<Int> = [] {
        didSet {
            if hiddenDataColumns.contains(selectedCellColumn) {
                clearCellSelection()
            }
        }
    }

    var selectedRows: ClosedRange<Int> {
        min(anchorRow, selectedCellRow)...max(anchorRow, selectedCellRow)
    }

    var selectedColumns: ClosedRange<Int> {
        min(anchorColumn, selectedCellColumn)...max(anchorColumn, selectedCellColumn)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: location)
        let physicalColumn = column(at: location)
        guard clickedRow >= 0 else {
            super.mouseDown(with: event)
            return
        }

        let extending = event.modifierFlags.contains(.shift)

        // Click the row-number gutter to select entire rows.
        if physicalColumn == 0 {
            selectEntireRows(around: clickedRow, extending: extending)
            window?.makeFirstResponder(self)
            return
        }

        guard physicalColumn > 0 else {
            super.mouseDown(with: event)
            return
        }

        let dataColumn = physicalColumn - 1
        selectCell(
            row: clickedRow,
            column: dataColumn,
            extending: extending
        )
        window?.makeFirstResponder(self)

        if event.clickCount >= 2, !extending {
            editHandler?(clickedRow, dataColumn, nil)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: location)
        let physicalColumn = column(at: location)
        guard clickedRow >= 0, physicalColumn >= 0 else {
            return super.menu(for: event)
        }

        if physicalColumn == 0 {
            if !rowIsSelected(clickedRow) {
                selectEntireRows(around: clickedRow, extending: false)
            }
        } else {
            let dataColumn = physicalColumn - 1
            if !selectionContains(row: clickedRow, column: dataColumn) {
                selectCell(row: clickedRow, column: dataColumn)
            }
        }
        window?.makeFirstResponder(self)

        let menu = NSMenu()
        menu.autoenablesItems = false
        let hasSelection = selectedCellRow >= 0 && selectedCellColumn >= 0

        let copyItem = menu.addItem(
            withTitle: "Copy",
            action: #selector(copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target = self
        copyItem.isEnabled = hasSelection

        let pasteItem = menu.addItem(
            withTitle: "Paste",
            action: #selector(paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = .command
        pasteItem.target = self
        pasteItem.isEnabled = hasSelection
            && NSPasteboard.general.string(forType: .string) != nil

        menu.addItem(.separator())

        let clearItem = menu.addItem(
            withTitle: "Clear Contents",
            action: #selector(clearContents(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = hasSelection

        menu.addItem(.separator())

        let rowCount = hasSelection ? selectedRows.count : 0
        let columnCount = hasSelection ? selectedColumns.count : 0

        let deleteRowsItem = menu.addItem(
            withTitle: rowCount > 1 ? "Delete \(rowCount) Rows" : "Delete Row",
            action: #selector(deleteSelectedRows(_:)),
            keyEquivalent: ""
        )
        deleteRowsItem.target = self
        deleteRowsItem.isEnabled = hasSelection

        let deleteColumnsItem = menu.addItem(
            withTitle: columnCount > 1 ? "Delete \(columnCount) Columns" : "Delete Column",
            action: #selector(deleteSelectedColumns(_:)),
            keyEquivalent: ""
        )
        deleteColumnsItem.target = self
        deleteColumnsItem.isEnabled = hasSelection

        return menu
    }

    func selectionContains(row: Int, column: Int) -> Bool {
        guard anchorRow >= 0, anchorColumn >= 0,
              selectedCellRow >= 0, selectedCellColumn >= 0 else { return false }
        return selectedRows.contains(row) && selectedColumns.contains(column)
    }

    func rowIsSelected(_ row: Int) -> Bool {
        anchorRow >= 0 && selectedCellRow >= 0 && selectedRows.contains(row)
    }

    func selectCell(row: Int, column: Int, extending: Bool = false) {
        guard row >= 0, row < numberOfRows,
              column >= 0, column < max(numberOfColumns - 1, 0),
              !hiddenDataColumns.contains(column) else { return }

        setSelectionAppearance(false)
        if !extending || anchorRow < 0 || anchorColumn < 0 {
            anchorRow = row
            anchorColumn = column
        }
        selectedCellRow = row
        selectedCellColumn = column
        setSelectionAppearance(true)
        scrollRowToVisible(row)
        scrollColumnToVisible(column + 1)
        notifySelectionChanged()
    }

    func selectEntireRows(around row: Int, extending: Bool) {
        let visibleColumns = (0..<max(numberOfColumns - 1, 0)).filter {
            !hiddenDataColumns.contains($0)
        }
        guard row >= 0, row < numberOfRows,
              let first = visibleColumns.first,
              let last = visibleColumns.last else { return }

        setSelectionAppearance(false)
        if !extending || anchorRow < 0 || anchorColumn < 0 {
            anchorRow = row
            anchorColumn = first
        }
        selectedCellRow = row
        selectedCellColumn = last
        setSelectionAppearance(true)
        scrollRowToVisible(row)
        notifySelectionChanged()
    }

    func clearCellSelection() {
        setSelectionAppearance(false)
        selectedCellRow = -1
        selectedCellColumn = -1
        anchorRow = -1
        anchorColumn = -1
        selectionHandler?(nil, nil)
    }

    private func notifySelectionChanged() {
        guard selectedCellRow >= 0, selectedCellColumn >= 0 else {
            selectionHandler?(nil, nil)
            return
        }
        selectionHandler?(selectedRows, selectedColumns)
    }

    override func keyDown(with event: NSEvent) {
        if selectedCellRow < 0 || selectedCellColumn < 0 {
            selectCell(row: 0, column: 0)
        }

        if event.modifierFlags.contains(.command),
           let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "c" {
                copySelection()
                return
            }
            if key == "v" {
                pasteSelection()
                return
            }
        }

        if event.keyCode == 48 {
            moveSelectionByTab(forward: !event.modifierFlags.contains(.shift))
            return
        }

        let movement: (row: Int, column: Int)? = switch event.keyCode {
        case 126: (-1, 0) // Up
        case 125: (1, 0)  // Down
        case 123: (0, -1) // Left
        case 124: (0, 1)  // Right
        default: nil
        }

        if let movement {
            let extending = event.modifierFlags.contains(.shift) && event.keyCode != 48
            moveSelection(
                rowDelta: movement.row,
                columnDelta: movement.column,
                extending: extending
            )
            return
        }

        switch event.keyCode {
        case 36, 76: // Return and keypad Enter
            editHandler?(selectedCellRow, selectedCellColumn, nil)
        case 51, 117: // Delete and forward delete
            if event.modifierFlags.contains(.command) {
                if event.modifierFlags.contains(.option) {
                    deleteColumnsHandler?(selectedColumns)
                } else {
                    deleteRowsHandler?(selectedRows)
                }
            } else {
                clearHandler?(selectedRows, selectedColumns)
            }
        default:
            guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                  let characters = event.characters,
                  !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !$0.properties.isControl }) else {
                super.keyDown(with: event)
                return
            }
            editHandler?(selectedCellRow, selectedCellColumn, characters)
        }
    }

    private func moveSelection(rowDelta: Int, columnDelta: Int, extending: Bool) {
        let visibleColumns = (0..<max(numberOfColumns - 1, 0)).filter {
            !hiddenDataColumns.contains($0)
        }
        guard numberOfRows > 0, !visibleColumns.isEmpty else { return }
        let row = min(max(selectedCellRow + rowDelta, 0), numberOfRows - 1)
        let currentIndex = visibleColumns.firstIndex(of: selectedCellColumn) ?? 0
        let columnIndex = min(max(currentIndex + columnDelta, 0), visibleColumns.count - 1)
        let column = visibleColumns[columnIndex]
        selectCell(row: row, column: column, extending: extending)
    }

    private func moveSelectionByTab(forward: Bool) {
        let visibleColumns = (0..<max(numberOfColumns - 1, 0)).filter {
            !hiddenDataColumns.contains($0)
        }
        guard numberOfRows > 0, !visibleColumns.isEmpty else { return }

        let currentIndex = visibleColumns.firstIndex(of: selectedCellColumn) ?? 0
        if forward {
            if currentIndex < visibleColumns.count - 1 {
                selectCell(row: selectedCellRow, column: visibleColumns[currentIndex + 1])
            } else {
                selectCell(
                    row: min(selectedCellRow + 1, numberOfRows - 1),
                    column: visibleColumns[0]
                )
            }
        } else if currentIndex > 0 {
            selectCell(row: selectedCellRow, column: visibleColumns[currentIndex - 1])
        } else {
            selectCell(
                row: max(selectedCellRow - 1, 0),
                column: visibleColumns[visibleColumns.count - 1]
            )
        }
    }

    private func setSelectionAppearance(_ selected: Bool) {
        guard anchorRow >= 0, anchorColumn >= 0,
              selectedCellRow >= 0, selectedCellColumn >= 0 else { return }

        for row in selectedRows {
            if let gutter = view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? RowNumberCellView {
                gutter.isRangeSelected = selected
            }
            for column in selectedColumns {
                if let cell = view(
                    atColumn: column + 1,
                    row: row,
                    makeIfNecessary: false
                ) as? CSVCellView {
                    cell.isCellSelected = selected
                }
            }
        }
    }

    @objc func copy(_ sender: Any?) {
        copySelection()
    }

    @objc func paste(_ sender: Any?) {
        pasteSelection()
    }

    @objc private func clearContents(_ sender: Any?) {
        guard selectedCellRow >= 0, selectedCellColumn >= 0 else { return }
        clearHandler?(selectedRows, selectedColumns)
    }

    @objc private func deleteSelectedRows(_ sender: Any?) {
        guard selectedCellRow >= 0 else { return }
        deleteRowsHandler?(selectedRows)
    }

    @objc private func deleteSelectedColumns(_ sender: Any?) {
        guard selectedCellColumn >= 0 else { return }
        deleteColumnsHandler?(selectedColumns)
    }

    private func copySelection() {
        guard selectedCellRow >= 0, selectedCellColumn >= 0 else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            copyHandler?(selectedRows, selectedColumns) ?? "",
            forType: .string
        )
    }

    private func pasteSelection() {
        guard selectedCellRow >= 0, selectedCellColumn >= 0,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        pasteHandler?(selectedRows, selectedColumns, text)
    }
}

private extension Unicode.Scalar.Properties {
    var isControl: Bool {
        generalCategory == .control
    }
}

@MainActor
private final class RowNumberCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    var isRangeSelected = false {
        didSet {
            label.textColor = isRangeSelected ? .controlAccentColor : .secondaryLabelColor
            needsDisplay = true
        }
    }

    var number = 0 {
        didSet { label.stringValue = String(number) }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        (isRangeSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.windowBackgroundColor).setFill()
        bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        edge.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        edge.stroke()
        super.draw(dirtyRect)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class CSVCellView: NSTableCellView {
    let editor = CSVTextField()
    var isCellSelected = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isCellSelected else { return }

        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        bounds.fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if editor.activationHandler?(editor, event) == true {
            editor.selectText(nil)
        }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        editor.identifier = .init("CSVCell")
        editor.isEditable = false
        editor.isSelectable = false
        editor.isBordered = false
        editor.isBezeled = false
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.lineBreakMode = .byClipping
        editor.usesSingleLineMode = true
        editor.cell?.isScrollable = true
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.translatesAutoresizingMaskIntoConstraints = false

        addSubview(editor)
        textField = editor
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            editor.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            editor.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class CSVTextField: NSTextField {
    var activationHandler: ((CSVTextField, NSEvent) -> Bool)?
    var originalValue = ""
    var isCancellingEdit = false

    override func mouseDown(with event: NSEvent) {
        if activationHandler?(self, event) == true {
            super.mouseDown(with: event)
        } else {
            // A single click selects the cell. A double-click is forwarded to
            // NSTextField above so it can place the insertion point naturally.
        }
    }
}
