# Don CSV

A small, native macOS CSV editor written in Swift and SwiftUI.

Requires macOS Tahoe 26 or later.

## Run

Open `Package.swift` in Xcode and press Run, or use:

```sh
swift run DonCSV
```

## Features

- Native, editable macOS table
- Open several CSV files at once in native tabs, with support for separate windows
- New files open in tabs by default; reopening an open file focuses its existing tab
- Columns start wide enough for their content and remain user-resizable
- Full-cell single-click targets with Numbers-style interaction: click to select, arrows/Tab to move,
  type to replace, double-click or Return to edit, and Escape to cancel
- Native alternating row stripes with a non-CSV row-number gutter
- Click a column header to alternate descending/ascending sort; click `#` to restore file order
- Right-click a column header to rename it, or select a cell and use the toolbar's Table Actions menu
- Right-click a cell for standard Copy, Paste, and Clear Contents actions
- Use the native right-hand Inspector to show or hide individual columns without changing the CSV
- Filter rows from the same sidebar by choosing a column and typing a case-insensitive search
- Tab and Shift-Tab move across visible columns and wrap naturally between rows
- Shift-click or Shift-arrow to select rectangular cell ranges
- Copy and paste selected ranges while preserving their row/column pattern
- Paste tab/newline spreadsheet data; a single value fills a larger selection
- Automatic saving after edits
- Open files stay live as external changes appear automatically, alongside in-app autosave
- Add and delete rows or columns
- CSV quoting, embedded commas, and multiline fields are preserved
- Drag-and-drop CSV opening
- Open CSV files directly from Finder
- Undo and redo edits, pastes, and row or column changes
- Reopen the last file and restore the window size on launch

The first CSV row is displayed exclusively as the editable table headings; data rows begin underneath it.
