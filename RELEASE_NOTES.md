# Don CSV Release Notes

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
- Show or hide individual columns from the native right-hand Columns sidebar without changing the CSV.
- Filter rows live by selecting a column and typing a case-insensitive search in the same sidebar.
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
