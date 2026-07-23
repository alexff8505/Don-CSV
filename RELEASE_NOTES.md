# Don CSV Release Notes

## Version 1.3 — 23 July 2026

### Multi-row and multi-column editing

- Select rectangular ranges with Shift-click or Shift-arrow navigation.
- Select one or more complete rows from the numbered `#` gutter.
- Delete every selected row or column from Table Actions, the context menu, the Table menu, or keyboard shortcuts.
- Use Command-Delete to remove selected rows and Command-Option-Delete to remove selected columns; plain Delete continues to clear cell contents.
- Keep hidden columns and the active filter aligned through column deletion, Undo, and Redo.

### Credits

- Multi-row and multi-column editing was contributed by Tatum Bisley.

### Native macOS polish

- Creates a new, immediately editable CSV from File → New CSV or Command-N using the standard Save panel.
- Shows the ten most recently opened CSV files in File → Open Recent, with the standard Clear Menu action.
- Commits an active cell edit and moves one visible cell to the right with Shift-Return.
- Keeps empty tabs quiet by showing only the Open action until a CSV is loaded.
- Groups row and column commands into compact native toolbar menus and adds clear tooltips.
- Uses the standard macOS search field, including its built-in search and clear controls.
- Reports filtered rows and visible columns accurately in the status bar.
- Adds the expected Copy, Paste, and Clear Contents cell context menu.
- Makes Tab and Shift-Tab skip hidden columns and wrap naturally between rows.
- Restores the last file away from the main thread so a slow or unavailable file cannot freeze launch.

## Version 1.2 — 21 July 2026

### Faster navigation and focused views

- Double-clicking any cell now starts editing through the same reliable path as pressing Return or Enter.
- Show or hide individual columns from the native right-hand Columns sidebar without changing the CSV.
- Filter rows live by selecting a column and typing a case-insensitive search in the same sidebar.
- Sort filtered results by clicking column headings, and clear the filter to restore every row.

## Version 1.1 — 21 July 2026

### Work with several files

- Open multiple CSV files at once, with each file placed in its own native macOS Tahoe tab.
- Open additional tabs or separate windows, and move between documents using standard Mac controls.
- Select several files in the Open dialog or drag several CSVs into Don CSV together.
- Reopening a file that is already open takes you to its existing tab.

### Faster table editing

- Click anywhere in a cell to select it more reliably.
- Click a column heading to alternate between descending and ascending sort order.
- Click the `#` row-number heading to return to the CSV's original order.
- Right-click a column heading to rename it.
- Improved column-heading sizing, row-number alignment, and table-edge spacing.

### Live files and autosave

- Open CSVs now stay live: changes made by an AI tool or another app appear automatically.
- Filesystem events update the table promptly, with a background safety check for missed events and atomic file replacements.
- Don CSV continues to autosave edits made in the app.
- If an external edit arrives while an autosave is pending, the external version is preserved rather than overwritten.

### Native macOS experience

- Uses the stock macOS Tahoe tab interface without custom tab styling.
- Improved multi-window document routing, Finder opening, and restoration of the last open file.
- Requires macOS Tahoe 26 or later.
