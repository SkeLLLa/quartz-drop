import Foundation

/// Minimal in-place edits of top-level config keys that keep the rest of the file, including
/// comments, untouched.
public enum ConfigEditor {
    /// Returns `text` with the top-level `key` set to `value`.
    ///
    /// Replaces an existing assignment, otherwise uncomments a commented-out one such as
    /// `# menu_bar = true`, otherwise inserts the key before the first table.
    public static func setTopLevel(_ key: String, to value: Bool, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let assignment = "\(key) = \(value)"
        let firstTable =
            lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }
            ?? lines.count

        if let index = lines[..<firstTable].firstIndex(where: { assigns(key, $0) }) {
            lines[index] = assignment + trailingComment(lines[index])
        } else if let index = lines[..<firstTable].firstIndex(where: { commentedAssigns(key, $0) })
        {
            let uncommented = lines[index].drop { $0 == " " || $0 == "\t" || $0 == "#" }
            lines[index] = assignment + trailingComment(String(uncommented))
        } else if firstTable == lines.count {
            if lines.last == "" { lines.removeLast() }
            lines.append(assignment)
            lines.append("")
        } else {
            lines.insert(contentsOf: [assignment, ""], at: firstTable)
        }
        return lines.joined(separator: "\n")
    }

    private static func assigns(_ key: String, _ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for name in [key, "\"\(key)\"", "'\(key)'"] where trimmed.hasPrefix(name) {
            if trimmed.dropFirst(name.count).trimmingCharacters(in: .whitespaces).hasPrefix("=") {
                return true
            }
        }
        return false
    }

    private static func commentedAssigns(_ key: String, _ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return false }
        return assigns(key, String(trimmed.drop { $0 == "#" }))
    }

    /// The `# ...` comment after a `key = value` assignment, with its leading spaces.
    private static func trailingComment(_ line: String) -> String {
        guard let equals = line.firstIndex(of: "="),
            let hash = line[equals...].firstIndex(of: "#")
        else { return "" }
        var start = hash
        while start > equals, line[line.index(before: start)] == " " {
            start = line.index(before: start)
        }
        return String(line[start...])
    }
}
