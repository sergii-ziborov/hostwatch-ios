import Foundation

enum MarkdownNotes {
    static func parse(kind: String, project: String, markdown: String) -> [ImportedNote] {
        let now = ISO8601DateFormatter().string(from: .now)
        var notes: [ImportedNote] = []
        var currentProject = project
        for raw in markdown.components(separatedBy: .newlines) {
            let marker = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if marker == "<!-- hostwatch-project: -->" { if project.isEmpty { currentProject = "" }; continue }
            if marker.hasPrefix("<!-- hostwatch-project: "), marker.hasSuffix(" -->") {
                if project.isEmpty { currentProject = String(marker.dropFirst("<!-- hostwatch-project: ".count).dropLast(" -->".count)) }
                continue
            }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-*# "))
            guard !line.isEmpty else { continue }
            if kind == "vulnerability" {
                guard let id = firstMatch(in: line, pattern: #"(?i)\b((?:CVE|GHSA|OSV|RUSTSEC|PYSEC|GO)-\S+)"#) else { continue }
                notes.append(.init(id: "\(kind)-\(id)-\(notes.count)", kind: kind, projectId: currentProject, title: id.uppercased(), detail: line, severity: firstMatch(in: line, pattern: #"(?i)\b(critical|high|medium|low)\b"#) ?? "unknown", url: nil, createdAt: now))
            } else if let status = firstMatch(in: line, pattern: #"\b([45]\d\d)\s+(GET|POST|PUT|PATCH|DELETE|HEAD)\s+(\S+)"#) {
                notes.append(.init(id: "\(kind)-\(status)-\(notes.count)", kind: "error", projectId: currentProject, title: status, detail: line, severity: status.hasPrefix("5") ? "high" : "medium", url: nil, createdAt: now))
            }
        }
        return notes
    }

    static func export(kind: String, projects: [ProjectHealth], groups: [ErrorProjectGroup]) -> String {
        if kind == "error" {
            var body = "# Hostwatch errors\n\n"
            for group in groups {
                body += "<!-- hostwatch-project: \(group.projectId == "unmapped" ? "" : group.projectId) -->\n## \(group.projectName)\n\n"
                for request in group.requests {
                    body += "- \(request.time) \(request.status) \(request.method) \(request.path) · \(request.host) · \(request.id)\n"
                }
                body += "\n"
            }
            return body
        }
        var body = "# Hostwatch vulnerabilities\n\n"
        for project in projects {
            let items = project.vulnerabilities ?? []
            guard !items.isEmpty else { continue }
            body += "<!-- hostwatch-project: \(project.id) -->\n## \(project.name)\n\n"
            for item in items {
                body += "- \(item.id) (\(item.severity)) `\(item.package)` \(item.installedVersion) → \(item.fixedVersion) — \(item.summary)\n"
            }
            body += "\n"
        }
        return body
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let value = Range(match.range(at: 0), in: text) else { return nil }
        if match.numberOfRanges >= 4, let status = Range(match.range(at: 1), in: text), let method = Range(match.range(at: 2), in: text), let path = Range(match.range(at: 3), in: text) {
            return "\(text[status]) \(text[method]) \(text[path])"
        }
        return String(text[value])
    }
}
