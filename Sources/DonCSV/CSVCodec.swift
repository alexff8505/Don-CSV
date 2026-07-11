import Foundation

enum CSVCodec {
    static func decode(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        // Swift treats CRLF as one extended grapheme, so normalize it before
        // scanning individual characters. Embedded quoted line breaks remain
        // line breaks and are written back as standard LF-delimited CSV.
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    isQuoted.toggle()
                }
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !isQuoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }

            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map(escape).joined(separator: ",")
        }
        .joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
