
import Foundation

enum SecurityAuditExporter {
    static func json(_ report: AuditReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(report)
    }

    static func html(_ report: AuditReport) -> Data {
        func escape(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }

        let rows = report.findings.map { finding in
            """
            <tr>
              <td>\(escape(finding.severity.rawValue))</td>
              <td>\(escape(finding.category))</td>
              <td>\(escape(finding.title))</td>
              <td>\(escape(finding.details))</td>
              <td><pre>\(escape(finding.evidence))</pre></td>
              <td>\(escape(finding.recommendation))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>MacInfo Security Audit</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont,
                           "Segoe UI", sans-serif;
              margin: 40px;
              color: #222;
            }
            h1 { margin-bottom: 8px; }
            .meta { color: #666; margin-bottom: 24px; }
            .score {
              font-size: 28px;
              font-weight: 700;
              margin-bottom: 24px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 13px;
            }
            th, td {
              border: 1px solid #ddd;
              padding: 10px;
              text-align: left;
              vertical-align: top;
            }
            th { background: #f3f4f6; }
            tr:nth-child(even) { background: #fafafa; }
            pre {
              white-space: pre-wrap;
              overflow-wrap: anywhere;
            }
          </style>
        </head>
        <body>
          <h1>MacInfo Security Audit</h1>
          <div class="meta">
            Computer: \(escape(report.computerName))<br>
            macOS: \(escape(report.macOSVersion))<br>
            Scan: \(escape(report.createdAt.description))
          </div>
          <div class="score">
            Heuristic Score: \(report.score) / 100
          </div>
          <p>
            Applications scanned: \(report.applicationCount)<br>
            Startup items scanned: \(report.startupItemCount)<br>
            Findings: \(report.findings.count)
          </p>
          <table>
            <thead>
              <tr>
                <th>Severity</th>
                <th>Category</th>
                <th>Finding</th>
                <th>Details</th>
                <th>Evidence</th>
                <th>Recommendation</th>
              </tr>
            </thead>
            <tbody>
              \(rows)
            </tbody>
          </table>
          <p>
            This report contains heuristic findings,
            not confirmed malware detections.
          </p>
        </body>
        </html>
        """

        return Data(html.utf8)
    }
}
