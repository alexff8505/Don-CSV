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
            }

            Divider()

            HStack(spacing: 12) {
                Label(document.status, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if document.fileURL != nil {
                    Text("\(document.rows.count) rows  •  \(document.columnCount) columns")
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

                Button {
                    if selectedRow >= 0 { document.deleteRow(selectedRow); selectedRow = -1 }
                } label: {
                    Label("Delete Row", systemImage: "minus")
                }
                .disabled(selectedRow < 0)

                Button {
                    if selectedColumn >= 0 { document.deleteColumn(selectedColumn); selectedColumn = -1 }
                } label: {
                    Label("Delete Column", systemImage: "rectangle.split.1x2")
                }
                .disabled(selectedColumn < 0)
            }
        }
        .navigationTitle(document.fileURL?.lastPathComponent ?? "Don CSV")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in document.load(url) }
            }
            return true
        }
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
        table.clearHandler = { [weak coordinator = context.coordinator] row, column in
            coordinator?.clearCell(row: row, column: column)
        }
        context.coordinator.rebuildColumns()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = context.coordinator.tableView else { return }

        if table.numberOfColumns != document.columnCount {
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
            parent.document.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn,
                  let column = Int(tableColumn.identifier.rawValue.dropFirst()) else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("CSVCellContainer")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? CSVCellView)
                ?? CSVCellView(identifier: identifier)
            let field = cell.editor
            field.stringValue = parent.document.value(row: row, column: column)
            field.tag = row * 100_000 + column
            field.delegate = self
            field.isEditable = false
            field.activationHandler = { [weak self] field, event in
                self?.handleCellClick(field, event: event) ?? false
            }
            if let spreadsheet = tableView as? SpreadsheetTableView {
                cell.isCellSelected = spreadsheet.selectedCellRow == row
                    && spreadsheet.selectedCellColumn == column
            }
            return cell
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            parent.selectedColumn = tableView.tableColumns.firstIndex(of: tableColumn) ?? -1
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
            parent.document.setValue(field.stringValue, row: row, column: column)
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
                  row >= 0, row < parent.document.rows.count,
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
                  row >= 0, row < parent.document.rows.count,
                  column >= 0, column < parent.document.columnCount,
                  let cell = tableView.view(
                    atColumn: column,
                    row: row,
                    makeIfNecessary: true
                  ) as? CSVCellView else { return }

            tableView.selectCell(row: row, column: column)
            let field = cell.editor
            field.originalValue = parent.document.value(row: row, column: column)
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

        func clearCell(row: Int, column: Int) {
            parent.document.setValue("", row: row, column: column)
            lastRevision = parent.document.revision
            if let cell = tableView?.view(
                atColumn: column,
                row: row,
                makeIfNecessary: true
            ) as? CSVCellView {
                cell.editor.stringValue = ""
            }
        }

        private func handleCellClick(_ field: CSVTextField, event: NSEvent) -> Bool {
            guard let tableView = tableView as? SpreadsheetTableView else { return false }
            let row = field.tag / 100_000
            let column = field.tag % 100_000
            tableView.selectCell(row: row, column: column)

            if event.clickCount >= 2 {
                field.originalValue = parent.document.value(row: row, column: column)
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

        func rebuildColumns() {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            for index in 0..<parent.document.columnCount {
                let column = NSTableColumn(identifier: .init("c\(index)"))
                column.title = title(for: index)
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
            for (index, column) in tableView.tableColumns.enumerated() {
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

@MainActor
private final class SpreadsheetTableView: NSTableView {
    var selectionHandler: ((Int, Int) -> Void)?
    var editHandler: ((Int, Int, String?) -> Void)?
    var clearHandler: ((Int, Int) -> Void)?
    private(set) var selectedCellRow = -1
    private(set) var selectedCellColumn = -1

    override var acceptsFirstResponder: Bool { true }

    func selectCell(row: Int, column: Int) {
        guard row >= 0, row < numberOfRows, column >= 0, column < numberOfColumns else { return }

        setSelectionAppearance(false, row: selectedCellRow, column: selectedCellColumn)
        selectedCellRow = row
        selectedCellColumn = column
        setSelectionAppearance(true, row: row, column: column)
        scrollRowToVisible(row)
        scrollColumnToVisible(column)
        selectionHandler?(row, column)
    }

    override func keyDown(with event: NSEvent) {
        if selectedCellRow < 0 || selectedCellColumn < 0 {
            selectCell(row: 0, column: 0)
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
            moveSelection(rowDelta: movement.row, columnDelta: movement.column)
            return
        }

        switch event.keyCode {
        case 36, 76: // Return and keypad Enter
            editHandler?(selectedCellRow, selectedCellColumn, nil)
        case 51, 117: // Delete and forward delete
            clearHandler?(selectedCellRow, selectedCellColumn)
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

    private func moveSelection(rowDelta: Int, columnDelta: Int) {
        guard numberOfRows > 0, numberOfColumns > 0 else { return }
        let row = min(max(selectedCellRow + rowDelta, 0), numberOfRows - 1)
        let column = min(max(selectedCellColumn + columnDelta, 0), numberOfColumns - 1)
        selectCell(row: row, column: column)
    }

    private func setSelectionAppearance(_ selected: Bool, row: Int, column: Int) {
        guard row >= 0, column >= 0,
              let cell = view(atColumn: column, row: row, makeIfNecessary: false) as? CSVCellView else {
            return
        }
        cell.isCellSelected = selected
    }
}

private extension Unicode.Scalar.Properties {
    var isControl: Bool {
        generalCategory == .control
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
