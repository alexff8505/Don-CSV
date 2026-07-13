import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: CSVDocument
    @State private var selectedRow = -1
    @State private var selectedColumn = -1

    var body: some View {
        VStack(spacing: 0) {
            if document.fileURL == nil {
                ContentUnavailableView {
                    Label("No CSV Open", systemImage: "tablecells")
                } description: {
                    Text("Open a comma-separated values file to view and edit it.")
                } actions: {
                    Button("Open CSV…") { document.open() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                CSVTableView(
                    document: document,
                    selectedRow: $selectedRow,
                    selectedColumn: $selectedColumn
                )
                .id(document.fileURL)
            }

            Divider()

            HStack(spacing: 12) {
                Label(document.status, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if document.fileURL != nil {
                    Text("\(max(document.rows.count - 1, 0)) data rows  •  \(document.columnCount) columns")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { document.open() } label: {
                    Label("Open", systemImage: "folder")
                }

                Button { document.saveNow() } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(document.fileURL == nil)

                Divider()

                Button { document.addRow() } label: {
                    Label("Add Row", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(document.fileURL == nil)

                Button { document.addColumn() } label: {
                    Label("Add Column", systemImage: "rectangle.split.3x1")
                }
                .disabled(document.fileURL == nil)

                Button { renameSelectedColumn() } label: {
                    Label("Rename Column", systemImage: "pencil")
                }
                .disabled(selectedColumn < 0 || selectedColumn >= document.columnCount)

                Button {
                    if selectedRow >= 0 { document.deleteRow(selectedRow + 1); selectedRow = -1 }
                } label: {
                    Label("Delete Row", systemImage: "minus")
                }
                .disabled(selectedRow < 0 || selectedRow >= document.dataRowCount)

                Button {
                    if selectedColumn >= 0 { document.deleteColumn(selectedColumn); selectedColumn = -1 }
                } label: {
                    Label("Delete Column", systemImage: "rectangle.split.1x2")
                }
                .disabled(selectedColumn < 0 || selectedColumn >= document.columnCount)
            }
        }
        .navigationTitle(document.fileURL?.lastPathComponent ?? "Don CSV")
        .onChange(of: document.fileURL) {
            selectedRow = -1
            selectedColumn = -1
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in document.load(url) }
            }
            return true
        }
    }

    private func renameSelectedColumn() {
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
}

struct CSVTableView: NSViewRepresentable {
    @ObservedObject var document: CSVDocument
    @Binding var selectedRow: Int
    @Binding var selectedColumn: Int

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

        table.headerView = NSTableHeaderView()

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        context.coordinator.tableView = table
        table.selectionHandler = { [weak coordinator = context.coordinator] row, column in
            coordinator?.selectCell(row: row, column: column)
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
        context.coordinator.rebuildColumns()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = context.coordinator.tableView else { return }

        if table.numberOfColumns != document.columnCount + 1 {
            context.coordinator.rebuildColumns()
        } else if context.coordinator.lastRevision != document.revision {
            context.coordinator.updateColumnTitlesAndWidths()
            table.reloadData()
            context.coordinator.lastRevision = document.revision
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: CSVTableView
        weak var tableView: NSTableView?
        var lastRevision = -1

        init(_ parent: CSVTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int {
            max(parent.document.rows.count - 1, 0)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }

            if tableColumn.identifier.rawValue == "rowNumber" {
                let identifier = NSUserInterfaceItemIdentifier("RowNumberCell")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? RowNumberCellView)
                    ?? RowNumberCellView(identifier: identifier)
                cell.number = row + 2
                cell.isRangeSelected = (tableView as? SpreadsheetTableView)?.rowIsSelected(row) ?? false
                return cell
            }

            guard
                  let column = Int(tableColumn.identifier.rawValue.dropFirst()) else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("CSVCellContainer")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? CSVCellView)
                ?? CSVCellView(identifier: identifier)
            let field = cell.editor
            field.stringValue = parent.document.value(row: row + 1, column: column)
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
            guard let physicalColumn = tableView.tableColumns.firstIndex(of: tableColumn),
                  physicalColumn > 0 else { return }
            let dataColumn = physicalColumn - 1
            parent.selectedColumn = dataColumn
            DispatchQueue.main.async { [weak self] in
                self?.promptToRenameHeader(dataColumn)
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
            parent.document.setValue(field.stringValue, row: row + 1, column: column)
            lastRevision = parent.document.revision
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
                finishEditing(field, moveToRow: row, column: column + 1)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                finishEditing(field, moveToRow: row, column: column - 1)
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
                  row >= 0, row < max(parent.document.rows.count - 1, 0),
                  column >= 0, column < parent.document.columnCount else { return }

            tableView.selectCell(row: row, column: column)
            tableView.window?.makeFirstResponder(tableView)
        }

        func selectCell(row: Int, column: Int) {
            parent.selectedRow = row
            parent.selectedColumn = column
        }

        func beginEditing(row: Int, column: Int, replacement: String?) {
            guard let tableView = tableView as? SpreadsheetTableView,
                  row >= 0, row < max(parent.document.rows.count - 1, 0),
                  column >= 0, column < parent.document.columnCount,
                  let cell = tableView.view(
                    atColumn: column + 1,
                    row: row,
                    makeIfNecessary: true
                  ) as? CSVCellView else { return }

            tableView.selectCell(row: row, column: column)
            let field = cell.editor
            field.originalValue = parent.document.value(row: row + 1, column: column)
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
                startingAtRow: rows.lowerBound + 1,
                column: columns.lowerBound,
                selectedRowCount: rows.count,
                selectedColumnCount: columns.count
            )
        }

        func copyValues(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> String {
            let values = rows.map { row in
                columns.map { column in
                    parent.document.value(row: row + 1, column: column)
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
            parent.document.pasteValues(
                values,
                startingAtRow: rows.lowerBound + 1,
                column: columns.lowerBound,
                selectedRowCount: rows.count,
                selectedColumnCount: columns.count
            )
        }

        private func handleCellClick(_ field: CSVTextField, event: NSEvent) -> Bool {
            guard let tableView = tableView as? SpreadsheetTableView else { return false }
            let row = field.tag / 100_000
            let column = field.tag % 100_000
            tableView.selectCell(
                row: row,
                column: column,
                extending: event.modifierFlags.contains(.shift)
            )

            if event.clickCount >= 2, !event.modifierFlags.contains(.shift) {
                field.originalValue = parent.document.value(row: row + 1, column: column)
                field.isEditable = true
                field.isSelectable = true
                return true
            }

            tableView.window?.makeFirstResponder(tableView)
            return false
        }

        private func finishEditing(_ field: CSVTextField, moveToRow row: Int, column: Int) {
            field.window?.makeFirstResponder(tableView)
            moveSelection(toRow: row, column: column)
        }

        func setHeaderValue(_ value: String, for column: Int) {
            guard column >= 0, column < parent.document.columnCount else { return }
            parent.document.setValue(value, row: 0, column: column)
            lastRevision = parent.document.revision
            tableView?.tableColumns[column + 1].title = value.isEmpty ? "Column \(column + 1)" : value
        }

        private func promptToRenameHeader(_ column: Int) {
            guard column >= 0, column < parent.document.columnCount else { return }

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

        func rebuildColumns() {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let rowNumberColumn = NSTableColumn(identifier: .init("rowNumber"))
            rowNumberColumn.title = ""
            rowNumberColumn.minWidth = 38
            rowNumberColumn.maxWidth = 38
            rowNumberColumn.width = 38
            rowNumberColumn.resizingMask = []
            tableView.addTableColumn(rowNumberColumn)

            for index in 0..<parent.document.columnCount {
                let column = NSTableColumn(identifier: .init("c\(index)"))
                column.title = title(for: index)
                column.headerToolTip = "Click to rename"
                column.minWidth = 60
                column.width = preferredWidth(for: index)
                column.resizingMask = .userResizingMask
                tableView.addTableColumn(column)
            }
            tableView.reloadData()
            lastRevision = parent.document.revision
        }

        func updateColumnTitlesAndWidths() {
            guard let tableView else { return }
            for (index, column) in tableView.tableColumns.dropFirst().enumerated() {
                column.title = title(for: index)
                column.width = max(column.width, preferredWidth(for: index))
            }
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
private final class SpreadsheetTableView: NSTableView {
    var selectionHandler: ((Int, Int) -> Void)?
    var editHandler: ((Int, Int, String?) -> Void)?
    var clearHandler: ((ClosedRange<Int>, ClosedRange<Int>) -> Void)?
    var copyHandler: ((ClosedRange<Int>, ClosedRange<Int>) -> String)?
    var pasteHandler: ((ClosedRange<Int>, ClosedRange<Int>, String) -> Void)?
    private(set) var selectedCellRow = -1
    private(set) var selectedCellColumn = -1
    private var anchorRow = -1
    private var anchorColumn = -1

    var selectedRows: ClosedRange<Int> {
        min(anchorRow, selectedCellRow)...max(anchorRow, selectedCellRow)
    }

    var selectedColumns: ClosedRange<Int> {
        min(anchorColumn, selectedCellColumn)...max(anchorColumn, selectedCellColumn)
    }

    override var acceptsFirstResponder: Bool { true }

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
              column >= 0, column < max(numberOfColumns - 1, 0) else { return }

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
        selectionHandler?(row, column)
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

        let movement: (row: Int, column: Int)? = switch event.keyCode {
        case 126: (-1, 0) // Up
        case 125: (1, 0)  // Down
        case 123: (0, -1) // Left
        case 124: (0, 1)  // Right
        case 48 where event.modifierFlags.contains(.shift): (0, -1) // Shift-Tab
        case 48: (0, 1) // Tab
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
            clearHandler?(selectedRows, selectedColumns)
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
        let dataColumnCount = max(numberOfColumns - 1, 0)
        guard numberOfRows > 0, dataColumnCount > 0 else { return }
        let row = min(max(selectedCellRow + rowDelta, 0), numberOfRows - 1)
        let column = min(max(selectedCellColumn + columnDelta, 0), dataColumnCount - 1)
        selectCell(row: row, column: column, extending: extending)
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
