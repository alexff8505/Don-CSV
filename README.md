# Don CSV

A small, native macOS CSV editor written in Swift and SwiftUI.

## Run

Open `Package.swift` in Xcode and press Run, or use:

```sh
swift run DonCSV
```

## Features

- Native, editable macOS table
- Columns start wide enough for their content and remain user-resizable
- Numbers-style cell interaction: click to select, arrows/Tab to move,
  type to replace, double-click or Return to edit, and Escape to cancel
- Native alternating row stripes with a non-CSV row-number gutter
- Select a column and use the pencil toolbar action to rename it; header
  double-click is also supported
- Shift-click or Shift-arrow to select rectangular cell ranges
- Copy and paste selected ranges while preserving their row/column pattern
- Paste tab/newline spreadsheet data; a single value fills a larger selection
- Automatic saving after edits
- External file changes appear within about one second
- Add and delete rows or columns
- CSV quoting, embedded commas, and multiline fields are preserved
- Drag-and-drop CSV opening

The first row is displayed as the table's column headings and remains editable as the first data row.
