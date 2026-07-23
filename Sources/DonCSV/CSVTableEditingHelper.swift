import Foundation

@MainActor
final class CSVTableEditingHelper: ObservableObject {
    private struct ColumnPresentation {
        let hiddenColumns: Set<Int>
        let filterColumn: Int
        let filterText: String
    }

    @Published var selectedDocumentRows: [Int] = []
    @Published var selectedColumns: [Int] = []
    @Published var hiddenColumns: Set<Int> = []
    @Published var filterColumn = 0
    @Published var filterText = ""

    func reset() {
        clearSelection()
        hiddenColumns.removeAll()
        filterColumn = 0
        filterText = ""
    }

    func reconcile(with document: CSVDocument) {
        hiddenColumns = hiddenColumns.filter { $0 >= 0 && $0 < document.columnCount }
        selectedColumns = selectedColumns.filter { $0 >= 0 && $0 < document.columnCount }
        selectedDocumentRows = selectedDocumentRows.filter {
            $0 > 0 && $0 < document.rows.count
        }

        if document.columnCount == 0 {
            filterColumn = 0
            filterText = ""
        } else {
            filterColumn = min(max(filterColumn, 0), document.columnCount - 1)
        }
    }

    func clearSelection() {
        selectedDocumentRows.removeAll()
        selectedColumns.removeAll()
    }

    func deleteSelectedRows(from document: CSVDocument) {
        deleteRows(selectedDocumentRows, from: document)
    }

    func deleteRows(_ indices: [Int], from document: CSVDocument) {
        let validIndices = Set(indices)
            .filter { $0 > 0 && $0 < document.rows.count }
            .sorted(by: >)
        guard !validIndices.isEmpty else { return }

        document.deleteRows(validIndices)
        clearSelection()
    }

    func deleteSelectedColumns(from document: CSVDocument) {
        deleteColumns(selectedColumns, from: document)
    }

    func deleteColumns(_ indices: [Int], from document: CSVDocument) {
        let validIndices = Set(indices)
            .filter { $0 >= 0 && $0 < document.columnCount }
            .sorted()
        guard !validIndices.isEmpty else { return }

        let previousPresentation = columnPresentation
        let actionName = validIndices.count == 1 ? "Delete Column" : "Delete Columns"
        document.undoManager.beginUndoGrouping()
        document.deleteColumns(validIndices)

        let deleted = Set(validIndices)
        hiddenColumns = remap(hiddenColumns, afterDeleting: deleted)
        if deleted.contains(filterColumn) {
            filterColumn = max(min(filterColumn, document.columnCount - 1), 0)
        } else {
            filterColumn -= deleted.filter { $0 < filterColumn }.count
        }
        clearSelection()
        reconcile(with: document)
        registerUndo(
            restoring: previousPresentation,
            with: document.undoManager,
            actionName: actionName
        )
        document.undoManager.endUndoGrouping()
        document.undoManager.setActionName(actionName)
    }

    private var columnPresentation: ColumnPresentation {
        ColumnPresentation(
            hiddenColumns: hiddenColumns,
            filterColumn: filterColumn,
            filterText: filterText
        )
    }

    private func registerUndo(
        restoring presentation: ColumnPresentation,
        with undoManager: UndoManager,
        actionName: String
    ) {
        undoManager.registerUndo(withTarget: self) { [weak undoManager] helper in
            guard let undoManager else { return }
            MainActor.assumeIsolated {
                let currentPresentation = helper.columnPresentation
                helper.restore(presentation)
                helper.registerUndo(
                    restoring: currentPresentation,
                    with: undoManager,
                    actionName: actionName
                )
            }
        }
        undoManager.setActionName(actionName)
    }

    private func restore(_ presentation: ColumnPresentation) {
        hiddenColumns = presentation.hiddenColumns
        filterColumn = presentation.filterColumn
        filterText = presentation.filterText
        clearSelection()
    }

    private func remap(
        _ columns: Set<Int>,
        afterDeleting deleted: Set<Int>
    ) -> Set<Int> {
        Set(columns.compactMap { column in
            guard !deleted.contains(column) else { return nil }
            return column - deleted.filter { $0 < column }.count
        })
    }
}
